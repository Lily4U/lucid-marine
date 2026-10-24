#!/usr/bin/env bash
# Lucid installer — Ultramarine Linux (Fedora) + Hyprland
#
# installs dependencies (dnf, COPR, Flatpak), places the shell at ~/.config/quickshell, and sets up
# the full bundle: the Hyprland config (binds, window rules, blur, autostart),
# the theming layer, the Lucid look, and the apps the dock ships pinned.
# safe to re-run: existing config and personal state are backed up, never
# overwritten in place.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# the VERSION file ships inside the shell tree, so the installed copy can tell
# the update check which version it is. bump it to cut a release
VERSION="unknown"
if [[ -f "$SRC/VERSION" ]]; then
    VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
fi
SHELL_DIR="$HOME/.config/quickshell"
LUCID_DIR="$HOME/.config/lucid"
MATUGEN_DIR="$HOME/.config/matugen"
WALL_SCRIPT_DIR="$HOME/.config/hypr/scripts/wallpaper"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=""

WITH_THEMING=1
WITH_LOOK=1
WITH_HYPR=1
WITH_APPS=1
WITH_WALLPAPERS=1
WITH_PLUGINS=1
HYPR_FORCE=0
HYPR_LUA_INSTALLED=0
ASSUME_YES=0
SKIP_DEPS=0

b=$'\e[1m'; dim=$'\e[2m'; red=$'\e[31m'; grn=$'\e[32m'; ylw=$'\e[33m'; r=$'\e[0m'
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s%s\n' "$grn" "$r" "$b" "$*$r"; }
warn() { printf '%s warning:%s %s\n' "$ylw" "$r" "$*" >&2; }
die()  { printf '%s error:%s %s\n' "$red" "$r" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
${b}Lucid $VERSION installer${r}

  ./install.sh [options]

  --no-theming   skip the palette layer; leave ~/.config/lucid
                 and ~/.config/matugen untouched
  --no-look      don't touch kitty.conf, starship.toml, fastfetch or VSCode
                 settings
  --no-hypr      keep your Hyprland config; Lucid's binds, window
                 rules and blur are not installed
  --no-apps      don't install the apps pinned to the dock by
                 default (Zen, VSCodium, Spotify, Steam, ... as Flatpaks)
  --no-wallpapers
                 don't copy the bundled wallpapers to
                 ~/Pictures/wallpapers
  --with-hypr    reinstall Lucid's Hyprland config even when one
                 is already in place
  --no-plugins   don't build the tilting-cursor Hyprland plugin
                 (hypr-dynamic-cursors)
  --skip-deps    don't install packages, only check for them
  -y, --yes      don't prompt, accept every default
  -h, --help     this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-theming) WITH_THEMING=0 ;;
        --no-look)    WITH_LOOK=0 ;;
        --no-hypr)    WITH_HYPR=0 ;;
        --no-apps)    WITH_APPS=0 ;;
        --no-wallpapers) WITH_WALLPAPERS=0 ;;
        --with-hypr)  WITH_HYPR=1; HYPR_FORCE=1 ;;
        --no-plugins) WITH_PLUGINS=0 ;;
        --skip-deps)  SKIP_DEPS=1 ;;
        -y|--yes)     ASSUME_YES=1 ;;
        -h|--help)    usage ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

