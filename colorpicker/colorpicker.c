#define _GNU_SOURCE
#include <errno.h>
#include <getopt.h>
#include <linux/input-event-codes.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <unistd.h>

#include <wayland-client.h>

#include "viewporter-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "wlr-screencopy-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

/* ------------------------------------------------------------------------ */
/* Consts                                                                   */
/* ------------------------------------------------------------------------ */

#define MAX_OUTPUTS   16
#define LOUPE_R       84   /* Lens Ray                                      */
#define ZOOM_MIN      3
#define ZOOM_MAX      25
#define ZOOM_DEFAULT  9    /* showed screen pixel (x ui_scale)              */

/* ------------------------------------------------------------------------ */
/* Utilities                                                                */
/* ------------------------------------------------------------------------ */

static void die(const char *fmt, ...) __attribute__((noreturn, format(printf, 1, 2)));
static void die(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "colorpicker: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    exit(1);
}

static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }
static inline int iclamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

static inline int floordiv(int a, int b)
{
    int q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0)))
        q--;
    return q;
}

static inline int posmod(int a, int b)
{
    int m = a % b;
    return m < 0 ? m + b : m;
}

/* Retângulo semiaberto [x0,x1) x [y0,y1) */
typedef struct { int x0, y0, x1, y1; } Rect;

static inline Rect rect_empty(void) { return (Rect){0, 0, 0, 0}; }
static inline bool rect_is_empty(Rect r) { return r.x1 <= r.x0 || r.y1 <= r.y0; }

static Rect rect_union(Rect a, Rect b)
{
    if (rect_is_empty(a)) return b;
    if (rect_is_empty(b)) return a;
    return (Rect){imin(a.x0, b.x0), imin(a.y0, b.y0), imax(a.x1, b.x1), imax(a.y1, b.y1)};
}

static Rect rect_clip(Rect r, int w, int h)
{
    r.x0 = imax(r.x0, 0);
    r.y0 = imax(r.y0, 0);
    r.x1 = imin(r.x1, w);
    r.y1 = imin(r.y1, h);
    return rect_is_empty(r) ? rect_empty() : r;
}

/* ------------------------------------------------------------------------ */
/* Formatação de cores                                                      */
/* ------------------------------------------------------------------------ */

enum color_fmt { FMT_HEX, FMT_RGB, FMT_HSL, FMT_HSV, FMT_CMYK, FMT_COUNT };

static const char *const fmt_names[FMT_COUNT] = {"hex", "rgb", "hsl", "hsv", "cmyk"};

static void format_color(char *out, size_t n, uint32_t rgb, enum color_fmt f, bool lower)
{
    int r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
    double rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    double mx = fmax(rf, fmax(gf, bf)), mn = fmin(rf, fmin(gf, bf));
    double d = mx - mn, h = 0.0;

    if (d > 0.0) {
        if (mx == rf)      h = 60.0 * fmod((gf - bf) / d, 6.0);
        else if (mx == gf) h = 60.0 * ((bf - rf) / d + 2.0);
        else               h = 60.0 * ((rf - gf) / d + 4.0);
        if (h < 0.0) h += 360.0;
    }
    int hi = (int)lround(h) % 360;

    switch (f) {
    case FMT_HEX:
        snprintf(out, n, lower ? "#%02x%02x%02x" : "#%02X%02X%02X", r, g, b);
        break;
    case FMT_RGB:
        snprintf(out, n, "rgb(%d, %d, %d)", r, g, b);
        break;
    case FMT_HSL: {
        double l = (mx + mn) / 2.0;
        double s = d == 0.0 ? 0.0 : d / (1.0 - fabs(2.0 * l - 1.0));
        snprintf(out, n, "hsl(%d, %d%%, %d%%)", hi, (int)lround(s * 100), (int)lround(l * 100));
        break;
    }
    case FMT_HSV: {
        double s = mx == 0.0 ? 0.0 : d / mx;
        snprintf(out, n, "hsv(%d, %d%%, %d%%)", hi, (int)lround(s * 100), (int)lround(mx * 100));
        break;
    }
    case FMT_CMYK: {
        double k = 1.0 - mx, c = 0, m = 0, y = 0;
        if (k < 1.0) {
            c = (1.0 - rf - k) / (1.0 - k);
            m = (1.0 - gf - k) / (1.0 - k);
            y = (1.0 - bf - k) / (1.0 - k);
        }
        snprintf(out, n, "cmyk(%d%%, %d%%, %d%%, %d%%)", (int)lround(c * 100),
                 (int)lround(m * 100), (int)lround(y * 100), (int)lround(k * 100));
        break;
    }
    default:
        out[0] = '\0';
    }
}

/* ------------------------------------------------------------------------ */
/*   bitmap 5x7 (Colums, bit0 = Top). ASCII 0x20..0x7A.                     */
/* included so we don't depend of Pango                                     */
/* ------------------------------------------------------------------------ */

