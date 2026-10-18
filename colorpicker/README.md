# colorpicker

Seletor de cores visual para **Wayland / Hyprland**, em **C puro**. Sem GTK, Qt, Cairo ou xkbcommon: só `libwayland-client`.

A tela congela, aparece uma lupa circular com grade de pixels seguindo o cursor, e um painel mostra a cor em tempo real. Clique para escolher.

```
$ colorpicker
#4F5FC0
```

## Como funciona

| Etapa | Protocolo / técnica |
|---|---|
| Captura de cada monitor | `wlr-screencopy-unstable-v1` |
| Overlay em tela cheia, com foco exclusivo de teclado | `wlr-layer-shell-unstable-v1` (camada `OVERLAY`) |
| Escala fracionária sem perder precisão de pixel | `wp_viewporter` (buffer em pixels físicos → tamanho lógico) |
| Desenho da lupa, painel e texto | software, direto num buffer `wl_shm` (fonte bitmap 5x7 embutida) |
| Redesenho eficiente | buffer duplo + dano mínimo (só a região da lupa) |
| Teclado | códigos evdev direto (sem xkbcommon), com repetição de tecla via `timerfd` |
| Copiar para clipboard | `wl-copy` (opcional) |

Suporta vários monitores, HiDPI (a interface escala junto) e capturas em 8 bits ou 10 bits por canal.

## Dependências

- `libwayland-client` (headers) e `wayland-scanner`
- `wayland-protocols` (para `xdg-shell` e `viewporter`)
- XMLs do `wlr-protocols` (`wlr-layer-shell` e `wlr-screencopy`)
- `wl-clipboard` (opcional, só para `--autocopy`)

```sh
# Arch
sudo pacman -S wayland wayland-protocols wl-clipboard
# Debian/Ubuntu
sudo apt install libwayland-dev wayland-protocols wl-clipboard
# Fedora
sudo dnf install wayland-devel wayland-protocols-devel wl-clipboard
```

Se sua distro não tiver o pacote `wlr-protocols`, o próprio Makefile baixa os dois XMLs que faltam:

```sh
make fetch      # só se necessário (precisa de curl)
```

## Compilar e instalar

```sh
make
sudo make install        # opcional (PREFIX=/usr/local por padrão)
```

## Uso

```
colorpicker [opções]

  -f, --format=FMT   hex (padrão), rgb, hsl, hsv, cmyk
  -l, --lowercase    hex em minúsculas
  -n, --no-newline   sem quebra de linha no final
  -a, --autocopy     copia o resultado com wl-copy
  -z, --zoom=N       zoom inicial da lupa (3 a 25, padrão 9)
```

| Ação | Atalho |
|---|---|
| Escolher a cor | Clique esquerdo · Enter · Espaço |
| Cancelar (saída com código 1) | Clique direito · Esc |
| Alternar formato (hex/rgb/hsl/hsv/cmyk) | Clique do meio · Tab |
| Zoom da lupa | Rolar o mouse · `+` / `-` |
| Ajuste fino de 1 px (10 px com Shift) | Setas |

Em scripts:

```sh
cor=$(colorpicker -f hex -l) || exit 1
notify-send "Cor escolhida" "$cor"
```

## Configuração no Hyprland

Atalho para abrir o seletor e copiar o resultado:

```ini
# hyprland.conf
bind = $mainMod SHIFT, C, exec, colorpicker -a
```

O Hyprland aplica uma animação de fade em *layer surfaces*, o que dá um "piscar" na captura congelada. Desative-a para o namespace `colorpicker`:

```ini
# Hyprland >= 0.53
layerrule = no_anim on, match:namespace colorpicker

# Hyprland < 0.53
# layerrule = noanim, colorpicker
```

Em Hyprland 0.55+ com configuração Lua:

```lua
hl.layer_rule({ match = { namespace = "colorpicker" }, no_anim = true })
```

## Limitações conhecidas

- **Monitores rotacionados** (`transform`) podem mostrar a captura na orientação errada. O `wlr-screencopy` entrega o buffer sem aplicar a rotação, e este código ainda não a compensa.
- Capturas em formatos além de 8888 e 2101010 (ex.: FP16 HDR) abortam com mensagem de erro.
- Os caracteres da fonte embutida cobrem ASCII (sem acentos), por isso os textos da interface não usam acentuação.
- O hot-plug de monitores durante a captura não é tratado.