ask() {
    [[ $ASSUME_YES -eq 1 ]] && return 0
    local reply
    read -rp "$1 [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------- preflight

step "Checking the system"

# Ultramarine reports ID=ultramarine, ID_LIKE=fedora. Fedora itself and other
# derivatives (Nobara, ...) pass the same check.
OS_ID=""; OS_LIKE=""; OS_VERSION=""
if [[ -r /etc/os-release ]]; then
    OS_ID=$(. /etc/os-release; printf '%s' "${ID:-}")
    OS_LIKE=$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")
    OS_VERSION=$(. /etc/os-release; printf '%s' "${VERSION_ID:-}")
fi
[[ "$OS_ID" == fedora || "$OS_ID" == ultramarine || " $OS_LIKE " == *" fedora "* ]] \
    || die "this installer targets Ultramarine / Fedora. see the README for a manual install."
command -v dnf &>/dev/null || die "dnf not found"
[[ $EUID -ne 0 ]] || die "don't run this as root — it installs into your home directory"
[[ -f "$SRC/shell.qml" ]] || die "run this from inside the Lucid repo (no shell.qml next to install.sh)"

command -v Hyprland &>/dev/null || command -v hyprctl &>/dev/null \
    || warn "Hyprland not found yet. Lucid uses Hyprland-specific APIs and will not work under another compositor."

# dnf5 (Fedora 41+, Ultramarine 41+) has COPR built in and spells "skip what
# does not exist" differently from dnf4
DNF5=0
[[ "$(dnf --version 2>/dev/null)" == *dnf5* ]] && DNF5=1
if [[ $DNF5 -eq 1 ]]; then
    DNF_SKIP=(--skip-unavailable)
else
    DNF_SKIP=(--setopt=strict=0)
fi

say "  ${OS_ID:-fedora} ${OS_VERSION}  ${grn}ok${r}  (dnf$([[ $DNF5 -eq 1 ]] && echo 5 || echo ''))"
say "  install target  $SHELL_DIR"
say "  theming layer   $([[ $WITH_THEMING -eq 1 ]] && echo yes || echo 'no (--no-theming)')"
say "  hyprland config $([[ $WITH_HYPR   -eq 1 ]] && echo yes || echo 'no (--no-hypr)')"
say "  dock apps       $([[ $WITH_APPS   -eq 1 ]] && echo yes || echo 'no (--no-apps)')"
say "  wallpapers      $([[ $WITH_WALLPAPERS -eq 1 ]] && echo yes || echo 'no (--no-wallpapers)')"

# ------------------------------------------------------------- dependencies

# COPR repositories are unofficial and maintained by individuals. They are only
# enabled after asking, and only when something is still missing from the
# official repos (Fedora, RPM Fusion and Terra, which Ultramarine ships).
# Names live here so they are one edit away if a maintainer moves.
COPR_QUICKSHELL="errornointernet/quickshell"   # quickshell (documented upstream)
COPR_EXTRAS="avengemedia/danklinux"            # matugen, cliphist and friends
COPR_HYPRLAND="ashbuk/Hyprland-Fedora"         # Hyprland: not in Fedora's own repos
COPR_HYPRLANDUTILS="aahsnr-work/base-pkgs"     # hyprland-guiutils remain on this repo ;)
# required — the shell will not start or will visibly break without these
PKG_REQUIRED=(quickshell qt6-qt5compat qt6-qtdeclarative qt6-qtmultimedia)
# each of these backs one feature; missing ones degrade that feature only
PKG_FEATURES=(
    matugen jq ImageMagick
    NetworkManager qrencode bluez bluez-obexd
    kde-connect fuse-sshfs python3-gobject
    pulseaudio-utils wireplumber brightnessctl upower hypridle hyprsunset
    grim wf-recorder ffmpeg-free wl-clipboard wtype cliphist
    tesseract tesseract-langpack-eng
    python3-pillow python3-numpy python3-fonttools
    cava songrec curl libnotify awww fastfetch
    python3-pywal google-noto-color-emoji-fonts
    # the shell is the session's own polkit agent; polkitd and its setuid
    # helper are the backend it drives
    xdg-utils zenity swappy polkit
    # the accounts page reads and writes users through this, and asks the
    # shell's polkit dialog whenever a change needs an administrator
    accountsservice
    # the environment page writes the desktop's appearance through these, and
    # the file chooser kde connect sends files with comes from the gtk portal.
    # librsvg2 renders a cursor theme again when its shadow is turned off
    gsettings-desktop-schemas qt6ct xdg-desktop-portal-gtk librsvg2 gtk-update-icon-cache
    # the launcher's $ mode runs a command in the user's terminal through this
    xdg-terminal-exec
    # the camera on/off toast hears /dev/video* opened and closed through this
    inotify-tools
    # the Sound page's Left/Right test: pw-play, and the voice that names each side
    pipewire-utils sound-theme-freedesktop
    # the Storage page: a drive's health, and mounting or ejecting one
    smartmontools udisks2
    # the desktop icons: video and music thumbnails, and the drives and trash they show
    ffmpegthumbnailer gvfs
    # Compile tools (for C colorpicker)
    clang make wayland-protocols-devel
)
# invoked by the shipped Hyprland binds and the Lucid look. without these the
# config installs fine but its keys do nothing and the prompt renders as boxes.
# (the JetBrainsMono Nerd Font is not packaged for Fedora; it is fetched below)
PKG_HYPR=(
    kitty nautilus playerctl gnome-calculator
    starship fish adw-gtk3-theme papirus-icon-theme
)
# the dock's default pins, installed as Flatpaks from Flathub: none of them is
# in Fedora's repos, and Flatpak keeps them out of the way of the system. the
# dock detects them through the flatpak export dirs. --no-apps skips them.
# (Proton VPN has no Flathub build: add Proton's own repo if you want it)
DOCK_FLATPAKS=(
    app.zen_browser.zen com.vscodium.codium dev.vencord.Vesktop
    com.spotify.Client com.valvesoftware.Steam
)

# a package already covered by an equivalent one the user chose themselves.
# without this a re-run keeps trying to install ffmpeg-free over ffmpeg
declare -A PKG_ALTS=(
    [ffmpeg-free]="ffmpeg"
    [qt6ct]="qt6ct-kde"
    [xdg-desktop-portal-gtk]="xdg-desktop-portal-gnome xdg-desktop-portal-kde"
    [adw-gtk3-theme]="adw-gtk3"
)
# same idea for the dock apps: an RPM or binary the user already has counts
declare -A DOCK_ALTS=(
    [app.zen_browser.zen]="zen-browser zen"
    [com.vscodium.codium]="codium vscodium code visual-studio-code"
    [dev.vencord.Vesktop]="vesktop discord"
    [com.spotify.Client]="spotify spotify-launcher"
    [com.valvesoftware.Steam]="steam"
)

# true when the package, or anything standing in for it, is installed. the
# whatprovides form also accepts capability names
have_pkg() {
    rpm -q --whatprovides "$1" &>/dev/null && return 0
    local alt
    for alt in ${PKG_ALTS[$1]:-}; do
        rpm -q --whatprovides "$alt" &>/dev/null && return 0
    done
    return 1
}

dock_have() {
    command -v flatpak &>/dev/null && flatpak info "$1" &>/dev/null && return 0
    local alt
    for alt in ${DOCK_ALTS[$1]:-}; do
        command -v "$alt" &>/dev/null && return 0
        rpm -q "$alt" &>/dev/null && return 0
    done
    return 1
}

# enable a COPR, with the plugin dnf4 needs for it
copr_enable() {
    if [[ $DNF5 -eq 0 ]] && ! rpm -q dnf-plugins-core &>/dev/null; then
        sudo dnf install -y dnf-plugins-core || return 1
    fi
    sudo dnf copr enable -y "$1"
}

# which of the wanted packages are still not installed
compute_missing() {
    missing=()
    local p
    for p in "${WANTED[@]}"; do
        have_pkg "$p" || missing+=("$p")
    done
}

# a second, third... call must not trip over an empty result under set -e
dnf_install() {
    sudo dnf install -y "${DNF_SKIP[@]}" "$@"
}

missing=()
DEPS_OK=1

step "Resolving dependencies"

WANTED=("${PKG_REQUIRED[@]}" "${PKG_FEATURES[@]}")
[[ $WITH_HYPR -eq 1 || $WITH_LOOK -eq 1 ]] && WANTED+=("${PKG_HYPR[@]}")
command -v Hyprland &>/dev/null && WANTED+=(hyprland-guiutils)
compute_missing

if [[ ${#missing[@]} -eq 0 ]]; then
    say "  everything is already installed"
elif [[ $SKIP_DEPS -eq 1 ]]; then
    DEPS_OK=0
    say "  ${ylw}missing (--skip-deps, not installing):${r}"
    printf '    %s\n' "${missing[@]}"
else
    say "  missing: ${missing[*]}"

    if ask "  install these now (official repos first)?"; then
        # pass 1: whatever Fedora, RPM Fusion and Terra carry. unknown names
        # are skipped, so one unresolvable package never sinks the batch
        dnf_install "${missing[@]}" || warn "dnf reported problems — checking what is left"
        compute_missing

        # pass 2: quickshell has no official package outside Rawhide
        if [[ " ${missing[*]} " == *" quickshell "* ]]; then
            say "  quickshell is not in the official repos; it comes from the"
            say "  ${COPR_QUICKSHELL} COPR (unofficial, community-maintained)"
            if ask "  Enable that COPR?"; then
                copr_enable "$COPR_QUICKSHELL" && dnf_install quickshell \
                    || warn "could not install quickshell from the COPR"
                compute_missing
            fi
        fi

        # pass 2b: hyprland-guiutils (Hyprland's dialogs and update screen).
        # separate from quickshell, so it is offered even when quickshell is fine
        if [[ " ${missing[*]} " == *" hyprland-guiutils "* ]]; then
            say "  hyprland-guiutils is not in the official repos; it comes from the"
            say "  ${COPR_HYPRLANDUTILS} COPR (unofficial, community-maintained)"
            if ask "  Enable that COPR?"; then
                copr_enable "$COPR_HYPRLANDUTILS" && dnf_install hyprland-guiutils \
                    || warn "could not install hyprland-guiutils from the COPR"
                compute_missing
            fi
        fi

        # pass 3: the helpers that are packaged only outside Fedora
        extras_missing=()
        for p in matugen cliphist hyprsunset hypridle cava; do
            [[ " ${missing[*]} " == *" $p "* ]] && extras_missing+=("$p")
        done
        if (( ${#extras_missing[@]} )); then
            say "  still missing, packaged by a COPR: ${extras_missing[*]}"
            if ask "  Enable ${COPR_EXTRAS} (unofficial) and try again?"; then
                copr_enable "$COPR_EXTRAS" && dnf_install "${extras_missing[@]}" \
                    || warn "the COPR could not provide all of them"
                compute_missing
            fi
        fi

        # pass 4: matugen is the palette engine, so it gets one more chance
        # built from source (crates.io) when no repo had it
        if [[ " ${missing[*]} " == *" matugen "* ]] && ! command -v matugen &>/dev/null; then
            say "  matugen is the palette engine; building it from crates.io instead"
            if ask "  Install rust + cargo and build matugen (a few minutes)?"; then
                dnf_install cargo rust gcc pkgconf-pkg-config || true
                if command -v cargo &>/dev/null \
                   && cargo install matugen --locked; then
                    say "  matugen -> ~/.cargo/bin/matugen"
                    case ":$PATH:" in
                        *":$HOME/.cargo/bin:"*) ;;
                        *) warn "  add ~/.cargo/bin to your PATH so Lucid can find matugen" ;;
                    esac
                else
                    warn "could not build matugen — the theme engine will not work"
                fi
                compute_missing
            fi
        fi

        # whatever is left degrades only its own feature
        if (( ${#missing[@]} )); then
            DEPS_OK=0
            warn "not available on this system, so these features stay off:"
            warn "    ${missing[*]}"
            for p in "${missing[@]}"; do
                case "$p" in
                    awww)          warn "  awww (wallpaper daemon) has no Fedora package: build it from source and put it on PATH" ;;
                    songrec)       warn "  songrec (music recognition) has no Fedora package: optional, 'cargo install songrec' works" ;;
                    xdg-terminal-exec) warn "  xdg-terminal-exec: optional, the launcher's \$ mode falls back to your terminal" ;;
                esac
            done
        else
            say "  all packages installed"
        fi
    else
        DEPS_OK=0
        warn "skipping. features backed by the missing packages will not work."
    fi
fi

# --- Hyprland itself ---------------------------------------------------------
# Fedora does not ship it. Lucid is useless without it, so it is offered
# rather than assumed, and never touched when it is already there
if [[ $WITH_HYPR -eq 1 || $WITH_LOOK -eq 1 ]] && [[ $SKIP_DEPS -eq 0 ]] \
   && ! command -v Hyprland &>/dev/null; then
    say "  Hyprland is not installed. Fedora has no official package; the"
    say "  ${COPR_HYPRLAND} COPR builds the stable releases. Lucid's lua"
    say "  config needs Hyprland 0.55 or newer."
    if ask "  Enable that COPR and install hyprland?"; then
        copr_enable "$COPR_HYPRLAND" && dnf_install hyprland hyprland-guiutils xdg-desktop-portal-hyprland \
            || { DEPS_OK=0; warn "could not install hyprland — do it by hand before logging in"; }
    else
        DEPS_OK=0
    fi
fi

# --- JetBrainsMono Nerd Font -------------------------------------------------
# the prompt and kitty.conf are drawn with its glyphs, and Fedora does not
# package it. fetched from the Nerd Fonts release, user-local, once
if [[ $WITH_HYPR -eq 1 || $WITH_LOOK -eq 1 ]] && [[ $SKIP_DEPS -eq 0 ]] \
   && ! { fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd Font' >/dev/null; }; then
    if command -v curl &>/dev/null && command -v tar &>/dev/null; then
        NF_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"
        NF_TMP=$(mktemp -d)
        say "  fetching JetBrainsMono Nerd Font (one-time)"
        if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
               -o "$NF_TMP/jbm.tar.xz" \
           && mkdir -p "$NF_DIR" \
           && tar -xJf "$NF_TMP/jbm.tar.xz" -C "$NF_DIR" --wildcards '*.ttf' 2>/dev/null; then
            fc-cache -f "$NF_DIR" &>/dev/null || true
            say "  JetBrainsMono Nerd Font -> $NF_DIR"
        else
            warn "  could not fetch the Nerd Font — the prompt will show boxes"
        fi
        rm -rf "$NF_TMP"
    else
        warn "  curl/tar missing — skipping the Nerd Font download"
    fi
fi

# --- the dock's default apps, from Flathub -----------------------------------
if [[ $WITH_APPS -eq 1 ]]; then
    dock_missing=()
    for id in "${DOCK_FLATPAKS[@]}"; do
        dock_have "$id" || dock_missing+=("$id")
    done

    if (( ${#dock_missing[@]} == 0 )); then
        say "  dock apps are already installed"
    elif [[ $SKIP_DEPS -eq 1 ]]; then
        say "  ${ylw}dock apps missing (--skip-deps, not installing):${r} ${dock_missing[*]}"
    else
        say "  ${dim}the dock's default apps, as Flatpaks: ${dock_missing[*]}${r}"
        say "  ${dim}(several GB — pass --no-apps to skip them)${r}"
        if ask "  install them now?"; then
            if ! command -v flatpak &>/dev/null; then
                dnf_install flatpak || warn "could not install flatpak"
            fi
            if command -v flatpak &>/dev/null; then
                flatpak remote-add --if-not-exists flathub \
                    https://dl.flathub.org/repo/flathub.flatpakrepo \
                    || warn "could not add the Flathub remote"
                for id in "${dock_missing[@]}"; do
                    flatpak install -y --noninteractive flathub "$id" \
                        || { DEPS_OK=0; warn "could not install $id"; }
                done
            else
                DEPS_OK=0
            fi
        else
            DEPS_OK=0
            warn "skipping the dock apps — the dock will pin whatever equivalents you have"
        fi
    fi
fi

# --------------------------------------------------------------- the shell

step "Installing the shell"

if [[ "$SRC" == "$SHELL_DIR" ]]; then
    say "  already at $SHELL_DIR, installing in place"
else
    if [[ -e "$SHELL_DIR" ]]; then
        BACKUP="$SHELL_DIR.backup-$STAMP"
        say "  existing config found, moving it to ${dim}$BACKUP${r}"
        mv "$SHELL_DIR" "$BACKUP"
    fi
    mkdir -p "$SHELL_DIR"
    # everything but the repo's own scaffolding. runtime state is excluded
    # too, so the copy can never carry another machine's settings, pins or
    # api keys — those come from defaults/ in the seed step below
    tar -C "$SRC" -cf - \
        --exclude='.git' --exclude='.github' --exclude='.claude' \
        --exclude='support' --exclude='defaults' --exclude='__pycache__' \
        --exclude='wallpapers' \
        --exclude='install.sh' --exclude='uninstall.sh' \
        --exclude='README.md' --exclude='LICENSE' --exclude='.gitignore' \
        --exclude='./lucidprefs/prefs.json' \
        --exclude='./lucidbar/blur.json' \
        --exclude='./lucidbar/clock_reminders.json' \
        --exclude='./lucidbar/mpris_shazam.json' \
        --exclude='./luciddocks/pinned.json' \
        --exclude='./luciddocks/usage.json' \
        --exclude='./luciddocks/wallpaper.json' \
        --exclude='./lucidmoji/config.json' \
        --exclude='./lucidmoji/state.json' \
        --exclude='./lucidkeys/state.json' \
        --exclude='./lucidwidgets/widgets.json' \
        --exclude='./luciddesktop/icons.json' \
        . | tar -C "$SHELL_DIR" -xf -
    say "  shell files -> $SHELL_DIR"
fi

# the shell loads its bundled font itself, but the apps the environment page
# dresses (and its font picker) only see what fontconfig knows. google sans
# flex is the OFL release, so it may ship; the proprietary google sans may not
if [[ -f "$SRC/assets/fonts/GoogleSansFlex.ttf" ]]; then
    FONT_DIR="$HOME/.local/share/fonts/lucid"
    mkdir -p "$FONT_DIR"
    install -m644 "$SRC/assets/fonts/GoogleSansFlex.ttf" "$FONT_DIR/GoogleSansFlex.ttf"
    install -m644 "$SRC/assets/fonts/OFL-GoogleSansFlex.txt" "$FONT_DIR/OFL-GoogleSansFlex.txt"
    fc-cache -f "$FONT_DIR" &>/dev/null || true
    say "  google sans flex -> $FONT_DIR"
fi

# the launcher sits outside the shell tree so autostart can reach it whether or
# not the Hyprland config was installed. it picks the Qt scene graph backend
# before exec'ing quickshell — see support/lucid/launch-shell.sh
if [[ -f "$SRC/support/lucid/launch-shell.sh" ]]; then
    mkdir -p "$LUCID_DIR"
    install -m755 "$SRC/support/lucid/launch-shell.sh" "$LUCID_DIR/launch-shell.sh"
    say "  shell launcher -> $LUCID_DIR/launch-shell.sh"
else
    warn "support/lucid/launch-shell.sh missing, autostart will run quickshell directly"
fi

# state files. a re-run keeps your settings: anything already in place wins,
# then whatever the previous install left in the backup, and only failing both
# does the shipped default get written
seed() {
    local src="$SRC/defaults/$1" dest="$SHELL_DIR/$2"
    mkdir -p "$(dirname "$dest")"
    if [[ -s "$dest" ]]; then
        say "  ${dim}keeping existing $2${r}"
    elif [[ -n "$BACKUP" && -s "$BACKUP/$2" ]]; then
        cp "$BACKUP/$2" "$dest"
        say "  carried over $2"
    else
        cp "$src" "$dest"
        say "  seeded $2"
    fi
}

# pinned dock apps are detected rather than shipped: a fixed list pins apps the
# machine does not have, and the dock can only draw a letter tile for those
detect_pinned() {
    local dirs=(
        /usr/share/applications
        "$HOME/.local/share/applications"
        /var/lib/flatpak/exports/share/applications
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    # the shipped dock lineup, in dock order. one entry per slot and first
    # match wins, so a machine without Lucid's default app still gets that
    # slot filled by whatever equivalent it does have
    local slots=(
        "zen zen-browser app.zen_browser.zen firefox librewolf chromium brave-browser google-chrome-stable"
        "vscodium codium com.vscodium.codium code code-oss com.visualstudio.code zed dev.zed.Zed"
        "spotify com.spotify.Client spotify-launcher"
        "vesktop dev.vencord.Vesktop discord com.discordapp.Discord webcord"
        "org.gnome.Nautilus nautilus org.kde.dolphin dolphin thunar nemo pcmanfm-qt pcmanfm"
        "steam com.valvesoftware.Steam"
        "proton.vpn.app.gtk protonvpn-app"
        "kitty alacritty foot org.wezfurlong.wezterm Alacritty com.mitchellh.ghostty"
    )
    local out="" found=0
    for slot in "${slots[@]}"; do
        for cand in $slot; do
            local f=""
            for d in "${dirs[@]}"; do
                [[ -f "$d/$cand.desktop" ]] && { f="$d/$cand.desktop"; break; }
            done
            [[ -n "$f" ]] || continue

            local name icon exec wm
            name=$(sed -n 's/^Name=//p'           "$f" | head -n1)
            icon=$(sed -n 's/^Icon=//p'           "$f" | head -n1)
            # strip desktop field codes, then drop any option left holding
            # nothing (Exec=spotify --uri=%u would otherwise pin "--uri=")
            exec=$(sed -n 's/^Exec=//p' "$f" | head -n1 \
                | sed -E 's/%[fFuUdDnNickvm]//g; s/ +-[^ ]*=( |$)/\1/g; s/  +/ /g; s/ +$//')
            wm=$(  sed -n 's/^StartupWMClass=//p' "$f" | head -n1)
            [[ -n "$name" && -n "$exec" ]] || continue
            # StartupWMClass is an X11 hint. a wayland-native app reports its
            # application-id instead, which is the reverse-dns desktop name -
            # trusting the hint there pins an id no window ever matches
            if [[ "$cand" == *.*.* ]]; then
                wm="$cand"
            else
                [[ -n "$wm" ]] || wm="$cand"
            fi
            [[ -n "$icon" ]] || icon="$cand"
            # escape for json
            esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
            [[ $found -eq 1 ]] && out+=","
            out+=$(printf '\n        {\n            "appId": "%s",\n            "appKey": "%s",\n            "command": "%s",\n            "iconName": "%s",\n            "name": "%s"\n        }' \
                "$(esc "$wm")" "$(esc "$cand")" "$(esc "$exec")" "$(esc "$icon")" "$(esc "$name")")
            found=1
            break
        done
    done
    [[ $found -eq 1 ]] || return 1
    printf '{\n    "pinnedApps": [%s\n    ]\n}\n' "$out"
}

seed_pinned() {
    local dest="$SHELL_DIR/luciddocks/pinned.json"
    mkdir -p "$(dirname "$dest")"
    if [[ -s "$dest" ]]; then
        say "  ${dim}keeping existing luciddocks/pinned.json${r}"
    elif [[ -n "$BACKUP" && -s "$BACKUP/luciddocks/pinned.json" ]]; then
        cp "$BACKUP/luciddocks/pinned.json" "$dest"
        say "  carried over luciddocks/pinned.json"
    elif detect_pinned > "$dest.tmp" 2>/dev/null && [[ -s "$dest.tmp" ]]; then
        mv "$dest.tmp" "$dest"
        say "  pinned $(grep -c '"appId"' "$dest") installed apps to the dock"
    else
        rm -f "$dest.tmp"
        cp "$SRC/defaults/pinned.json" "$dest"
        say "  seeded luciddocks/pinned.json (defaults)"
    fi
}

seed prefs.json            lucidprefs/prefs.json
seed blur.json             lucidbar/blur.json
seed clock_reminders.json  lucidbar/clock_reminders.json
seed mpris_shazam.json     lucidbar/mpris_shazam.json
seed_pinned
seed usage.json            luciddocks/usage.json
seed wallpaper.json        luciddocks/wallpaper.json
seed moji-config.json      lucidmoji/config.json
seed moji-state.json       lucidmoji/state.json
seed keys-state.json       lucidkeys/state.json
seed widgets.json          lucidwidgets/widgets.json
# where the desktop icons sit has no shipped default: only carried over
if [[ ! -s "$SHELL_DIR/luciddesktop/icons.json" && -n "$BACKUP" && -s "$BACKUP/luciddesktop/icons.json" ]]; then
    mkdir -p "$SHELL_DIR/luciddesktop"
    cp "$BACKUP/luciddesktop/icons.json" "$SHELL_DIR/luciddesktop/icons.json"
    say "  carried over luciddesktop/icons.json"
fi

# the media visualiser runs `cava -p ~/.config/cava/quickshell.conf`. without
# that file cava falls back to its own defaults, which emit ncurses output
# instead of the raw ascii frames the bar strip parses - the strip then reads
# one enormous bar and draws it as a circle across the whole popup. not part of
# --no-look: this backs a shell feature, it is not a taste preference.
CAVA_CFG="$HOME/.config/cava/quickshell.conf"
mkdir -p "$(dirname "$CAVA_CFG")"
if [[ ! -f "$CAVA_CFG" ]]; then
    cp "$SRC/support/cava/quickshell.conf" "$CAVA_CFG"
    say "  cava visualiser config -> ~/.config/cava/quickshell.conf"
elif cmp -s "$SRC/support/cava/quickshell.conf" "$CAVA_CFG"; then
    say "  ${dim}keeping cava/quickshell.conf${r}"
else
    cp "$CAVA_CFG" "$CAVA_CFG.backup-$STAMP"
    cp "$SRC/support/cava/quickshell.conf" "$CAVA_CFG"
    say "  cava/quickshell.conf refreshed (yours -> quickshell.conf.backup-$STAMP)"
fi

# the Environment page writes the Qt half of the appearance - style, icon theme
# and fonts - into qt6ct.conf, and the shipped modules/env.lua exports
# QT_QPA_PLATFORMTHEME=qt6ct so Qt apps read it. envtool.py deliberately never
# creates that file: it refuses to conjure a config for a toolkit the machine
# does not use. so on a fresh machine the page's Qt switch is a silent no-op
# until something writes one. minimal on purpose - the page fills in the style,
# icons and fonts itself on the first apply.
QT6CT_CFG="$HOME/.config/qt6ct/qt6ct.conf"
if ! command -v qt6ct &>/dev/null; then
    say "  ${dim}qt6ct is not installed - the Environment page will skip Qt${r}"
elif [[ -f "$QT6CT_CFG" ]]; then
    say "  ${dim}keeping qt6ct/qt6ct.conf${r}"
else
    mkdir -p "$(dirname "$QT6CT_CFG")"
    printf '[Appearance]\nstyle=Fusion\n' > "$QT6CT_CFG"
    say "  qt6ct.conf -> ~/.config/qt6ct/qt6ct.conf"
fi

# --------------------------------------------------- notification ownership

# org.freedesktop.Notifications is a single-owner D-Bus name and Lucid's bar
# serves it. Any other notification daemon that is merely *installed* can be
# D-Bus-activated the moment something posts a notification - it does not have
# to be autostarted - and whoever claims the name first keeps it for the whole
# session. Lose that race and Lucid's toasts silently never appear: you get the
# other daemon's notification instead, while the bar looks perfectly fine.

step "Checking who serves notifications"

NOTIFY_RIVALS=()
for f in /usr/share/dbus-1/services/*.service "$HOME/.local/share/dbus-1/services/"*.service; do
    [[ -f "$f" ]] || continue
    grep -q '^Name=org.freedesktop.Notifications' "$f" || continue
    grep -qi 'quickshell' "$f" && continue
    NOTIFY_RIVALS+=("$f")
done

if [[ ${#NOTIFY_RIVALS[@]} -eq 0 ]]; then
    say "  ${dim}nothing else claims the name — Lucid's notifications win${r}"
else
    for f in "${NOTIFY_RIVALS[@]}"; do
        unit=$(sed -n 's/^SystemdService=//p' "$f" | head -n1)
        exe=$(sed -n 's/^Exec=//p' "$f" | head -n1 | awk '{print $1}')
        say "  ${ylw}$(basename "$exe")${r} also claims org.freedesktop.Notifications"
        say "  ${dim}($f)${r}"
    done
    say "  D-Bus starts it on the first notification, and it then keeps the"
    say "  name for the session — Lucid's own notifications never show."

    if ask "  Stop it taking over?"; then
        for f in "${NOTIFY_RIVALS[@]}"; do
            unit=$(sed -n 's/^SystemdService=//p' "$f" | head -n1)
            exe=$(sed -n 's/^Exec=//p' "$f" | head -n1 | awk '{print $1}')
            base=$(basename "$exe")
            if [[ -n "$unit" ]] && command -v systemctl &>/dev/null; then
                systemctl --user mask "$unit" &>/dev/null \
                    && say "  masked $unit (undo: systemctl --user unmask $unit)" \
                    || warn "  could not mask $unit — uninstall $base instead"
            else
                warn "  $base has no systemd unit to mask — uninstall it to be rid of it"
            fi
            # it may already hold the name in this session; the mask only
            # stops the next activation, so drop the running one too
            if pgrep -x "$base" &>/dev/null; then
                pkill -x "$base" &>/dev/null || true
                say "  stopped the running $base"
            fi
        done
        say "  ${dim}restart Lucid (or log back in) so it claims the name${r}"
    else
        warn "  left alone — expect its notifications instead of Lucid's"
    fi
fi

# ------------------------------------------------------------------ hyprland

# binds, window rules, blur, animations and autostart. this is a whole session
# config, so an existing one is always backed up first and replacing it is a
# question - except when it is Lucid's own from an earlier run, which is just
# refreshed. kept out of the theming step: the modules read no palette, so
# --no-theming should not cost you the binds.
HYPR_DIR="$HOME/.config/hypr"
HYPR_LUA_INSTALLED=0

# ----- FORK NOTICE ------ #
# I did not fix the mouse, i would accept pull requests

# the cursor that tilts as it moves is a Hyprland plugin (hypr-dynamic-cursors).
# scripts/cursor-plugin.sh compiles it against the headers the hyprland package
# itself installs, so the build always matches the Hyprland it is for, and
# modules/autostart.lua runs the same script on login to load it - rebuilding
# first when Hyprland has changed. hyprpm is not involved: it keeps its own
# copy of the headers, calls them current as long as the commit matches, and
# after a library update under the same Hyprland builds plugins that are
# refused with "version mismatch" until it is forced. none of this is fatal:
# a failed build leaves a cursor that simply does not tilt
CURSOR_PLUGIN="$HYPR_DIR/scripts/cursor-plugin.sh"
setup_cursor_plugin() {
    local so="${XDG_DATA_HOME:-$HOME/.local/share}/lucid/plugins/dynamic-cursors.so"
    local in_hypr=0
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && in_hypr=1

    # built on an earlier run: bring it up to date, which is a no-op when it is
    if [[ -f "$so" ]]; then
        if [[ $in_hypr -eq 1 ]]; then
            if "$CURSOR_PLUGIN" ensure; then
                say "  cursor plugin up to date and loaded"
            else
                warn "  the cursor plugin did not load — see: $CURSOR_PLUGIN status"
            fi
        else
            say "  ${dim}cursor plugin already built; it is loaded on login${r}"
        fi
        return 0
    fi

    say "  modules/plugins.lua is set up for a cursor that tilts as it moves"
    say "  (hypr-dynamic-cursors). it is compiled here, for your Hyprland."
    ask "  Build it now (about a minute, no password needed)?" || {
        say "  ${dim}skipped — later: $CURSOR_PLUGIN build && $CURSOR_PLUGIN load${r}"
        return 0
    }

    # the plugin's makefile, and the clone before it
    local need=() p
    { command -v make && command -v g++ && command -v pkg-config; } &>/dev/null || need+=(gcc-c++ make pkgconf-pkg-config)
    # the plugin compiles against the compositor's headers
    rpm -q hyprland-devel &>/dev/null || need+=(hyprland-devel)
    command -v git &>/dev/null || need+=(git)
    if (( ${#need[@]} )); then
        if [[ $SKIP_DEPS -eq 1 ]]; then
            warn "  the cursor plugin needs ${need[*]} (--skip-deps, not installing)"
            return 0
        fi
        sudo dnf install -y "${need[@]}" || {
            warn "  could not install ${need[*]} — the cursor plugin is left out"
            return 0
        }
    fi

    "$CURSOR_PLUGIN" build || {
        warn "  the cursor plugin did not build — everything else is unaffected"
        return 0
    }
    if [[ $in_hypr -eq 0 ]]; then
        say "  cursor plugin built; modules/autostart.lua loads it on login"
    elif "$CURSOR_PLUGIN" load; then
        say "  cursor plugin loaded; modules/autostart.lua loads it on every login"
    else
        warn "  the cursor plugin built but did not load — see: $CURSOR_PLUGIN status"
    fi

    # a copy hyprpm still has would be loaded a second time by anyone who
    # runs hyprpm reload at login
    if [[ -f "/var/cache/hyprpm/$USER/dynamic-cursors/state.toml" ]]; then
        say "  ${dim}hyprpm has a copy of this plugin too; it is no longer needed (hyprpm remove dynamic-cursors)${r}"
    fi
}

if [[ $WITH_HYPR -eq 1 ]]; then
    step "Setting up Hyprland"

    HAS_HYPR_CFG=0
    [[ -f "$HYPR_DIR/hyprland.lua" || -f "$HYPR_DIR/hyprland.conf" ]] && HAS_HYPR_CFG=1

    # a config we installed on an earlier run is not "someone else's config":
    # without telling them apart, a re-run asks to replace Lucid's own setup and
    # then tells you to add binds you already have
    HYPR_IS_LUCID=0
    if [[ -f "$HYPR_DIR/modules/binds.lua" ]] && grep -q 'qs ipc call' "$HYPR_DIR/modules/binds.lua" 2>/dev/null; then
        HYPR_IS_LUCID=1
    fi

    DO_HYPR=1
    if [[ $HYPR_IS_LUCID -eq 1 ]]; then
        say "  ${dim}already Lucid's — refreshing it${r}"
    elif [[ $HAS_HYPR_CFG -eq 1 && $HYPR_FORCE -eq 0 ]]; then
        say "  you already have a Hyprland config. Lucid's brings the binds,"
        say "  window rules, blur and animations, and yours is backed up first."
        if ! ask "  Replace it with Lucid's?"; then
            DO_HYPR=0
            say "  ${dim}left alone — re-run with --with-hypr to change your mind${r}"
        fi
    fi

    # the lua config only exists from Hyprland 0.55. an older one reads
    # hyprland.conf and ignores hyprland.lua, so replacing the config would
    # leave it with nothing but its own defaults - worth asking first.
    # `hyprctl version` prints "Hyprland 0.54.0 built from ..." with no v,
    # so the number is taken bare and compared as a number
    if [[ $DO_HYPR -eq 1 ]] && command -v hyprctl &>/dev/null; then
        HYPR_VER=$(hyprctl version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [[ -n "$HYPR_VER" ]]; then
            IFS=. read -r hv_major hv_minor _ <<< "$HYPR_VER"
            if (( hv_major == 0 && hv_minor < 55 )); then
                warn "  Hyprland $HYPR_VER predates the lua config (0.55+) — it will ignore hyprland.lua"
                if ! ask "  Install it anyway?"; then
                    DO_HYPR=0
                    say "  ${dim}left alone — update Hyprland, then re-run with --with-hypr${r}"
                fi
            fi
        fi
    fi

    if [[ $DO_HYPR -eq 1 ]]; then
        if [[ $HAS_HYPR_CFG -eq 1 ]]; then
            cp -r "$HYPR_DIR" "$HYPR_DIR.backup-$STAMP"
            say "  your hypr config -> $HYPR_DIR.backup-$STAMP"
        fi
        mkdir -p "$HYPR_DIR/modules" "$HYPR_DIR/scripts"
        cp "$SRC/support/hypr/hyprland.lua" "$HYPR_DIR/hyprland.lua"
        cp "$SRC/support/hypr/modules/"*.lua "$HYPR_DIR/modules/"
        install -m755 "$SRC/support/hypr/scripts/reload.sh" "$HYPR_DIR/scripts/reload.sh"
        install -m755 "$SRC/support/hypr/scripts/cursor-plugin.sh" "$HYPR_DIR/scripts/cursor-plugin.sh"
        # a hyprland.conf left beside hyprland.lua is ambiguous - Hyprland
        # reads one of them and you cannot tell which, so the install looks
        # like it did nothing. the full directory is already backed up above
        if [[ -f "$HYPR_DIR/hyprland.conf" ]]; then
            mv "$HYPR_DIR/hyprland.conf" "$HYPR_DIR/hyprland.conf.replaced-$STAMP"
            say "  hyprland.conf -> hyprland.conf.replaced-$STAMP (lua config wins now)"
            # a lua config cannot source a .conf, so whatever the old config
            # pulled in - hyprmod's hyprland-gui.conf, a file of your own -
            # stops being read here. name them, so the settings that vanish
            # with them are not a mystery: each needs a lua module in its
            # place (hyprmod adds require("hyprland-gui") when re-run)
            sourced=()
            while IFS= read -r f; do
                [[ -n "$f" ]] && sourced+=("$f")
            done < <(sed -nE 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//p' \
                        "$HYPR_DIR/hyprland.conf.replaced-$STAMP" \
                     | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//' || true)
            if (( ${#sourced[@]} )); then
                warn "  it sourced ${#sourced[@]} file(s) that hyprland.lua will not read:"
                for f in "${sourced[@]}"; do
                    say "    $f"
                done
                say "  ${dim}a lua config cannot source .conf files. whatever wrote those needs a lua module instead — hyprmod: re-run it and accept its require(\"hyprland-gui\") line${r}"
            fi
        fi
        HYPR_LUA_INSTALLED=1
        say "  hyprland.lua + $(ls "$SRC/support/hypr/modules" | wc -l) modules -> $HYPR_DIR"
        say "  ${dim}binds, window rules, blur, animations and autostart come with it${r}"
        # a refresh replaces hyprland.lua whole, but a require added to it
        # since the last run - hyprmod's require("hyprland-gui"), a module
        # of your own - is not Lucid's to drop. those lines go back in,
        # after Lucid's, so what they set still wins. only on a refresh:
        # a config replaced on request was meant to go
        if [[ $HYPR_IS_LUCID -eq 1 && -f "$HYPR_DIR.backup-$STAMP/hyprland.lua" ]]; then
            carried=()
            while IFS= read -r line; do
                grep -qxF -- "$line" "$HYPR_DIR/hyprland.lua" && continue
                printf '%s\n' "${carried[@]:-}" | grep -qxF -- "$line" && continue
                carried+=("$line")
            done < <(grep -E '^[[:space:]]*(pcall[[:space:]]*\([[:space:]]*)?(require|dofile)[[:space:]]*[(,]' \
                        "$HYPR_DIR.backup-$STAMP/hyprland.lua" || true)
            if (( ${#carried[@]} )); then
                {
                    printf '\n-- kept by the Lucid installer: these were added to hyprland.lua after it was installed\n'
                    printf '%s\n' "${carried[@]}"
                } >> "$HYPR_DIR/hyprland.lua"
                say "  kept ${#carried[@]} require line(s) added to hyprland.lua since the last install"
            fi
        fi

        # modules/binds.lua binds from this list, which Settings -> Keybinds
        # edits. an existing one is yours and survives the refresh
        mkdir -p "$LUCID_DIR"
        if [[ -s "$LUCID_DIR/keybinds.json" ]]; then
            say "  ${dim}keeping existing $LUCID_DIR/keybinds.json${r}"
        else
            cp "$SRC/support/hypr/keybinds.json" "$LUCID_DIR/keybinds.json"
            say "  keybinds -> $LUCID_DIR/keybinds.json"
        fi

        # modules/plugins.lua carries the settings for Hyprland plugins; each
        # block only applies while its plugin is loaded, so without one it is inert
        if [[ $WITH_PLUGINS -eq 1 ]]; then
            setup_cursor_plugin
        else
            say "  ${dim}cursor plugin skipped (--no-plugins)${r}"
        fi

        # the binds shell out to these, so a missing one is a dead key rather
        # than a visible error. worth saying now, not after the first F-key
        for c in kitty nautilus playerctl gnome-calculator wpctl brightnessctl; do
            command -v "$c" &>/dev/null || warn "  $c is missing — the binds that use it will do nothing"
        done

    fi
else
    step "Skipping the Hyprland config (--no-hypr)"
    say "  ${dim}the Lucid binds and window rules are not installed${r}"
fi

# ------------------------------------------------------------------ theming

if [[ $WITH_THEMING -eq 1 ]]; then
    step "Installing the theming layer"

    mkdir -p "$LUCID_DIR/themes" "$MATUGEN_DIR/templates" "$WALL_SCRIPT_DIR" "$HOME/.cache/quickshell"

    cp -r "$SRC/support/lucid/themes/." "$LUCID_DIR/themes/"
    install -m755 "$SRC/support/lucid/apply-theme.sh"      "$LUCID_DIR/apply-theme.sh"
    install -m755 "$SRC/support/lucid/render-templates.sh" "$LUCID_DIR/render-templates.sh"
    install -m755 "$SRC/support/lucid/templates.py"       "$LUCID_DIR/templates.py"
    install -m755 "$SRC/support/lucid/apply-colour.sh"    "$LUCID_DIR/apply-colour.sh"
    install -m755 "$SRC/support/lucid/wallpaper-colours.sh" "$LUCID_DIR/wallpaper-colours.sh"
    install -m644 "$SRC/support/lucid/matugen-options.sh" "$LUCID_DIR/matugen-options.sh"
    install -m755 "$SRC/support/lucid/gen-pywal-palette.py" "$LUCID_DIR/gen-pywal-palette.py"
    install -m755 "$SRC/support/lucid/add-theme.py"        "$LUCID_DIR/add-theme.py"
    install -m755 "$SRC/support/lucid/scheme-gallery.py"   "$LUCID_DIR/scheme-gallery.py"
    install -m755 "$SRC/support/lucid/palette-edit.py"     "$LUCID_DIR/palette-edit.py"
    install -m755 "$SRC/support/lucid/gen-light-palette.py" "$LUCID_DIR/gen-light-palette.py"
    install -m755 "$SRC/support/lucid/app-palette.py"      "$LUCID_DIR/app-palette.py"
    install -m755 "$SRC/support/lucid/set-mode.sh"         "$LUCID_DIR/set-mode.sh"
    install -m755 "$SRC/support/lucid/sync-sddm.sh"        "$LUCID_DIR/sync-sddm.sh"
    install -m755 "$SRC/support/lucid/sync-starship.sh"    "$LUCID_DIR/sync-starship.sh"
    install -m644 "$SRC/support/lucid/lucid_palette.py"    "$LUCID_DIR/lucid_palette.py"
    install -m755 "$SRC/support/wallpaper/set-wallpaper.sh" "$WALL_SCRIPT_DIR/set-wallpaper.sh"
    # rules you wrote are yours: only ever placed when there are none
    [[ -f "$LUCID_DIR/wallpaper-outputs.conf" ]] || install -m644 "$SRC/support/lucid/wallpaper-outputs.conf" "$LUCID_DIR/wallpaper-outputs.conf"
    # the sddm theme lives outside $HOME, so it is the one thing here that
    # needs root. skipped entirely when sddm is not installed, and it never
    # switches the active theme - that stays the user's call. root keeps the
    # theme; every account paints its own corner of it without a password
    if [[ -d /usr/share/sddm/themes ]]; then
        SDDM_THEME_DIR=/usr/share/sddm/themes/lucid
        # a fingerprint at the login screen needs two lines in sddm's pam
        # service, so it is asked for once and then kept on every re-run
        SDDM_FINGER=()
        if [[ -e /usr/lib64/security/pam_fprintd.so || -e /usr/lib/security/pam_fprintd.so ]]; then
            if grep -q '^# >>> lucid: fingerprint login' /etc/pam.d/sddm 2>/dev/null; then
                SDDM_FINGER=(--fingerprint)
            elif ask "  Let the login screen take a fingerprint too? (two lines in /etc/pam.d/sddm, backed up first)"; then
                SDDM_FINGER=(--fingerprint)
            fi
        fi
        if sudo bash "$SRC/support/sddm/install-theme.sh" "$SDDM_THEME_DIR" "${SDDM_FINGER[@]}"; then
            say "  sddm theme      -> $SDDM_THEME_DIR"
            # the theme no longer carries a shared wallpaper, so paint this
            # account's corner now rather than at its next login. it reads
            # the palette through qs, which needs the session's display
            if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
                "$LUCID_DIR/sync-sddm.sh" --missing &>/dev/null || true
            fi
            # /etc/sddm.conf outranks /etc/sddm.conf.d, so point at the file
            # that actually wins rather than at the tidier-looking drop-in
            say "    enable it with: Current=lucid under [Theme] in /etc/sddm.conf"
        else
            warn "could not install the sddm theme (needs sudo); skipping"
        fi
    fi

    say "  theme palettes  -> $LUCID_DIR/themes"
    say "  theme scripts   -> $LUCID_DIR"
    say "  wallpaper hook  -> $WALL_SCRIPT_DIR/set-wallpaper.sh"

    cp -r "$SRC/support/matugen/templates/." "$MATUGEN_DIR/templates/"
    say "  matugen templates -> $MATUGEN_DIR/templates/"

    MATUGEN_CFG="$MATUGEN_DIR/config.toml"
    [[ -f "$MATUGEN_CFG" ]] && cp "$MATUGEN_CFG" "$MATUGEN_CFG.backup-$STAMP"
    [[ -f "$MATUGEN_CFG" ]] || printf '[config]\n' > "$MATUGEN_CFG"

    TPL='~/.config/matugen/templates'
    MG_ADDED=(); MG_KEPT=(); MG_SKIPPED=()

    # older installs gave starship a matugen template, which wrote the whole
    # starship.toml and so replaced any prompt the user had made. only its
    # palette is repainted now (sync-starship.sh), so Lucid's own block goes;
    # a starship block pointing anywhere else is the user's and stays
    if grep -q '^\[templates\.starship\]' "$MATUGEN_CFG"; then
        awk '
            function flush() { if (!(inblk && lucid)) printf "%s", blk; blk = ""; inblk = 0; lucid = 0 }
            /^\[/ { flush(); if ($0 ~ /^\[templates\.starship\]/) inblk = 1 }
            { blk = blk $0 "\n"; if (inblk && $0 ~ /starship-colors\.toml/) lucid = 1 }
            END { flush() }
        ' "$MATUGEN_CFG" > "$MATUGEN_CFG.lucid-tmp" && cat "$MATUGEN_CFG.lucid-tmp" > "$MATUGEN_CFG"
        rm -f "$MATUGEN_CFG.lucid-tmp"
    fi

    # a block is only added when the app it themes is actually present, so
    # matugen never writes colours into a config directory that isn't there.
    # an existing block is always left alone - this config is the user's.
    add_template() {
        local name=$1 input=$2 output=$3 guard=${4:-always} hook=${5:-}
        case "$guard" in
            always) ;;
            dir:*)  [[ -d "${guard#dir:}" ]] || { MG_SKIPPED+=("$name"); return 0; } ;;
            file:*) [[ -f "${guard#file:}" ]] || { MG_SKIPPED+=("$name"); return 0; } ;;
            cmd:*)  command -v "${guard#cmd:}" &>/dev/null || { MG_SKIPPED+=("$name"); return 0; } ;;
        esac
        if grep -q "^\[templates\.$name\]" "$MATUGEN_CFG"; then
            MG_KEPT+=("$name"); return 0
        fi
        mkdir -p "$(dirname "${output/#\~/$HOME}")"
        {
            printf '\n[templates.%s]\n' "$name"
            printf "input_path = '%s'\n" "$input"
            printf "output_path = '%s'\n" "$output"
            [[ -n "$hook" ]] && printf "post_hook = '%s'\n" "$hook" || true
        } >> "$MATUGEN_CFG"
        MG_ADDED+=("$name")
    }

    add_template quickshell     "$TPL/quickshell-colors.json"  '~/.cache/quickshell/matugen.json'
    add_template vscode-raw     "$TPL/vscode-colors"           '~/.cache/matugen/vscode-colors'
    add_template vscode-json    "$TPL/vscode-colors.json"      '~/.cache/matugen/vscode-colors.json'
    add_template hyprland       "$TPL/hyprland-colors.lua"     '~/.config/hypr/colors.conf'    "dir:$HOME/.config/hypr"
    add_template kitty          "$TPL/kitty.conf"              '~/.config/kitty/matugen-colors.conf' "cmd:kitty" 'killall -SIGUSR1 kitty 2>/dev/null || true'
    # no dir: guard on these two. gtk only creates ~/.config/gtk-{3,4}.0 once
    # an app writes a setting there, so on a fresh machine the guard skipped
    # both templates, matugen never wrote colors.css, and nautilus kept its
    # stock colours forever. add_template creates the directory itself.
    add_template gtk3           "$TPL/gtk-colors.css"          '~/.config/gtk-3.0/colors.css'
    add_template gtk4           "$TPL/gtk-colors.css"          '~/.config/gtk-4.0/colors.css'
    add_template rofi           "$TPL/rofi-colors.rasi"        '~/.config/rofi/colors.rasi'    "dir:$HOME/.config/rofi"
    add_template waybar         "$TPL/colors.css"              '~/.config/waybar/colors.css'   "dir:$HOME/.config/waybar"
    add_template swaync         "$TPL/colors.css"              '~/.config/swaync/colors.css'   "dir:$HOME/.config/swaync"
    add_template wlogout        "$TPL/colors.css"              '~/.config/wlogout/colors.css'  "dir:$HOME/.config/wlogout"
    add_template ags            "$TPL/ags-colors.scss"         '~/.config/ags/style/_colors.scss' "dir:$HOME/.config/ags"
    add_template vesktop        "$TPL/midnight-discord.css"    '~/.config/vesktop/themes/midnight-discord.css' "dir:$HOME/.config/vesktop"
    add_template pywalfox       "$TPL/pywalfox-colors.json"    '~/.cache/wal/colors.json'      "cmd:pywalfox" 'pywalfox update'
    add_template steam-material "$TPL/steam-material.css"      '~/.local/share/Steam/millennium/themes/Material-Theme/css/main/colors/matugen.css' \
                                "dir:$HOME/.local/share/Steam/millennium/themes/Material-Theme"
    # Qt widget apps take their palette from qt6ct, the platform theme
    # modules/env.lua sets. KDE apps then lay a KDE colour scheme over it, so
    # they get one too - both are pointed at below. qt6ct watches its own
    # folder but not colors/, so the hook touches qt6ct.conf for open apps
    add_template qt6ct          "$TPL/qt6ct-colors.conf"       '~/.config/qt6ct/colors/lucid.conf' "cmd:qt6ct" \
                                'touch -c ~/.config/qt6ct/qt6ct.conf'
    add_template kde            "$TPL/kde-colors.colors"       '~/.local/share/color-schemes/Lucid.colors' "cmd:qt6ct"

    # firefox and zen keep their chrome css inside a generated profile dir, so
    # the path has to be discovered rather than assumed
    FF_PROFILE=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -type d -name '*.default-release' 2>/dev/null | head -1 || true)
    ZEN_PROFILE=$(find "$HOME/.config/zen" -maxdepth 1 -type d -name '*.Default*' 2>/dev/null | head -1 || true)
    if [[ -n "$FF_PROFILE" ]]; then
        add_template firefox-website-colors "$TPL/firefox-colors.css" "$FF_PROFILE/chrome/colors.css"
    else
        MG_SKIPPED+=(firefox-website-colors)
    fi
    if [[ -n "$ZEN_PROFILE" ]]; then
        add_template zen "$TPL/zen-userchrome.css" "$ZEN_PROFILE/chrome/userChrome.css"
    else
        MG_SKIPPED+=(zen)
    fi

    (( ${#MG_ADDED[@]} ))   && say "  matugen added:   ${MG_ADDED[*]}"                                || true
    (( ${#MG_KEPT[@]} ))    && say "  ${dim}matugen kept:    ${MG_KEPT[*]}${r}"                       || true
    (( ${#MG_SKIPPED[@]} )) && say "  ${dim}matugen skipped: ${MG_SKIPPED[*]} (not installed)${r}"    || true

    # put keys under [section] of an ini file, creating the section - or the
    # file - when it isn't there
    ini_add_keys() {
        local file=$1 section=$2 keys=$3
        mkdir -p "$(dirname "$file")"
        if [[ ! -f "$file" ]]; then
            printf '[%s]\n%s\n' "$section" "$keys" > "$file"
        elif grep -qxF "[$section]" "$file"; then
            awk -v s="[$section]" -v k="$keys" '{ print } $0 == s { print k }' "$file" > "$file.lucid-tmp" \
                && cat "$file.lucid-tmp" > "$file"
            rm -f "$file.lucid-tmp"
        else
            printf '\n[%s]\n%s\n' "$section" "$keys" >> "$file"
        fi
    }

    # with no palette chosen in qt6ct, Qt apps (Prism Launcher, qt6ct itself...)
    # get Qt's stock light one whatever the theme. a palette already picked
    # there is the user's and stays
    QT6CT_CFG="$HOME/.config/qt6ct/qt6ct.conf"
    if command -v qt6ct &>/dev/null && grep -q '^\[templates\.qt6ct\]' "$MATUGEN_CFG"; then
        if grep -qE '^(custom_palette|color_scheme_path)=' "$QT6CT_CFG" 2>/dev/null; then
            say "  ${dim}qt6ct already has a palette${r}"
        else
            ini_add_keys "$QT6CT_CFG" Appearance \
                "color_scheme_path=$HOME/.config/qt6ct/colors/lucid.conf"$'\n'"custom_palette=true"
            say "  qt6ct now uses the theme's palette"
        fi
    fi

    # outside Plasma, a KDE app (Dolphin, Kate, Okular...) with no colour scheme
    # named in kdeglobals swaps the qt6ct palette for Breeze Light or Dark as it
    # starts, so name Lucid's. one already named - by Plasma under [General] or
    # by the user - stays
    KDEGLOBALS="$HOME/.config/kdeglobals"
    if command -v qt6ct &>/dev/null && grep -q '^\[templates\.kde\]' "$MATUGEN_CFG"; then
        if grep -q '^ColorScheme=' "$KDEGLOBALS" 2>/dev/null; then
            say "  ${dim}kdeglobals already names a colour scheme${r}"
        else
            ini_add_keys "$KDEGLOBALS" UiSettings "ColorScheme=Lucid"
            say "  KDE apps now use the theme's colour scheme"
        fi
    fi

    # GTK apps - Nautilus included - only read colors.css if gtk.css imports it
    for gtkver in 3.0 4.0; do
        gtkdir="$HOME/.config/gtk-$gtkver"
        mkdir -p "$gtkdir"
        if [[ -f "$gtkdir/gtk.css" ]] && grep -q "colors.css" "$gtkdir/gtk.css"; then
            say "  ${dim}gtk-$gtkver already imports colors.css${r}"
        else
            [[ -f "$gtkdir/gtk.css" ]] && cp "$gtkdir/gtk.css" "$gtkdir/gtk.css.backup-$STAMP"
            printf "@import url('colors.css');\n" >> "$gtkdir/gtk.css"
            say "  gtk-$gtkver now imports colors.css"
        fi
    done

    # --- the look: terminal + prompt + blur -------------------------------
    # each piece is additive and backed up first, because these are files the
    # user owns and may already have tuned
    if [[ $WITH_LOOK -eq 1 ]] && ask "  Apply the Lucid look (kitty, starship prompt, fastfetch, VSCode theme, GTK theme + icons)?"; then

        # --- gtk theme + icons --------------------------------------------
        # gtk reads three places and they disagree happily. under hyprland
        # there is no xsettings daemon, so gtk3/gtk4 take settings.ini as the
        # source of truth while gnome apps and portals read gsettings - set
        # both or half your apps stay light. settings.ini is merged key by
        # key: it also carries the user's font, cursor and hinting choices.
        GTK_THEME_NAME=adw-gtk3-dark
        ICON_THEME_NAME=FairyWren_Dark

        # replace the key if it is there, insert it under [Settings] if not
        ini_set() {
            local f=$1 k=$2 v=$3
            mkdir -p "$(dirname "$f")"
            if [[ ! -f "$f" ]]; then
                printf '[Settings]\n%s=%s\n' "$k" "$v" > "$f"
                return 0
            fi
            grep -q '^\[Settings\]' "$f" || printf '\n[Settings]\n' >> "$f"
            if grep -q "^$k=" "$f"; then
                sed -i "s|^$k=.*|$k=$v|" "$f"
            else
                sed -i "0,/^\[Settings\]/s|^\[Settings\]|[Settings]\n$k=$v|" "$f"
            fi
        }

        # FairyWren is not in the repos and distro packages slice it into 52
        # per-colour themes with different names, so take it from upstream:
        # the two directories there are exactly the theme names set below
        ICONS_DIR="$HOME/.local/share/icons"
        if [[ -d "$ICONS_DIR/$ICON_THEME_NAME" ]]; then
            say "  ${dim}keeping the FairyWren icons already in $ICONS_DIR${r}"
        elif ! command -v git &>/dev/null; then
            warn "  git is not installed — skipping the FairyWren icon theme"
            ICON_THEME_NAME=""
        else
            say "  fetching the FairyWren icon theme (~140MB, one-time)"
            FW_TMP=$(mktemp -d)
            if git clone --depth 1 https://gitlab.com/FreshDoctor/FairyWren-Icons.git \
                 "$FW_TMP/fw" &>/dev/null \
               && [[ -d "$FW_TMP/fw/FairyWren_Dark" && -d "$FW_TMP/fw/FairyWren_Light" ]]; then
                mkdir -p "$ICONS_DIR"
                cp -r "$FW_TMP/fw/FairyWren_Dark" "$FW_TMP/fw/FairyWren_Light" "$ICONS_DIR/"
                say "  FairyWren icons -> $ICONS_DIR"
            else
                warn "  could not fetch the FairyWren icons — leaving the icon theme alone"
                ICON_THEME_NAME=""
            fi
            rm -rf "$FW_TMP"
        fi

        # the loader only rescans a theme once its cache is rebuilt
        if [[ -n "$ICON_THEME_NAME" ]] && command -v gtk-update-icon-cache &>/dev/null; then
            for v in Dark Light; do
                [[ -d "$ICONS_DIR/FairyWren_$v" ]] || continue
                gtk-update-icon-cache -qtf "$ICONS_DIR/FairyWren_$v" &>/dev/null || true
            done
        fi

        # adw-gtk3-dark ships inside adw-gtk-theme rather than as its own
        # package, so check the theme directory, not the package name
        if [[ ! -d /usr/share/themes/$GTK_THEME_NAME && ! -d "$HOME/.themes/$GTK_THEME_NAME" ]]; then
            warn "  $GTK_THEME_NAME is not installed — install adw-gtk3-theme"
        fi

        for gtkver in 3.0 4.0; do
            gtkini="$HOME/.config/gtk-$gtkver/settings.ini"
            [[ -f "$gtkini" ]] && cp "$gtkini" "$gtkini.backup-$STAMP"
            ini_set "$gtkini" gtk-theme-name "$GTK_THEME_NAME"
            ini_set "$gtkini" gtk-application-prefer-dark-theme 1
            [[ -n "$ICON_THEME_NAME" ]] && ini_set "$gtkini" gtk-icon-theme-name "$ICON_THEME_NAME"
        done
        say "  gtk-3.0 and gtk-4.0 settings.ini -> $GTK_THEME_NAME${ICON_THEME_NAME:+ + $ICON_THEME_NAME}"

        # gnome apps, portals and anything reading dconf take these instead
        if command -v gsettings &>/dev/null; then
            gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
            [[ -n "$ICON_THEME_NAME" ]] && \
                gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME_NAME" 2>/dev/null || true
            say "  gsettings -> $GTK_THEME_NAME, prefer-dark${ICON_THEME_NAME:+, $ICON_THEME_NAME}"
        else
            warn "  gsettings not found — GNOME apps may ignore the theme"
        fi

        # kitty - the include is what makes matugen's colours apply at all
        KITTY_CFG="$HOME/.config/kitty/kitty.conf"
        KITTY_EXISTED=0; [[ -f "$KITTY_CFG" ]] && KITTY_EXISTED=1

        # a kitty.conf an earlier install shipped, with nothing of the user's
        # in it: every setting is one Lucid wrote, then or now. that copy is
        # swapped for the current one; any other is theirs and only gets the
        # includes below
        kitty_is_lucids() {
            [[ $(head -n1 "$1") == "# Lucid — kitty" ]] || return 1
            local ours extra
            ours=$(grep -vE '^[[:space:]]*(#|$)' "$SRC/support/look/kitty.conf"; printf '%s\n' "background_opacity 0.7")
            extra=$(grep -vE '^[[:space:]]*(#|$)' "$1" | grep -vxF -e "$ours" || true)
            [[ -z $extra ]]
        }
        if [[ -f "$KITTY_CFG" ]] && ! cmp -s "$KITTY_CFG" "$SRC/support/look/kitty.conf" && kitty_is_lucids "$KITTY_CFG"; then
            cp "$KITTY_CFG" "$KITTY_CFG.backup-$STAMP"
            cp "$SRC/support/look/kitty.conf" "$KITTY_CFG"
            say "  kitty.conf -> the current Lucid one (the old copy: kitty.conf.backup-$STAMP)"
        fi

        if [[ -f "$HOME/.config/kitty/kitty.conf" ]]; then
            if grep -q "matugen-colors.conf" "$HOME/.config/kitty/kitty.conf"; then
                say "  ${dim}kitty.conf already includes matugen-colors.conf${r}"
            else
                cp "$HOME/.config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf.backup-$STAMP"
                printf '\n# added by Lucid — colours follow the active theme\ninclude ./matugen-colors.conf\n' \
                    >> "$HOME/.config/kitty/kitty.conf"
                say "  kitty.conf now includes matugen-colors.conf"
            fi
        else
            mkdir -p "$HOME/.config/kitty"
            cp "$SRC/support/look/kitty.conf" "$HOME/.config/kitty/kitty.conf"
            say "  kitty.conf -> ~/.config/kitty/kitty.conf"
        fi

        # background_opacity follows the Glass slider, out of a file the shell
        # rewrites. seed it first: kitty warns about an include it cannot find,
        # and the shell only writes once the value differs from what is there
        if [[ ! -f "$HOME/.config/kitty/lucid-glass.conf" ]]; then
            printf '# generated by lucid settings\ndynamic_background_opacity yes\nbackground_opacity 1.00\n' \
                > "$HOME/.config/kitty/lucid-glass.conf"
            say "  lucid-glass.conf -> ~/.config/kitty/lucid-glass.conf"
        fi
        if grep -q "lucid-glass.conf" "$KITTY_CFG"; then
            say "  ${dim}kitty.conf already includes lucid-glass.conf${r}"
        else
            [[ $KITTY_EXISTED -eq 1 && ! -f "$KITTY_CFG.backup-$STAMP" ]] \
                && cp "$KITTY_CFG" "$KITTY_CFG.backup-$STAMP"
            printf '\n# added by Lucid — opacity follows the Glass slider\ninclude ./lucid-glass.conf\n' \
                >> "$KITTY_CFG"
            say "  kitty.conf now follows the Glass slider"
        fi

        # kitty opens fish rather than the login shell. only wired when fish is
        # really there: kitty fails to open a window at all on a shell it cannot
        # exec, and that reads as "the terminal keybind is broken"
        if command -v fish &>/dev/null; then
            if grep -qE '^[[:space:]]*shell[[:space:]]+' "$KITTY_CFG"; then
                say "  ${dim}kitty.conf already sets a shell${r}"
            else
                [[ $KITTY_EXISTED -eq 1 && ! -f "$KITTY_CFG.backup-$STAMP" ]] \
                    && cp "$KITTY_CFG" "$KITTY_CFG.backup-$STAMP"
                printf '\n# added by Lucid\nshell fish\n' >> "$KITTY_CFG"
                say "  kitty.conf now opens fish"
            fi
        else
            sed -i '/^# kitty opens fish rather than the login shell$/d; /^shell fish$/d' "$KITTY_CFG"
            warn "  fish is not installed — kitty will use your login shell"
        fi

        # vscode / vscodium - matugen writes the colour files, but they do
        # nothing until the Matugen theme extension is installed and selected
        vscode_wire() {
            local cli=$1 cfg=$2
            command -v "$cli" &>/dev/null || return 0
            if "$cli" --list-extensions 2>/dev/null | grep -i "matugen-theme" >/dev/null; then
                say "  ${dim}$cli already has the Matugen theme${r}"
            elif "$cli" --install-extension haikalllp.matugen-theme &>/dev/null; then
                say "  installed the Matugen theme extension for $cli"
            else
                warn "  could not install the Matugen theme for $cli — do it by hand"
            fi

            mkdir -p "$(dirname "$cfg")"
            if [[ ! -f "$cfg" ]]; then
                printf '{\n  "workbench.colorTheme": "Matugen"\n}\n' > "$cfg"
                say "  $cli settings.json -> Matugen theme"
            elif grep -q '"workbench.colorTheme"' "$cfg"; then
                say "  ${dim}$cli already sets workbench.colorTheme${r}"
            else
                cp "$cfg" "$cfg.backup-$STAMP"
                # settings.json is jsonc - trailing commas are legal there - so
                # insert as text rather than reparsing and reformatting it
                awk 'ins != 1 && /\{/ { print; print "  \"workbench.colorTheme\": \"Matugen\","; ins = 1; next } 1' \
                    "$cfg" > "$cfg.lucid-tmp" && mv "$cfg.lucid-tmp" "$cfg"
                if grep -q '"workbench.colorTheme"' "$cfg"; then
                    say "  $cli now uses the Matugen theme"
                else
                    cp "$cfg.backup-$STAMP" "$cfg"
                    warn "  couldn't edit $cli settings.json — set the Matugen theme by hand"
                fi
            fi
        }

        vscode_wire codium   "$HOME/.config/VSCodium/User/settings.json"
        vscode_wire code     "$HOME/.config/Code/User/settings.json"
        vscode_wire code-oss "$HOME/.config/Code - OSS/User/settings.json"

        # starship - the prompt shape ships here; sync-starship.sh rewrites
        # only its [palettes.colors] block on every theme change, so this
        # file is what makes the prompt look like Lucid's
        STARSHIP_CFG="$HOME/.config/starship.toml"
        # the prompt without its colour table, which every theme repaints.
        # the older ones are the prompts earlier releases shipped
        starship_shape() { awk '/^\[/ { skip = ($0 == "[palettes.colors]") } !skip' "$1" | md5sum | cut -c1-32; }
        STARSHIP_OLD_SHAPES="45f0cc0634e505763613a1c4b8bbdbc5 fc6cc84e525ac275570158a41d7dfc66"
        if [[ ! -f "$STARSHIP_CFG" ]]; then
            cp "$SRC/support/look/starship.toml" "$STARSHIP_CFG"
            say "  starship.toml -> ~/.config/starship.toml"
        elif grep -q '^\[palettes.colors\]' "$STARSHIP_CFG"; then
            shape=$(starship_shape "$STARSHIP_CFG")
            if [[ $shape == "$(starship_shape "$SRC/support/look/starship.toml")" ]]; then
                # its colours are whatever the current theme painted, so
                # re-copying would only reset them to the seed
                say "  ${dim}keeping your starship.toml (already the Lucid prompt)${r}"
            elif [[ " $STARSHIP_OLD_SHAPES " == *" $shape "* ]]; then
                # an earlier release's prompt, untouched: the new one goes in
                # and takes the current theme's colours straight away
                cp "$STARSHIP_CFG" "$STARSHIP_CFG.backup-$STAMP"
                cp "$SRC/support/look/starship.toml" "$STARSHIP_CFG"
                [[ -x "$LUCID_DIR/sync-starship.sh" ]] && "$LUCID_DIR/sync-starship.sh" &>/dev/null || true
                say "  starship.toml -> the new Lucid prompt (the old one: starship.toml.backup-$STAMP)"
            else
                # a Lucid prompt someone has made their own
                say "  ${dim}keeping your starship.toml; the new Lucid prompt is support/look/starship.toml${r}"
            fi
        else
            cp "$STARSHIP_CFG" "$STARSHIP_CFG.backup-$STAMP"
            cp "$SRC/support/look/starship.toml" "$STARSHIP_CFG"
            say "  your starship.toml -> starship.toml.backup-$STAMP"
            say "  starship.toml -> ~/.config/starship.toml"
        fi
        command -v starship &>/dev/null \
            || warn "  starship is not installed — the prompt config is in place but unused"

        # the config does nothing until the shell actually calls starship, and
        # the init line differs per shell. only ever appended, never rewritten.
        # a missing rc is created for your login shell only - writing a .zshrc
        # for someone who does not use zsh is just litter
        LOGIN_SH=$(basename "${SHELL:-}")
        starship_init() {
            local rc=$1 line=$2 shname=$3 always=${4:-0}
            if [[ ! -f "$rc" ]]; then
                [[ "$shname" == "$LOGIN_SH" || $always -eq 1 ]] || return 0
                mkdir -p "$(dirname "$rc")"
                printf '# added by Lucid\n%s\n' "$line" > "$rc"
                say "  created $(basename "$rc") to start starship"
                return 0
            fi
            if grep -F 'starship init' "$rc" >/dev/null; then
                say "  ${dim}$(basename "$rc") already starts starship${r}"
            else
                cp "$rc" "$rc.backup-$STAMP"
                printf '\n# added by Lucid\n%s\n' "$line" >> "$rc"
                say "  $(basename "$rc") now starts starship"
            fi
        }
        starship_init "$HOME/.bashrc"                  'eval "$(starship init bash)"'   bash
        # zsh redraws on SIGWINCH but does not re-run precmd, so the prompt keeps
        # the old colours until you press enter. reset-prompt re-runs starship.
        # bash has no equivalent - its prompt updates on the next prompt instead
        starship_init "$HOME/.zshrc" 'eval "$(starship init zsh)"
TRAPWINCH() { zle && { zle reset-prompt; zle -R } }'    zsh
        # always for fish, whatever the login shell is - kitty opens it
        starship_init "$HOME/.config/fish/config.fish" 'starship init fish | source'    fish 1

        # the prompt and kitty.conf are drawn with nerd font glyphs; without
        # the font every segment renders as a replacement box
        fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd Font' >/dev/null \
            || warn "  JetBrainsMono Nerd Font is missing — the prompt will show boxes"

        # fastfetch - its keys, title and logo are ANSI 32 (color2), which
        # every Lucid theme paints the primary, so it follows the theme. a
        # config of your own stays as it is
        FASTFETCH_CFG="$HOME/.config/fastfetch/config.jsonc"
        if [[ ! -f "$FASTFETCH_CFG" ]]; then
            mkdir -p "$(dirname "$FASTFETCH_CFG")"
            cp "$SRC/support/look/fastfetch.jsonc" "$FASTFETCH_CFG"
            say "  fastfetch config -> ~/.config/fastfetch/config.jsonc"
        elif cmp -s "$FASTFETCH_CFG" "$SRC/support/look/fastfetch.jsonc"; then
            say "  ${dim}fastfetch config is already Lucid's${r}"
        else
            say "  ${dim}keeping your fastfetch config; Lucid's is support/look/fastfetch.jsonc${r}"
        fi

        # hyprland blur - skipped when the lua config went in above, since its
        # decorations module already carries the same blur
        if [[ $HYPR_LUA_INSTALLED -eq 1 ]]; then
            say "  ${dim}blur comes from modules/decorations.lua${r}"
        elif [[ -f "$HYPR_DIR/hyprland.lua" ]]; then
            mkdir -p "$HYPR_DIR/modules"
            cp "$SRC/support/look/lucid-look.lua" "$HYPR_DIR/modules/lucid-look.lua"
            # per-app glass rides along: Settings > Glass writes lucid-glass.lua
            # and this is the module that reads it
            cp "$SRC/support/hypr/modules/glass.lua" "$HYPR_DIR/modules/glass.lua"
            # and so do the options Settings > Windows sets, in lucid-settings.lua
            cp "$SRC/support/hypr/modules/settings.lua" "$HYPR_DIR/modules/settings.lua"
            # and the apps and variables Settings > Startup keeps, in lucid-startup.lua
            cp "$SRC/support/hypr/modules/startup.lua" "$HYPR_DIR/modules/startup.lua"
            if grep -q 'require("modules.lucid-look")' "$HYPR_DIR/hyprland.lua"; then
                say "  ${dim}hyprland.lua already requires modules.lucid-look${r}"
            else
                cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.backup-$STAMP"
                printf '\nrequire("modules.lucid-look")\n' >> "$HYPR_DIR/hyprland.lua"
                say "  hyprland.lua now requires modules.lucid-look"
            fi
            if grep -q 'require("modules.glass")' "$HYPR_DIR/hyprland.lua"; then
                say "  ${dim}hyprland.lua already requires modules.glass${r}"
            else
                [[ -f "$HYPR_DIR/hyprland.lua.backup-$STAMP" ]] \
                    || cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.backup-$STAMP"
                printf '\nrequire("modules.glass")\n' >> "$HYPR_DIR/hyprland.lua"
                say "  hyprland.lua now requires modules.glass"
            fi
            if grep -q 'require("modules.settings")' "$HYPR_DIR/hyprland.lua"; then
                say "  ${dim}hyprland.lua already requires modules.settings${r}"
            else
                [[ -f "$HYPR_DIR/hyprland.lua.backup-$STAMP" ]] \
                    || cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.backup-$STAMP"
                printf '\nrequire("modules.settings")\n' >> "$HYPR_DIR/hyprland.lua"
                say "  hyprland.lua now requires modules.settings"
            fi
            if grep -q 'require("modules.startup")' "$HYPR_DIR/hyprland.lua"; then
                say "  ${dim}hyprland.lua already requires modules.startup${r}"
            else
                [[ -f "$HYPR_DIR/hyprland.lua.backup-$STAMP" ]] \
                    || cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.backup-$STAMP"
                printf '\nrequire("modules.startup")\n' >> "$HYPR_DIR/hyprland.lua"
                say "  hyprland.lua now requires modules.startup"
            fi
        elif [[ -f "$HYPR_DIR/hyprland.conf" ]]; then
            cp "$SRC/support/look/lucid-look.conf" "$HYPR_DIR/lucid-look.conf"
            if grep -q "lucid-look.conf" "$HYPR_DIR/hyprland.conf"; then
                say "  ${dim}hyprland.conf already sources lucid-look.conf${r}"
            else
                cp "$HYPR_DIR/hyprland.conf" "$HYPR_DIR/hyprland.conf.backup-$STAMP"
                printf '\nsource = ~/.config/hypr/lucid-look.conf\n' >> "$HYPR_DIR/hyprland.conf"
                say "  hyprland.conf now sources lucid-look.conf"
            fi
        else
            mkdir -p "$HYPR_DIR"
            cp "$SRC/support/look/lucid-look.conf" "$HYPR_DIR/lucid-look.conf"
            warn "  no hyprland config found — source lucid-look.conf yourself"
        fi
    fi

    # first-run palette, so the shell has colours before any wallpaper is set
    [[ -f "$HOME/.cache/current_theme" ]] || printf 'matugen' > "$HOME/.cache/current_theme"
    if [[ ! -s "$HOME/.cache/quickshell/matugen.json" ]]; then
        cp "$SRC/support/lucid/themes/nord/quickshell.json" "$HOME/.cache/quickshell/matugen.json"
        say "  seeded a starter palette (nord) — pick a theme in Settings to change it"
    fi
else
    step "Skipping the theming layer (--no-theming)"
    say "  the theme picker and wallpaper strip will not work until it is installed"
fi

# -------------------------------------------------------------- wallpapers

# one folder per theme, which is where the wallpaper strip looks:
# ~/Pictures/wallpapers/<theme>. yours are never overwritten or removed
PICTURES_DIR="$HOME/Pictures/wallpapers"
if [[ $WITH_WALLPAPERS -eq 1 && -d "$SRC/wallpapers" ]]; then
    step "Installing the wallpapers"

    WALL_NEW=0
    WALL_KEPT=0
    for dir in "$SRC"/wallpapers/*/; do
        [[ -d "$dir" ]] || continue
        theme="$(basename "$dir")"
        mkdir -p "$PICTURES_DIR/$theme"
        for pic in "$dir"*; do
            [[ -f "$pic" ]] || continue
            dest="$PICTURES_DIR/$theme/$(basename "$pic")"
            if [[ -e "$dest" ]]; then
                WALL_KEPT=$((WALL_KEPT + 1))
            else
                cp "$pic" "$dest"
                WALL_NEW=$((WALL_NEW + 1))
            fi
        done
    done

    say "  $WALL_NEW wallpapers -> $PICTURES_DIR"
    [[ $WALL_KEPT -gt 0 ]] && say "  ${dim}$WALL_KEPT were already there, left as they are${r}"
    say "  ${dim}the strip shows the folder for the theme you are on; SUPER+B opens it${r}"
elif [[ $WITH_WALLPAPERS -eq 0 ]]; then
    step "Skipping the wallpapers (--no-wallpapers)"
    say "  ${dim}$PICTURES_DIR is left alone; the strip shows whatever is in it${r}"
fi

# ---------------------------------------------------------------------- done

step "Done"

# a running instance is still on the old files, so offer the restart that
# actually puts the new version on screen.
# the path alone is not enough: with nothing running, `qs list` says
# "No running instances for <path>", which the path matches. the field only
# a real instance has is what to look for.
# no grep -q here: it would close the pipe, and pipefail would then read the
# producer's SIGPIPE as "not running". the in-shell updater (LUCID_UPDATER)
# asks about the restart itself, once the install has finished
if [[ -z "${LUCID_UPDATER:-}" ]] && qs list 2>/dev/null | grep -F "Config path: $SHELL_DIR/shell.qml" >/dev/null; then
    if ask "  Lucid is running on the old files. Restart it now?"; then
        qs kill -p "$SHELL_DIR" 2>/dev/null || true
        sleep 1
        # through the launcher, as autostart does, so the new instance gets
        # the same render backend and driver choice as one started at login
        if [[ -x "$LUCID_DIR/launch-shell.sh" ]]; then
            (setsid "$LUCID_DIR/launch-shell.sh" -d >/dev/null 2>&1 &) || true
        else
            (setsid qs -d >/dev/null 2>&1 &) || true
        fi
        say "  restarted"
    fi
fi

cat <<EOF

  ${b}Lucid $VERSION${r} is installed.

  Start it:      ${b}qs${r}
  Settings:      ${b}qs ipc call -- settings open${r}

EOF

if [[ $HYPR_LUA_INSTALLED -eq 1 ]]; then
    cat <<EOF
  Hyprland is configured: modules/binds.lua carries the binds, the window
  and layer rules are in place, and modules/autostart.lua starts the shell
  on login.

    SUPER            launcher        SUPER+W      workspaces
    SUPER+S          settings        SUPER+T      theme picker
    SUPER+period     emoji           SUPER+B      wallpaper
    SUPER+P          commands        SUPER+E      files
    SUPER+C          close window    SUPER+V      float
    SUPER+D / Print  screenshot      F10          lock
    SUPER+R          reload hypr     F9           terminal
    SUPER+Escape     session         CTRL+ALT+TAB switch windows

  Special workspaces slide over whatever you are on; the same keys hide them:

    SUPER+SHIFT+S    scratchpad      SUPER+ALT+S  stash a window
    SUPER+SHIFT+M    music           SUPER+SHIFT+D  comms
    SUPER+SHIFT+R    to-do           CTRL+SHIFT+ESC system monitor

  ${b}The new binds are not live yet${r} — run ${b}hyprctl reload${r}, or log out
  and back in to pick up the autostart too.

EOF
else
    cat <<EOF
  Autostart:     add ${b}exec-once = qs${r} to your Hyprland config

  Suggested Hyprland binds:

    bind = SUPER, SPACE,  exec, qs ipc call -- launcher toggle
    bind = SUPER, E,      exec, qs ipc call -- moji toggle
    bind = SUPER, L,      exec, qs ipc call -- lock lock
    bind = SUPER, S,      exec, qs ipc call -- snap toggle
    bind = SUPER, comma,  exec, qs ipc call -- settings open

  Keep the double dash: it is required whenever a call takes an argument.
  Or run ${b}./install.sh --with-hypr${r} to take Lucid's config wholesale.

EOF
fi

# --- Compile the colorpicker ---
if [[ -f "$SRC/colorpicker/Makefile" ]]; then
    step "Building the pure C colorpicker"
    if make -C "$SRC/colorpicker" \
       && mkdir -p "$HOME/.local/bin" \
       && cp "$SRC/colorpicker/colorpicker" "$HOME/.local/bin/colorpicker"; then
        say "  colorpicker -> ~/.local/bin/colorpicker"
    else
        DEPS_OK=0
        warn "could not build the colorpicker (needs clang, make, wayland-devel, wayland-protocols-devel)"
    fi
fi

if [[ $DEPS_OK -eq 0 ]]; then
    warn "some dependencies are missing — the shell is installed, but the"
    warn "features they back will not work until you install them."
fi