static const uint8_t font5x7[91][5] = {
    {0x00,0x00,0x00,0x00,0x00}, {0x00,0x00,0x5F,0x00,0x00}, {0x00,0x07,0x00,0x07,0x00}, /*  ! " */
    {0x14,0x7F,0x14,0x7F,0x14}, {0x24,0x2A,0x7F,0x2A,0x12}, {0x23,0x13,0x08,0x64,0x62}, /* # $ % */
    {0x36,0x49,0x56,0x20,0x50}, {0x00,0x08,0x07,0x03,0x00}, {0x00,0x1C,0x22,0x41,0x00}, /* & ' ( */
    {0x00,0x41,0x22,0x1C,0x00}, {0x2A,0x1C,0x7F,0x1C,0x2A}, {0x08,0x08,0x3E,0x08,0x08}, /* ) * + */
    {0x00,0x80,0x70,0x30,0x00}, {0x08,0x08,0x08,0x08,0x08}, {0x00,0x00,0x60,0x60,0x00}, /* , - . */
    {0x20,0x10,0x08,0x04,0x02},                                                         /* /     */
    {0x3E,0x51,0x49,0x45,0x3E}, {0x00,0x42,0x7F,0x40,0x00}, {0x72,0x49,0x49,0x49,0x46}, /* 0 1 2 */
    {0x21,0x41,0x49,0x4D,0x33}, {0x18,0x14,0x12,0x7F,0x10}, {0x27,0x45,0x45,0x45,0x39}, /* 3 4 5 */
    {0x3C,0x4A,0x49,0x49,0x31}, {0x41,0x21,0x11,0x09,0x07}, {0x36,0x49,0x49,0x49,0x36}, /* 6 7 8 */
    {0x46,0x49,0x49,0x29,0x1E},                                                         /* 9     */
    {0x00,0x00,0x14,0x00,0x00}, {0x00,0x40,0x34,0x00,0x00}, {0x00,0x08,0x14,0x22,0x41}, /* : ; < */
    {0x14,0x14,0x14,0x14,0x14}, {0x00,0x41,0x22,0x14,0x08}, {0x02,0x01,0x59,0x09,0x06}, /* = > ? */
    {0x3E,0x41,0x5D,0x59,0x4E},                                                         /* @     */
    {0x7C,0x12,0x11,0x12,0x7C}, {0x7F,0x49,0x49,0x49,0x36}, {0x3E,0x41,0x41,0x41,0x22}, /* A B C */
    {0x7F,0x41,0x41,0x41,0x3E}, {0x7F,0x49,0x49,0x49,0x41}, {0x7F,0x09,0x09,0x09,0x01}, /* D E F */
    {0x3E,0x41,0x41,0x51,0x73}, {0x7F,0x08,0x08,0x08,0x7F}, {0x00,0x41,0x7F,0x41,0x00}, /* G H I */
    {0x20,0x40,0x41,0x3F,0x01}, {0x7F,0x08,0x14,0x22,0x41}, {0x7F,0x40,0x40,0x40,0x40}, /* J K L */
    {0x7F,0x02,0x1C,0x02,0x7F}, {0x7F,0x04,0x08,0x10,0x7F}, {0x3E,0x41,0x41,0x41,0x3E}, /* M N O */
    {0x7F,0x09,0x09,0x09,0x06}, {0x3E,0x41,0x51,0x21,0x5E}, {0x7F,0x09,0x19,0x29,0x46}, /* P Q R */
    {0x26,0x49,0x49,0x49,0x32}, {0x03,0x01,0x7F,0x01,0x03}, {0x3F,0x40,0x40,0x40,0x3F}, /* S T U */
    {0x1F,0x20,0x40,0x20,0x1F}, {0x3F,0x40,0x38,0x40,0x3F}, {0x63,0x14,0x08,0x14,0x63}, /* V W X */
    {0x03,0x04,0x78,0x04,0x03}, {0x61,0x59,0x49,0x4D,0x43},                             /* Y Z   */
    {0x00,0x7F,0x41,0x41,0x00}, {0x02,0x04,0x08,0x10,0x20}, {0x00,0x41,0x41,0x7F,0x00}, /* [ \ ] */
    {0x04,0x02,0x01,0x02,0x04}, {0x40,0x40,0x40,0x40,0x40}, {0x00,0x01,0x02,0x04,0x00}, /* ^ _ ` */
    {0x20,0x54,0x54,0x54,0x78}, {0x7F,0x48,0x44,0x44,0x38}, {0x38,0x44,0x44,0x44,0x28}, /* a b c */
    {0x38,0x44,0x44,0x48,0x7F}, {0x38,0x54,0x54,0x54,0x18}, {0x08,0x7E,0x09,0x01,0x02}, /* d e f */
    {0x18,0xA4,0xA4,0xA4,0x78}, {0x7F,0x08,0x04,0x04,0x78}, {0x00,0x44,0x7D,0x40,0x00}, /* g h i */
    {0x20,0x40,0x44,0x3D,0x00}, {0x7F,0x10,0x28,0x44,0x00}, {0x00,0x41,0x7F,0x40,0x00}, /* j k l */
    {0x7C,0x04,0x78,0x04,0x78}, {0x7C,0x08,0x04,0x04,0x78}, {0x38,0x44,0x44,0x44,0x38}, /* m n o */
    {0xFC,0x24,0x24,0x24,0x18}, {0x18,0x24,0x24,0x24,0xFC}, {0x7C,0x08,0x04,0x04,0x08}, /* p q r */
    {0x48,0x54,0x54,0x54,0x20}, {0x04,0x3F,0x44,0x40,0x20}, {0x3C,0x40,0x40,0x20,0x7C}, /* s t u */
    {0x1C,0x20,0x40,0x20,0x1C}, {0x3C,0x40,0x30,0x40,0x3C}, {0x44,0x28,0x10,0x28,0x44}, /* v w x */
    {0x4C,0x90,0x90,0x90,0x7C}, {0x44,0x64,0x54,0x4C,0x44},                             /* y z   */
};

/* ------------------------------------------------------------------------ */
/*                              (XRGB8888)                                  */
/* ------------------------------------------------------------------------ */

struct canvas {
    uint32_t *px;
    int w, h;
};

static inline uint32_t mix_rgb(uint32_t dst, uint32_t src, int a)
{
    if (a <= 0) return dst;
    if (a >= 255) return src & 0xFFFFFF;
    int ia = 255 - a;
    uint32_t r = (((src >> 16) & 0xFF) * a + ((dst >> 16) & 0xFF) * ia + 127) / 255;
    uint32_t g = (((src >> 8) & 0xFF) * a + ((dst >> 8) & 0xFF) * ia + 127) / 255;
    uint32_t b = ((src & 0xFF) * a + (dst & 0xFF) * ia + 127) / 255;
    return (r << 16) | (g << 8) | b;
}

static inline void put_px(struct canvas *c, int x, int y, uint32_t col, int a)
{
    if ((unsigned)x >= (unsigned)c->w || (unsigned)y >= (unsigned)c->h)
        return;
    uint32_t *p = &c->px[(size_t)y * c->w + x];
    *p = mix_rgb(*p & 0xFFFFFF, col, a);
}

static void fill_rect(struct canvas *c, int x, int y, int w, int h, uint32_t col, int a)
{
    int x0 = imax(x, 0), y0 = imax(y, 0), x1 = imin(x + w, c->w), y1 = imin(y + h, c->h);
    for (int j = y0; j < y1; j++)
        for (int i = x0; i < x1; i++)
            put_px(c, i, j, col, a);
}

static void outline_rect(struct canvas *c, int x, int y, int w, int h, int t, uint32_t col)
{
    fill_rect(c, x, y, w, t, col, 255);
    fill_rect(c, x, y + h - t, w, t, col, 255);
    fill_rect(c, x, y, t, h, col, 255);
    fill_rect(c, x + w - t, y, t, h, col, 255);
}

