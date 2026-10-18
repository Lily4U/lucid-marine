<div align="center">

<img src="assets/logo.svg" width="104" alt="Lucid">

# Lucid-marine

**A Material 3 Expressive desktop shell for Hyprland, built on [Quickshell](https://quickshell.org) and adapted for Ultramarine Linux.**

A bar, a dock that morphs into a launcher, desktop widgets, a lock screen,
an emoji picker, a screenshot tool, a custom C color picker and a settings app — themed together from
your wallpaper.

<p>
  <a href="https://github.com/Lily4U/lucid-marine/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/Lily4U/lucid-marine?style=for-the-badge&label=LAST%20COMMIT&labelColor=14100E&color=FF7F50"></a>
  <a href="https://github.com/Lily4U/lucid-marine/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Lily4U/lucid-marine?style=for-the-badge&label=STARS&labelColor=14100E&color=FFC46B"></a>
  <a href="https://github.com/Lily4U/lucid-marine/releases"><img alt="Release" src="https://img.shields.io/github/v/tag/Lily4U/lucid-marine?style=for-the-badge&label=RELEASE&labelColor=14100E&color=FFAB91"></a>
  <img alt="Repo size" src="https://img.shields.io/github/repo-size/Lily4U/lucid-marine?style=for-the-badge&label=REPO%20SIZE&labelColor=14100E&color=E8A87C">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/LICENSE-MIT-80CBC4?style=for-the-badge&labelColor=14100E"></a>
</p>

<p>
  <img alt="Version" src="https://img.shields.io/badge/VERSION-v1.20.1-FF7F50?style=for-the-badge&labelColor=14100E">
  <img alt="Platform" src="https://img.shields.io/badge/PLATFORM-ULTRAMARINE%20LINUX-FFAB91?style=for-the-badge&logo=fedora&logoColor=FFAB91&labelColor=14100E">
  <img alt="Compositor" src="https://img.shields.io/badge/COMPOSITOR-HYPRLAND-80CBC4?style=for-the-badge&labelColor=14100E">
  <a href="https://quickshell.org"><img alt="Built on Quickshell" src="https://img.shields.io/badge/BUILT%20ON-QUICKSHELL-FFC46B?style=for-the-badge&labelColor=14100E"></a>
</p>

<img src="assets/desktop.webp" alt="The Lucid desktop: the bar along the top, calendar and weather widgets on the left, the clock and what is playing on the right, and the dock along the bottom">

</div>

---

> **v1.20.1.** Lucid-marine fork with icons on the desktop, bar modules that join into
> one island, live wallpapers and four ways to pick one, five new widgets, files
> over Bluetooth, a custom low-level C color picker and the fix for Steam opening and closing in a loop. Lucid 2 itself redrew
> every surface in Material You Expressive, made the clock an app and gave the
> launcher, the bar and the settings room to be shaped. It's what I use daily. The shell shows the highlights once after
> you update; everything that landed in it, and in every version before it, is
> in the [changelog](CHANGELOG.md). Rough edges are still possible and bug
> reports are welcome.

> **To hear about new versions**, press **Watch → Custom → Releases** at the top
> of this page. Lucid also checks for itself: once a day it asks GitHub for the
> newest release and says so once, in a notification. See
> [Updating](#updating).

## Install

Lucid-marine installs to `~/.config/quickshell` and targets **Ultramarine Linux / Fedora** with
**Hyprland**. Three commands:

```sh
git clone [https://github.com/Lily4U/lucid-marine.git](https://github.com/Lily4U/lucid-marine.git) lucid
cd lucid
./install.sh

```

That's it — the installer does the rest:

1. **Checks your system** — refuses to run anywhere it can't finish the job,
rather than leaving you half-installed.
2. **Installs dependencies** — uses `dnf` to fetch system packages, enabling COPRs and RPM Fusion when needed. It lists everything and asks before touching
your system. Say no and it carries on, telling you which features won't work.
This includes the apps Lucid ships pinned to the dock as Flatpaks. `--no-apps` skips them.
3. **Compiles the custom C color picker** — builds the lightweight native utility using `make` and `clang`/`gcc` and places it in your PATH (`~/.local/bin/colorpicker`).
4. **Copies the shell** to `~/.config/quickshell`, moving any existing config to
`~/.config/quickshell.backup-<timestamp>` first.
5. **Sets up Hyprland** — `hyprland.lua` and its modules: the keybinds, the
window and layer rules, blur, animations, and an autostart that launches the
shell on login. If you already have a config it is backed up and you are
asked first; `--no-hypr` keeps yours untouched.
6. **Sets up theming** — the palettes, the wallpaper hook, and the matugen
template. An existing `matugen/config.toml` is appended to, never replaced.
7. **Applies the look** — kitty's colours, its opacity and its fish shell, the
starship prompt (wired into `.bashrc`, `.zshrc` and `config.fish`), a
fastfetch config that wears the theme (only where you have none), the
VSCode/VSCodium Matugen theme, and the GTK theme: `adw-gtk3-dark` with the
FairyWren icons, written to `gsettings` and to both `gtk-3.0` and `gtk-4.0`
`settings.ini`. A `kitty.conf` or prompt an earlier release installed, and
nobody has changed since, is swapped for the current one, with a backup.
`--no-look` skips this.
8. **Pins the dock** — reads your installed `.desktop` files and pins the real
apps, so the dock is never a row of blank letter tiles.
9. **Offers to restart** a running instance onto the new files.

Then reload Hyprland so the new binds and rules take effect:

```sh
hyprctl reload

```

Or log out and back in, which picks up the autostart too. To start the shell by
hand in the meantime, run `qs`.

Set a wallpaper from **Settings → General** on first run — that's what generates
your colour palette.

### Updating

Pull and re-run. Your settings, pinned apps, reminders, Shazam history and API
keys are carried forward into the new install:

```sh
git pull
./install.sh

```

Lucid tells you when there is something to pull. Once a day it asks GitHub's
public API for the newest release, and when that is newer than the version you
installed it posts one notification — once per version, never again for the same
one. The request is a plain `curl` for
`api.github.com/repos/Lily4U/lucid-marine/releases/latest` and carries nothing about
you or your machine; **Settings → About** shows what it found and turns it off.

```sh
qs ipc call updates status   # what it knows
qs ipc call updates check    # ask now

```

### Older versions

`v0.57 beta` is a tag, so it stays exactly where it is:

```sh
git clone --branch v0.57 [https://github.com/Lily4U/lucid-marine.git](https://github.com/Lily4U/lucid-marine.git)

```

### Installer options

| Flag | What it does |
| --- | --- |
| `--no-theming` | Skips the palette layer. Leaves `~/.config/lucid` and `~/.config/matugen` alone — use this if you already have a matugen setup you don't want touched. |
| `--no-hypr` | Keeps your Hyprland config. Lucid's binds, window rules, blur and autostart are not installed. |
| `--no-apps` | Doesn't install the apps the dock ships pinned (Zen, VSCodium, Spotify, Vesktop, Files, Steam, Proton VPN). The dock then pins whatever equivalents you already have. |
| `--no-look` | Doesn't touch `kitty.conf`, `starship.toml`, the fastfetch config, your shell rc files, VSCode settings, or the GTK theme and icons. |
| `--no-wallpapers` | Doesn't copy the bundled wallpapers into `~/Pictures/wallpapers`. They are ~180 MB, so this is worth passing on a small disk or a slow link. |
| `--with-hypr` | Reinstalls Lucid's Hyprland config even when one is already in place. |
| `--skip-deps` | Never installs packages, just reports what's missing. |
| `-y`, `--yes` | Accept every prompt. |

Re-running the installer is how you update. It moves your existing
`~/.config/quickshell` to `~/.config/quickshell.backup-<timestamp>`, installs
the new shell files, then carries your settings, pinned apps, reminders,
Shazam history and API keys forward into it. Nothing is deleted, and the
backup stays where it is until you remove it.

## Keybinds

The installer ships these in `~/.config/hypr/modules/binds.lua`, along with the
window rules, blur, animations and the autostart. Run `hyprctl reload` after
installing to pick them up.

| Key | Does |
| --- | --- |
| `SUPER` (tap) | Launcher |
| `SUPER` + `P` | Command palette |
| `SUPER` + `T` | Theme picker |
| `SUPER` + `B` | Wallpaper picker |
| `SUPER` + `SHIFT` + `V` | Clipboard history |
| `SUPER` + `S` | Settings |
| `SUPER` + `.` | Emoji picker |
| `SUPER` + `K` | On-screen keyboard |
| `SUPER` + `W` | Workspace overview (also: three-finger swipe) |
| `CTRL` + `ALT` + `TAB` | Window switcher — every window on every workspace, newest first (`+SHIFT` steps back) |
| `SUPER` + `Esc` | Session screen — lock, sleep, log out, restart, shut down |
| `SUPER` + `D` / `Print` | Region screenshot |
| `SUPER` + `Print` | Full screenshot |
| `SUPER` + `SHIFT` + `T` | Copy text from a region (OCR) |
| `SUPER` + `SHIFT` + `C` | Pick a colour off the screen (using custom C colorpicker) |
| `SUPER` + `E` | Files |
| `SUPER` + `C` | Close window |
| `SUPER` + `V` | Toggle float |
| `SUPER` + `1`–`0` | Switch workspace (`+SHIFT` moves the window) |
| `SUPER` + `SHIFT` + `S` | Scratchpad, or put away whichever special workspace is up |
| `SUPER` + `ALT` + `S` | Stash the focused window in the scratchpad, or send it back |
| `SUPER` + `SHIFT` + `M` | Music workspace |
| `SUPER` + `SHIFT` + `D` | Comms workspace |
| `SUPER` + `SHIFT` + `R` | To-do workspace |
| `CTRL` + `SHIFT` + `Esc` | System monitor workspace |
| `SUPER` + arrows | Move focus |
| `SUPER` + `R` | Reload Hyprland |
| `F1`–`F6` | Volume, mic, brightness |
| `F9` | Terminal |
| `F10` | Lock |
| `F12` | Calculator |

Ran with `--no-hypr`, or want to bind things yourself? Everything is exposed
over IPC:

```lua
hl.bind("SUPER + SPACE",   hl.dsp.exec_cmd("qs ipc call -- launcher toggle"))
hl.bind("SUPER + E",       hl.dsp.exec_cmd("qs ipc call -- moji toggle"))
hl.bind("SUPER + L",       hl.dsp.exec_cmd("qs ipc call -- lock lock"))
hl.bind("SUPER + Escape",  hl.dsp.exec_cmd("qs ipc call -- session toggle"))
hl.bind("SUPER + S",       hl.dsp.exec_cmd("qs ipc call -- snap toggle"))
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("qs ipc call -- snap text"))
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("qs ipc call -- snap color"))
hl.bind("SUPER + comma",   hl.dsp.exec_cmd("qs ipc call -- settings open"))

```

Special workspaces are Hyprland Lua rather than IPC. On a Lua config of your
own, copy `support/hypr/modules/specials.lua` into `~/.config/hypr/modules/`
and bind its functions the way Lucid's `modules/binds.lua` does:

```lua
local specials = require("modules.specials")
hl.bind("SUPER + SHIFT + M", specials.toggle("music"))

```

Keep the `--`. It is only strictly required when the call takes an argument —
`qs ipc call settings show bar` fails with *"The following argument was not
expected: bar"*, while `qs ipc call -- settings show bar` works. It is harmless
on argument-free calls, so using it everywhere saves you the surprise.

## Requirements

Ultramarine Linux / Fedora and Hyprland. The installer handles all of this, listed here so
you know what's being pulled in.

**Required** — the shell won't start without these:

`quickshell` · `qt6-5compat` · `qt6-declarative` · `qt6-multimedia` · `clang` · `make` · `wayland-devel` · `wayland-protocols-devel`

**Per feature** — a missing one breaks only its own feature:

| Package | Backs |
| --- | --- |
| `matugen`, `jq` | Wallpaper-derived colours, theme switching |
| `git` | Importing a theme from a scheme repo on Settings → Theme |
| `awww` | Setting the wallpaper |
| `python-pywal` | The Pywal theme |
| `NetworkManager` | Wi-Fi panel |
| `qrencode` | The QR code that shares a saved Wi-Fi network |
| `bluez`, `bluez-utils` | Bluetooth panel and settings |
| `bluez-obexd`, `python3-gobject` | Sending and receiving files over Bluetooth |
| `kdeconnect`, `python3-gobject` | The KDE Connect page |
| `fuse-sshfs` | Browsing a phone's files |
| `pulseaudio-utils`, `wireplumber` | Volume, audio devices, and playing Lucid's sounds |
| `inotify-tools` | The camera on/off toast and sound |
| `smartmontools`, `udisks2` | Storage drive health and mounting |
| `ffmpegthumbnailer`, `gvfs` | Desktop icons thumbnails and drives |
| `pipewire-utils`, `sound-theme-freedesktop` | Sound page Left/Right test |
| `brightnessctl`, `upower` | Brightness, battery |
| `hyprsunset` | Night light |
| `hypridle` | Idle page / lock / suspend |
| `grim`, `wf-recorder`, `ffmpeg-free`, `ImageMagick` | Screenshots and recording |
| `tesseract`, `tesseract-langpack-eng` | Text mode's OCR |
| `python3-pillow`, `python3-numpy`, `python3-fonttools` | Emoji in copied text |
| `wl-clipboard`, `wtype` | Emoji and GIF pasting |
| `cliphist` | Clipboard history |
| `cava` | Audio visualisers |
| `songrec` | Song identification |
| `curl` | Weather, location lookup and GIF search |
| `polkit` | Administrator prompts |
| `accountsservice` | Users and Accounts page |
| `libnotify` | Notification actions |
| `swappy` | Screenshot markup |
| **`colorpicker`** (custom C binary) | Fast native screen color picking (replaces hyprpicker dependency) |
| `xdg-utils` | Opening links and files |
| `librsvg`, `gtk-update-icon-cache` | Pointer shadow and icon cache |
| `google-noto-color-emoji-fonts` | Emoji rendering |

## Uninstall

```sh
./uninstall.sh

```

Moves `~/.config/quickshell` aside rather than deleting it, so your settings
survive. Packages installed by `install.sh` are left alone.

## Contributing

Issues and PRs welcome on the `lucid-marine` fork.

## License

MIT — see [LICENSE](https://www.google.com/search?q=LICENSE).

Built on [Quickshell](https://quickshell.org). Colour generation by
[matugen](https://github.com/InioX/matugen). Design follows
[Material 3 Expressive](https://m3.material.io).

```