static void fill_round_rect(struct canvas *c, int x, int y, int w, int h, int r,
                            uint32_t col, int a)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            double px = i + 0.5, py = j + 0.5, dx = 0, dy = 0;
            if (px < r)           dx = r - px;
            else if (px > w - r)  dx = px - (w - r);
            if (py < r)           dy = r - py;
            else if (py > h - r)  dy = py - (h - r);
            double d = sqrt(dx * dx + dy * dy);
            double cov = d <= r - 0.5 ? 1.0 : (d >= r + 0.5 ? 0.0 : r + 0.5 - d);
            if (cov > 0.0)
                put_px(c, x + i, y + j, col, (int)(a * cov));
        }
    }
}

static int text_width(const char *s, int scale)
{
    int n = (int)strlen(s);
    return n ? (n * 6 - 1) * scale : 0;
}

static void draw_text(struct canvas *c, int x, int y, const char *s, int scale, uint32_t col)
{
    for (; *s; s++, x += 6 * scale) {
        unsigned ch = (unsigned char)*s;
        if (ch < 0x20 || ch > 0x7A)
            continue;
        const uint8_t *g = font5x7[ch - 0x20];
        for (int cx = 0; cx < 5; cx++)
            for (int cy = 0; cy < 8; cy++)
                if (g[cx] & (1u << cy))
                    fill_rect(c, x + cx * scale, y + cy * scale, scale, scale, col, 255);
    }
}

/* ------------------------------------------------------------------------ */
/*           Overlay drawing / Wayland independent                          */
/* ------------------------------------------------------------------------ */

static Rect draw_overlay(struct canvas *c, const uint32_t *src, int ui, int cx, int cy,
                         int zoom, enum color_fmt fmt, bool lower)
{
    const int R = LOUPE_R * ui;
    const int cell = zoom * ui;
    const int half = cell / 2;

    /* --- lupa circular ------------------------------------------------- */
    int ya = imax(-R - 2, -cy), yb = imin(R + 2, c->h - 1 - cy);
    int xa = imax(-R - 2, -cx), xb = imin(R + 2, c->w - 1 - cx);
    for (int dy = ya; dy <= yb; dy++) {
        for (int dx = xa; dx <= xb; dx++) {
            double d = sqrt((double)dx * dx + (double)dy * dy);
            double cov = R + 1.0 - d;
            if (cov <= 0.0) continue;
            if (cov > 1.0) cov = 1.0;

            uint32_t col;
            if (d <= R - 4 * ui) {
                int sx = cx + floordiv(dx + half, cell);
                int sy = cy + floordiv(dy + half, cell);
                if (sx < 0 || sy < 0 || sx >= c->w || sy >= c->h)
                    col = 0x202020;
                else
                    col = src[(size_t)sy * c->w + sx] & 0xFFFFFF;
                if (cell >= 7 * ui && (posmod(dx + half, cell) == 0 || posmod(dy + half, cell) == 0))
                    col = mix_rgb(col, 0x000000, 48); /* linhas de grade discretas */
            } else if (d <= R - ui) {
                col = 0xFFFFFF;                        /* anel branco  */
            } else {
                col = 0x1A1A1A;                        /* contorno     */
            }
            put_px(c, cx + dx, cy + dy, col, (int)(255 * cov));
        }
    }

    /* destaque do pixel central (preto por fora, branco por dentro) */
    outline_rect(c, cx - half - ui, cy - half - ui, cell + 2 * ui, cell + 2 * ui, ui, 0x000000);
    outline_rect(c, cx - half, cy - half, cell, cell, ui, 0xFFFFFF);

    /* --- painel com o valor -------------------------------------------- */
    uint32_t col = src[(size_t)cy * c->w + cx] & 0xFFFFFF;
    char text[64];
    format_color(text, sizeof text, col, fmt, lower);

    const char *hint = "Tab: formato  Esc: sair";
    int s1 = 2 * ui, s2 = ui;
    int pad = 8 * ui, sw = 32 * ui;
    int tw = text_width(text, s1), hw = text_width(hint, s2);
    int pw = pad + sw + pad + imax(tw, hw) + pad;
    int ph = 2 * pad + sw;

    int px = cx - pw / 2;
    int py = cy + R + 10 * ui;
    if (py + ph > c->h - 4 * ui)
        py = cy - R - 10 * ui - ph; /* sem espaço embaixo: vai para cima */
    if (px + pw > c->w - 4 * ui) px = c->w - 4 * ui - pw;
    if (px < 4 * ui) px = 4 * ui;
    if (py < 0) py = 0;

    fill_round_rect(c, px, py, pw, ph, 6 * ui, 0x16161A, 235);
    fill_round_rect(c, px + pad, py + pad, sw, sw, 4 * ui, 0xFFFFFF, 255);
    fill_round_rect(c, px + pad + ui, py + pad + ui, sw - 2 * ui, sw - 2 * ui, 3 * ui, col, 255);

    int block_h = 8 * s1 + 4 * ui + 8 * s2;
    int ty = py + (ph - block_h) / 2;
    int tx = px + pad + sw + pad;
    draw_text(c, tx, ty, text, s1, 0xFFFFFF);
    draw_text(c, tx, ty + 8 * s1 + 4 * ui, hint, s2, 0x9A9AA5);

    Rect loupe = {cx - R - 2, cy - R - 2, cx + R + 3, cy + R + 3};
    Rect panel = {px, py, px + pw, py + ph};
    return rect_union(loupe, panel);
}

/* ------------------------------------------------------------------------ */
/* Estado da aplicação                                                      */
/* ------------------------------------------------------------------------ */

struct output;

struct shmbuf {
    struct wl_buffer *buffer;
    uint32_t *data;
    size_t size;
    bool busy;
    Rect drawn;            /* overlay area in THIS buffer */
    struct output *owner;
};

struct output {
    struct wl_output *wl_output;

    /* captura (pixels físicos) */
    struct zwlr_screencopy_frame_v1 *frame;
    struct wl_buffer *cap_buffer;
    void *cap_data;
    size_t cap_size;
    uint32_t cap_format, cap_stride;
    uint32_t buf_w, buf_h;
    bool y_invert;
    uint32_t *frozen;      /* XRGB8888 */

    /* superfície */
    struct wl_surface *surface;
    struct wp_viewport *viewport;
    struct zwlr_layer_surface_v1 *layer;
    int lw, lh;            /* Logic size */
    int ui;                /*  Scale factor (>=1) */
    bool configured, first_commit, needs_redraw;
    struct shmbuf bufs[2];
    Rect displayed;        /* overlay area currently visible */
};

struct app {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct wl_seat *seat;
    struct wl_pointer *pointer;
    struct wl_keyboard *keyboard;
    struct zwlr_layer_shell_v1 *layer_shell;
    struct zwlr_screencopy_manager_v1 *screencopy;
    struct wp_viewporter *viewporter;
    uint32_t compositor_version;

    struct output outputs[MAX_OUTPUTS];
    int n_outputs;
    int pending_captures;

    /* i got tired of translating, sorry */
    /* interação */
    struct output *active;    /* monitor sob o ponteiro */
    int cur_x, cur_y;         /* pixel sob o cursor (coords do buffer) */
    int zoom;
    enum color_fmt format;
    bool shift;
    double scroll_acc;

    /* repetição de tecla */
    int repeat_fd;
    uint32_t repeat_key;
    int32_t repeat_rate, repeat_delay;

    /* opções */
    bool lowercase, no_newline, autocopy;

    /* resultado */
    bool done, picked;
    char result[64];
};

static struct app app;

/* ------------------------------------------------------------------------ */
/* Memória compartilhada (wl_shm)                                           */
/* ------------------------------------------------------------------------ */

static int create_shm_file(size_t size)
{
    int fd = memfd_create("colorpicker-shm", MFD_CLOEXEC);
    if (fd < 0)
        return -1;
    if (ftruncate(fd, (off_t)size) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void buffer_release(void *data, struct wl_buffer *buf)
{
    (void)buf;
    struct shmbuf *b = data;
    b->busy = false;
}
static const struct wl_buffer_listener buffer_listener = {.release = buffer_release};

static void output_render(struct output *o);

static void shmbuf_create(struct shmbuf *b, struct output *o, const uint32_t *init)
{
    int w = (int)o->buf_w, h = (int)o->buf_h;
    b->size = (size_t)w * h * 4;
    int fd = create_shm_file(b->size);
    if (fd < 0)
        die("falha ao criar memória compartilhada: %s", strerror(errno));
    b->data = mmap(NULL, b->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (b->data == MAP_FAILED)
        die("mmap falhou: %s", strerror(errno));
    struct wl_shm_pool *pool = wl_shm_create_pool(app.shm, fd, (int32_t)b->size);
    b->buffer = wl_shm_pool_create_buffer(pool, 0, w, h, w * 4, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    memcpy(b->data, init, b->size);
    b->busy = false;
    b->drawn = rect_empty();
    b->owner = o;
    wl_buffer_add_listener(b->buffer, &buffer_listener, b);
}

/* ------------------------------------------------------------------------ */
/* Renderização incremental por monitor                                     */
/* ------------------------------------------------------------------------ */

static void restore_rect(struct shmbuf *b, const uint32_t *frozen, int W, int H, Rect r)
{
    r = rect_clip(r, W, H);
    if (rect_is_empty(r))
        return;
    for (int y = r.y0; y < r.y1; y++)
        memcpy(b->data + (size_t)y * W + r.x0, frozen + (size_t)y * W + r.x0,
               (size_t)(r.x1 - r.x0) * 4);
}

/*
 * Buffer duplo + "dano" mínimo: cada buffer lembra onde desenhou o overlay;
 * ao reutilizá-lo, restauramos só essa região a partir da captura congelada.
 * Dano enviado = união(overlay anterior visível, overlay novo).
 */
static void output_render(struct output *o)
{
    if (!o->configured)
        return;

    struct shmbuf *b = NULL;
    for (int i = 0; i < 2; i++) {
        if (!o->bufs[i].busy) {
            b = &o->bufs[i];
            break;
        }
    }
    if (!b) {                    /* ambos em uso pelo compositor: tenta depois */
        o->needs_redraw = true;
        return;
    }
    o->needs_redraw = false;

    int W = (int)o->buf_w, H = (int)o->buf_h;
    restore_rect(b, o->frozen, W, H, b->drawn);

    Rect now = rect_empty();
    if (app.active == o) {
        struct canvas c = {b->data, W, H};
        now = rect_clip(draw_overlay(&c, o->frozen, o->ui, app.cur_x, app.cur_y, app.zoom,
                                     app.format, app.lowercase), W, H);
    }

    Rect dmg = o->first_commit ? (Rect){0, 0, W, H}
                               : rect_clip(rect_union(o->displayed, now), W, H);
    if (rect_is_empty(dmg))
        return;

    o->displayed = now;
    b->drawn = now;
    b->busy = true;
    o->first_commit = false;

    wl_surface_attach(o->surface, b->buffer, 0, 0);
    wl_surface_damage_buffer(o->surface, dmg.x0, dmg.y0, dmg.x1 - dmg.x0, dmg.y1 - dmg.y0);
    wl_surface_commit(o->surface);
}

/* Repete a renderização pendente quando um buffer é liberado. */
static void flush_pending_redraws(void)
{
    for (int i = 0; i < app.n_outputs; i++)
        if (app.outputs[i].needs_redraw)
            output_render(&app.outputs[i]);
}

/* ------------------------------------------------------------------------ */
/* Captura de tela (wlr-screencopy)                                         */
/* ------------------------------------------------------------------------ */

static inline uint32_t to_xrgb(uint32_t fmt, uint32_t p)
{
    switch (fmt) {
    case WL_SHM_FORMAT_ARGB8888:
    case WL_SHM_FORMAT_XRGB8888:
        return p & 0xFFFFFF;
    case WL_SHM_FORMAT_ABGR8888:
    case WL_SHM_FORMAT_XBGR8888:
        return ((p & 0xFF) << 16) | (p & 0xFF00) | ((p >> 16) & 0xFF);
    case WL_SHM_FORMAT_ARGB2101010:
    case WL_SHM_FORMAT_XRGB2101010: {
        uint32_t r = (p >> 22) & 0xFF, g = (p >> 12) & 0xFF, b = (p >> 2) & 0xFF;
        return (r << 16) | (g << 8) | b;
    }
    case WL_SHM_FORMAT_ABGR2101010:
    case WL_SHM_FORMAT_XBGR2101010: {
        uint32_t b = (p >> 22) & 0xFF, g = (p >> 12) & 0xFF, r = (p >> 2) & 0xFF;
        return (r << 16) | (g << 8) | b;
    }
    default:
        return 0;
    }
}

static bool format_supported(uint32_t fmt)
{
    switch (fmt) {
    case WL_SHM_FORMAT_ARGB8888: case WL_SHM_FORMAT_XRGB8888:
    case WL_SHM_FORMAT_ABGR8888: case WL_SHM_FORMAT_XBGR8888:
    case WL_SHM_FORMAT_ARGB2101010: case WL_SHM_FORMAT_XRGB2101010:
    case WL_SHM_FORMAT_ABGR2101010: case WL_SHM_FORMAT_XBGR2101010:
        return true;
    default:
        return false;
    }
}

static void frame_buffer(void *data, struct zwlr_screencopy_frame_v1 *frame, uint32_t format,
                         uint32_t width, uint32_t height, uint32_t stride)
{
    struct output *o = data;
    if (!format_supported(format))
        die("formato de captura não suportado (0x%08x)", format);

    o->cap_format = format;
    o->buf_w = width;
    o->buf_h = height;
    o->cap_stride = stride;
    o->cap_size = (size_t)stride * height;

    int fd = create_shm_file(o->cap_size);
    if (fd < 0)
        die("falha ao criar memória compartilhada: %s", strerror(errno));
    o->cap_data = mmap(NULL, o->cap_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (o->cap_data == MAP_FAILED)
        die("mmap falhou: %s", strerror(errno));

    struct wl_shm_pool *pool = wl_shm_create_pool(app.shm, fd, (int32_t)o->cap_size);
    o->cap_buffer = wl_shm_pool_create_buffer(pool, 0, (int32_t)width, (int32_t)height,
                                              (int32_t)stride, format);
    wl_shm_pool_destroy(pool);
    close(fd);

    zwlr_screencopy_frame_v1_copy(frame, o->cap_buffer);
}

static void frame_flags(void *data, struct zwlr_screencopy_frame_v1 *frame, uint32_t flags)
{
    (void)frame;
    struct output *o = data;
    o->y_invert = flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT;
}

static void frame_ready(void *data, struct zwlr_screencopy_frame_v1 *frame, uint32_t hi,
                        uint32_t lo, uint32_t nsec)
{
    (void)hi; (void)lo; (void)nsec;
    struct output *o = data;
    uint32_t w = o->buf_w, h = o->buf_h;

    o->frozen = malloc((size_t)w * h * 4);
    if (!o->frozen)
        die("sem memória");

    for (uint32_t y = 0; y < h; y++) {
        uint32_t sy = o->y_invert ? h - 1 - y : y;
        const uint8_t *row = (const uint8_t *)o->cap_data + (size_t)sy * o->cap_stride;
        uint32_t *dst = o->frozen + (size_t)y * w;
        for (uint32_t x = 0; x < w; x++) {
            uint32_t p;
            memcpy(&p, row + (size_t)x * 4, 4);
            dst[x] = to_xrgb(o->cap_format, p);
        }
    }

    wl_buffer_destroy(o->cap_buffer);
    munmap(o->cap_data, o->cap_size);
    o->cap_buffer = NULL;
    o->cap_data = NULL;
    zwlr_screencopy_frame_v1_destroy(frame);
    o->frame = NULL;
    app.pending_captures--;
}

static void frame_failed(void *data, struct zwlr_screencopy_frame_v1 *frame)
{
    (void)data; (void)frame;
    die("o compositor falhou ao capturar a tela");
}

static void frame_damage(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t a, uint32_t b,
                         uint32_t c, uint32_t e)
{ (void)d; (void)f; (void)a; (void)b; (void)c; (void)e; }
static void frame_linux_dmabuf(void *d, struct zwlr_screencopy_frame_v1 *f, uint32_t a,
                               uint32_t b, uint32_t c)
{ (void)d; (void)f; (void)a; (void)b; (void)c; }
static void frame_buffer_done(void *d, struct zwlr_screencopy_frame_v1 *f)
{ (void)d; (void)f; }

static const struct zwlr_screencopy_frame_v1_listener frame_listener = {
    .buffer = frame_buffer,
    .flags = frame_flags,
    .ready = frame_ready,
    .failed = frame_failed,
    .damage = frame_damage,
    .linux_dmabuf = frame_linux_dmabuf,
    .buffer_done = frame_buffer_done,
};

/* ------------------------------------------------------------------------ */
/* Superfícies layer-shell                                                  */
/* ------------------------------------------------------------------------ */

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *ls, uint32_t serial,
                            uint32_t w, uint32_t h)
{
    struct output *o = data;
    zwlr_layer_surface_v1_ack_configure(ls, serial);

    o->lw = w ? (int)w : (int)o->buf_w;
    o->lh = h ? (int)h : (int)o->buf_h;
    o->ui = imax(1, (int)lround((double)o->buf_w / o->lw));

    if (o->viewport)
        wp_viewport_set_destination(o->viewport, o->lw, o->lh);
    else
        wl_surface_set_buffer_scale(o->surface, o->ui); /* fallback sem viewporter */

    if (!o->configured) {
        shmbuf_create(&o->bufs[0], o, o->frozen);
        shmbuf_create(&o->bufs[1], o, o->frozen);
        o->configured = true;
        o->first_commit = true;
    }
    output_render(o);
}

static void layer_closed(void *data, struct zwlr_layer_surface_v1 *ls)
{
    (void)data; (void)ls;
    app.done = true;
}

static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = layer_configure,
    .closed = layer_closed,
};

static void output_create_surface(struct output *o)
{
    o->surface = wl_compositor_create_surface(app.compositor);
    if (app.viewporter)
        o->viewport = wp_viewporter_get_viewport(app.viewporter, o->surface);

    o->layer = zwlr_layer_shell_v1_get_layer_surface(app.layer_shell, o->surface, o->wl_output,
                                                     ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
                                                     "colorpicker");
    zwlr_layer_surface_v1_set_size(o->layer, 0, 0);
    zwlr_layer_surface_v1_set_anchor(o->layer,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(o->layer, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(
        o->layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
    zwlr_layer_surface_v1_add_listener(o->layer, &layer_listener, o);
    wl_surface_commit(o->surface);
}

/* ------------------------------------------------------------------------ */
/* Ações                                                                    */
/* ------------------------------------------------------------------------ */

static struct output *output_from_surface(struct wl_surface *s)
{
    for (int i = 0; i < app.n_outputs; i++)
        if (app.outputs[i].surface == s)
            return &app.outputs[i];
    return NULL;
}

static void clamp_cursor(struct output *o)
{
    app.cur_x = iclamp(app.cur_x, 0, (int)o->buf_w - 1);
    app.cur_y = iclamp(app.cur_y, 0, (int)o->buf_h - 1);
}

static void cursor_from_surface_coords(struct output *o, wl_fixed_t sx, wl_fixed_t sy)
{
    if (o->lw <= 0 || o->lh <= 0)
        return;
    app.cur_x = (int)floor(wl_fixed_to_double(sx) * (double)o->buf_w / o->lw);
    app.cur_y = (int)floor(wl_fixed_to_double(sy) * (double)o->buf_h / o->lh);
    clamp_cursor(o);
}

static void do_pick(void)
{
    struct output *o = app.active;
    if (!o || !o->frozen)
        return;
    uint32_t col = o->frozen[(size_t)app.cur_y * o->buf_w + app.cur_x] & 0xFFFFFF;
    format_color(app.result, sizeof app.result, col, app.format, app.lowercase);
    app.picked = true;
    app.done = true;
}

static void do_cancel(void) { app.done = true; }

static void cycle_format(void)
{
    app.format = (enum color_fmt)((app.format + 1) % FMT_COUNT);
    if (app.active)
        output_render(app.active);
}

static void zoom_step(int delta)
{
    app.zoom = iclamp(app.zoom + delta, ZOOM_MIN, ZOOM_MAX);
    if (app.active)
        output_render(app.active);
}

static void nudge(uint32_t key)
{
    struct output *o = app.active;
    if (!o)
        return;
    int step = app.shift ? 10 : 1;
    switch (key) {
    case KEY_UP:    app.cur_y -= step; break;
    case KEY_DOWN:  app.cur_y += step; break;
    case KEY_LEFT:  app.cur_x -= step; break;
    case KEY_RIGHT: app.cur_x += step; break;
    default: return;
    }
    clamp_cursor(o);
    output_render(o);
}

/* ------------------------------------------------------------------------ */
/* Ponteiro                                                                 */
/* ------------------------------------------------------------------------ */

static void ptr_enter(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s,
                      wl_fixed_t sx, wl_fixed_t sy)
{
    (void)d;
    struct output *o = output_from_surface(s);
    if (!o)
        return;
    wl_pointer_set_cursor(p, serial, NULL, 0, 0); /* esconde o cursor: a lupa o substitui */
    app.active = o;
    cursor_from_surface_coords(o, sx, sy);
    output_render(o);
}

static void ptr_leave(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s)
{
    (void)d; (void)p; (void)serial;
    struct output *o = output_from_surface(s);
    if (o && app.active == o) {
        app.active = NULL;
        output_render(o);
    }
}

static void ptr_motion(void *d, struct wl_pointer *p, uint32_t time, wl_fixed_t sx, wl_fixed_t sy)
{
    (void)d; (void)p; (void)time;
    if (!app.active)
        return;
    cursor_from_surface_coords(app.active, sx, sy);
    output_render(app.active);
}

static void ptr_button(void *d, struct wl_pointer *p, uint32_t serial, uint32_t time,
                       uint32_t button, uint32_t state)
{
    (void)d; (void)p; (void)serial; (void)time;
    if (state != WL_POINTER_BUTTON_STATE_PRESSED)
        return;
    switch (button) {
    case BTN_LEFT:   do_pick();       break;
    case BTN_RIGHT:  do_cancel();     break;
    case BTN_MIDDLE: cycle_format();  break;
    }
}

static void ptr_axis(void *d, struct wl_pointer *p, uint32_t time, uint32_t axis, wl_fixed_t value)
{
    (void)d; (void)p; (void)time;
    if (axis != WL_POINTER_AXIS_VERTICAL_SCROLL)
        return;
    app.scroll_acc += wl_fixed_to_double(value);
    while (app.scroll_acc >= 8.0)  { zoom_step(-1); app.scroll_acc -= 8.0; } /* rolar p/ baixo */
    while (app.scroll_acc <= -8.0) { zoom_step(+1); app.scroll_acc += 8.0; } /* rolar p/ cima  */
}

static void ptr_frame(void *d, struct wl_pointer *p) { (void)d; (void)p; }
static void ptr_axis_source(void *d, struct wl_pointer *p, uint32_t s) { (void)d; (void)p; (void)s; }
static void ptr_axis_stop(void *d, struct wl_pointer *p, uint32_t t, uint32_t a)
{ (void)d; (void)p; (void)t; (void)a; }
static void ptr_axis_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v)
{ (void)d; (void)p; (void)a; (void)v; }

static const struct wl_pointer_listener pointer_listener = {
    .enter = ptr_enter,
    .leave = ptr_leave,
    .motion = ptr_motion,
    .button = ptr_button,
    .axis = ptr_axis,
    .frame = ptr_frame,
    .axis_source = ptr_axis_source,
    .axis_stop = ptr_axis_stop,
    .axis_discrete = ptr_axis_discrete,
};

/* ------------------------------------------------------------------------ */
/* Teclado (códigos evdev diretamente: dispensa xkbcommon)                  */
/* ------------------------------------------------------------------------ */

static void stop_repeat(void)
{
    struct itimerspec its = {0};
    timerfd_settime(app.repeat_fd, 0, &its, NULL);
    app.repeat_key = 0;
}

static struct timespec ms_to_ts(int ms)
{
    return (struct timespec){.tv_sec = ms / 1000, .tv_nsec = (long)(ms % 1000) * 1000000L};
}

static void start_repeat(uint32_t key)
{
    if (app.repeat_rate <= 0)
        return;
    struct itimerspec its = {
        .it_value = ms_to_ts(app.repeat_delay),
        .it_interval = ms_to_ts(imax(1, 1000 / app.repeat_rate)),
    };
    app.repeat_key = key;
    timerfd_settime(app.repeat_fd, 0, &its, NULL);
}

static void kb_keymap(void *d, struct wl_keyboard *k, uint32_t fmt, int32_t fd, uint32_t size)
{
    (void)d; (void)k; (void)fmt; (void)size;
    close(fd); /* não precisamos do keymap */
}

static void kb_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *surf,
                     struct wl_array *keys)
{ (void)d; (void)k; (void)s; (void)surf; (void)keys; }

static void kb_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *surf)
{
    (void)d; (void)k; (void)s; (void)surf;
    stop_repeat();
    app.shift = false;
}

static void kb_key(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t time, uint32_t key,
                   uint32_t state)
{
    (void)d; (void)k; (void)serial; (void)time;
    bool pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED;

    if (key == KEY_LEFTSHIFT || key == KEY_RIGHTSHIFT) {
        app.shift = pressed;
        return;
    }
    if (!pressed) {
        if (key == app.repeat_key)
            stop_repeat();
        return;
    }

    switch (key) {
    case KEY_ESC:                                  do_cancel();    break;
    case KEY_ENTER: case KEY_KPENTER: case KEY_SPACE: do_pick();   break;
    case KEY_TAB:                                  cycle_format(); break;
    case KEY_EQUAL: case KEY_KPPLUS:               zoom_step(+1);  break;
    case KEY_MINUS: case KEY_KPMINUS:              zoom_step(-1);  break;
    case KEY_UP: case KEY_DOWN: case KEY_LEFT: case KEY_RIGHT:
        nudge(key);
        start_repeat(key);
        break;
    }
}

static void kb_modifiers(void *d, struct wl_keyboard *k, uint32_t s, uint32_t a, uint32_t b,
                         uint32_t c, uint32_t e)
{ (void)d; (void)k; (void)s; (void)a; (void)b; (void)c; (void)e; }

static void kb_repeat_info(void *d, struct wl_keyboard *k, int32_t rate, int32_t delay)
{
    (void)d; (void)k;
    app.repeat_rate = rate;
    app.repeat_delay = delay;
}

static const struct wl_keyboard_listener keyboard_listener = {
    .keymap = kb_keymap,
    .enter = kb_enter,
    .leave = kb_leave,
    .key = kb_key,
    .modifiers = kb_modifiers,
    .repeat_info = kb_repeat_info,
};

/* ------------------------------------------------------------------------ */
/* Seat e registry                                                          */
/* ------------------------------------------------------------------------ */

static void seat_capabilities(void *d, struct wl_seat *seat, uint32_t caps)
{
    (void)d;
    if ((caps & WL_SEAT_CAPABILITY_POINTER) && !app.pointer) {
        app.pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(app.pointer, &pointer_listener, NULL);
    }
    if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !app.keyboard) {
        app.keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(app.keyboard, &keyboard_listener, NULL);
    }
}
static void seat_name(void *d, struct wl_seat *s, const char *n) { (void)d; (void)s; (void)n; }
static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

static void reg_global(void *d, struct wl_registry *reg, uint32_t name, const char *iface,
                       uint32_t ver)
{
    (void)d;
    if (!strcmp(iface, wl_compositor_interface.name)) {
        app.compositor_version = ver < 4 ? ver : 4;
        app.compositor = wl_registry_bind(reg, name, &wl_compositor_interface, app.compositor_version);
    } else if (!strcmp(iface, wl_shm_interface.name)) {
        app.shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    } else if (!strcmp(iface, wl_seat_interface.name) && !app.seat) {
        app.seat = wl_registry_bind(reg, name, &wl_seat_interface, ver < 5 ? ver : 5);
        wl_seat_add_listener(app.seat, &seat_listener, NULL);
    } else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name)) {
        app.layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1);
    } else if (!strcmp(iface, zwlr_screencopy_manager_v1_interface.name)) {
        app.screencopy = wl_registry_bind(reg, name, &zwlr_screencopy_manager_v1_interface, 1);
    } else if (!strcmp(iface, wp_viewporter_interface.name)) {
        app.viewporter = wl_registry_bind(reg, name, &wp_viewporter_interface, 1);
    } else if (!strcmp(iface, wl_output_interface.name) && app.n_outputs < MAX_OUTPUTS) {
        struct output *o = &app.outputs[app.n_outputs++];
        o->wl_output = wl_registry_bind(reg, name, &wl_output_interface, 1);
    }
}
static void reg_global_remove(void *d, struct wl_registry *r, uint32_t n) { (void)d; (void)r; (void)n; }
static const struct wl_registry_listener registry_listener = {
    .global = reg_global,
    .global_remove = reg_global_remove,
};

/* ------------------------------------------------------------------------ */
/* Clipboard (via wl-copy, que daemoniza e mantém a seleção viva)           */
/* ------------------------------------------------------------------------ */

static void copy_to_clipboard(const char *text)
{
    int fds[2];
    if (pipe(fds) < 0) {
        perror("colorpicker: pipe");
        return;
    }
    fflush(stdout);
    pid_t pid = fork();
    if (pid < 0) {
        perror("colorpicker: fork");
        close(fds[0]);
        close(fds[1]);
        return;
    }
    if (pid == 0) {
        dup2(fds[0], STDIN_FILENO);
        close(fds[0]);
        close(fds[1]);
        execlp("wl-copy", "wl-copy", (char *)NULL);
        fprintf(stderr, "colorpicker: não foi possível executar wl-copy (instale wl-clipboard)\n");
        _exit(127);
    }
    close(fds[0]);
    ssize_t n = write(fds[1], text, strlen(text));
    (void)n;
    close(fds[1]);
    int st = 0;
    waitpid(pid, &st, 0);
}

/* ------------------------------------------------------------------------ */
/* CLI                                                                      */
/* ------------------------------------------------------------------------ */

static void usage(FILE *f)
{
    fprintf(f,
        "colorpicker — seletor de cores visual para Wayland/Hyprland\n\n"
        "Uso: colorpicker [opções]\n\n"
        "  -f, --format=FMT   formato inicial: hex (padrão), rgb, hsl, hsv, cmyk\n"
        "  -l, --lowercase    hex em minúsculas\n"
        "  -n, --no-newline   não imprime quebra de linha no final\n"
        "  -a, --autocopy     copia o resultado para a área de transferência (wl-copy)\n"
        "  -z, --zoom=N       zoom inicial da lupa, %d a %d (padrão %d)\n"
        "  -h, --help         mostra esta ajuda\n\n"
        "Controles:\n"
        "  Clique esquerdo / Enter / Espaço   escolhe a cor\n"
        "  Clique direito / Esc               cancela (código de saída 1)\n"
        "  Clique do meio / Tab               alterna o formato\n"
        "  Rolar / + / -                      zoom da lupa\n"
        "  Setas (Shift = 10 px)              ajuste fino do pixel\n",
        ZOOM_MIN, ZOOM_MAX, ZOOM_DEFAULT);
}

static void parse_args(int argc, char **argv)
{
    static const struct option opts[] = {
        {"format", required_argument, NULL, 'f'},
        {"lowercase", no_argument, NULL, 'l'},
        {"no-newline", no_argument, NULL, 'n'},
        {"autocopy", no_argument, NULL, 'a'},
        {"zoom", required_argument, NULL, 'z'},
        {"help", no_argument, NULL, 'h'},
        {0},
    };
    int c;
    while ((c = getopt_long(argc, argv, "f:lnaz:h", opts, NULL)) != -1) {
        switch (c) {
        case 'f': {
            bool ok = false;
            for (int i = 0; i < FMT_COUNT; i++) {
                if (!strcmp(optarg, fmt_names[i])) {
                    app.format = (enum color_fmt)i;
                    ok = true;
                }
            }
            if (!ok)
                die("formato inválido '%s' (use hex, rgb, hsl, hsv ou cmyk)", optarg);
            break;
        }
        case 'l': app.lowercase = true; break;
        case 'n': app.no_newline = true; break;
        case 'a': app.autocopy = true; break;
        case 'z': {
            char *end;
            long z = strtol(optarg, &end, 10);
            if (*end || z < ZOOM_MIN || z > ZOOM_MAX)
                die("zoom deve estar entre %d e %d", ZOOM_MIN, ZOOM_MAX);
            app.zoom = (int)z;
            break;
        }
        case 'h': usage(stdout); exit(0);
        default:  usage(stderr); exit(2);
        }
    }
}

/* ------------------------------------------------------------------------ */
/* main                                                                     */
/* ------------------------------------------------------------------------ */

#ifndef CP_TEST
int main(int argc, char **argv)
{
    app.zoom = ZOOM_DEFAULT;
    app.repeat_rate = 25;
    app.repeat_delay = 400;
    parse_args(argc, argv);
    signal(SIGPIPE, SIG_IGN);

    app.display = wl_display_connect(NULL);
    if (!app.display)
        die("não foi possível conectar ao compositor Wayland (WAYLAND_DISPLAY definido?)");

    app.repeat_fd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
    if (app.repeat_fd < 0)
        die("timerfd_create: %s", strerror(errno));

    app.registry = wl_display_get_registry(app.display);
    wl_registry_add_listener(app.registry, &registry_listener, NULL);
    wl_display_roundtrip(app.display); /* globais */
    wl_display_roundtrip(app.display); /* capabilities do seat, etc. */

    if (!app.compositor || app.compositor_version < 4) die("wl_compositor v4+ ausente");
    if (!app.shm)          die("wl_shm ausente");
    if (!app.layer_shell)  die("o compositor não oferece wlr-layer-shell");
    if (!app.screencopy)   die("o compositor não oferece wlr-screencopy");
    if (!app.seat)         die("nenhum wl_seat disponível");
    if (app.n_outputs == 0) die("nenhum monitor encontrado");

    /* 1) captura todos os monitores ANTES de criar o overlay */
    for (int i = 0; i < app.n_outputs; i++) {
        struct output *o = &app.outputs[i];
        o->frame = zwlr_screencopy_manager_v1_capture_output(app.screencopy, 0, o->wl_output);
        zwlr_screencopy_frame_v1_add_listener(o->frame, &frame_listener, o);
        app.pending_captures++;
    }
    while (app.pending_captures > 0)
        if (wl_display_dispatch(app.display) < 0)
            die("conexão com o compositor perdida durante a captura");

    /* 2) cria o overlay em cada monitor */
    for (int i = 0; i < app.n_outputs; i++)
        output_create_surface(&app.outputs[i]);

    for (bool all = false; !all;) {
        if (wl_display_dispatch(app.display) < 0)
            die("conexão com o compositor perdida");
        all = true;
        for (int i = 0; i < app.n_outputs; i++)
            if (!app.outputs[i].configured)
                all = false;
    }

    /* 3) laço de eventos: Wayland + timer de repetição de tecla */
    while (!app.done) {
        while (wl_display_prepare_read(app.display) != 0)
            wl_display_dispatch_pending(app.display);
        if (wl_display_flush(app.display) < 0 && errno != EAGAIN) {
            wl_display_cancel_read(app.display);
            break;
        }

        struct pollfd fds[2] = {
            {.fd = wl_display_get_fd(app.display), .events = POLLIN},
            {.fd = app.repeat_fd, .events = POLLIN},
        };
        if (poll(fds, 2, -1) < 0 && errno != EINTR) {
            wl_display_cancel_read(app.display);
            break;
        }

        if (fds[0].revents & POLLIN) {
            if (wl_display_read_events(app.display) < 0)
                break;
        } else {
            wl_display_cancel_read(app.display);
        }
        if (wl_display_dispatch_pending(app.display) < 0)
            break;

        if (fds[1].revents & POLLIN) {
            uint64_t exp = 0;
            if (read(app.repeat_fd, &exp, sizeof exp) == (ssize_t)sizeof exp && app.repeat_key)
                for (uint64_t i = 0; i < exp && i < 8; i++)
                    nudge(app.repeat_key);
        }
        flush_pending_redraws();
    }

    /* 4) remove o overlay antes de qualquer outra coisa (devolve o foco) */
    for (int i = 0; i < app.n_outputs; i++) {
        struct output *o = &app.outputs[i];
        if (o->layer)   zwlr_layer_surface_v1_destroy(o->layer);
        if (o->viewport) wp_viewport_destroy(o->viewport);
        if (o->surface) wl_surface_destroy(o->surface);
    }
    wl_display_roundtrip(app.display);

    if (!app.picked) {
        wl_display_disconnect(app.display);
        return 1;
    }

    printf("%s%s", app.result, app.no_newline ? "" : "\n");
    fflush(stdout);
    if (app.autocopy)
        copy_to_clipboard(app.result);

    wl_display_disconnect(app.display);
    return 0;
}
#endif /* CP_TEST */
