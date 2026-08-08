<div align="center">

# ❄️ nixos-dotfiles

**A fully-declarative NixOS flake for `nixos-btw` — a [niri](https://github.com/YaLTeR/niri) + [COSMIC](https://system76.com/cosmic) Wayland rice in OLED black, white, and neon green (`#00ff41`).**

Ricing, a local agentic voice assistant, degoogled daily drivers, gaming, video editing, and privacy tooling — all reproducible from one `./install.sh`.

</div>

---

## 🚀 Install

On a fresh NixOS machine:

```sh
git clone https://github.com/r3dg0d/nixos-dotfiles
cd nixos-dotfiles
./install.sh
```

That is the whole thing. The script does not configure the desktop itself —
everything is declared in the flake — it just does what a declarative
configuration cannot do for itself:

1. checks this really is NixOS, that `nix`/`git` are present, that flakes can be
   used, and that there is enough room on `/nix`
2. picks the flake host (see [Hosts](#-hosts))
3. makes sure `hosts/<host>/hardware-configuration.nix` describes **this**
   machine — generating one if absent, and refusing to silently overwrite one
   that already matches (see [Portability](#-portability))
4. generates `/etc/searxng.env`, the one secret that is deliberately not in git
5. `nixos-rebuild build`, and only if that succeeds, `nixos-rebuild switch`
6. offers to download SIVA's speech models
7. prints a status report of what works and what is waiting on a reboot

```
  NixOS configuration ....... OK
  Flake ..................... OK
  NVIDIA .................... OK (580.95.05)
  PipeWire .................. OK
  Niri ...................... OK (niri.desktop)
  COSMIC .................... OK (cosmic.desktop)
  SDDM ...................... OK (running)
  sddm-ascii-city ........... OK (theme installed + selected)
  Waybar .................... OK
  Ghostty ................... OK
  Wallpaper ................. OK (deployed from the repo)
  llama-server .............. OK (active)
  SIVA ...................... OK (active)
  SIVA wake word ............ OK (active)
  SIVA-Voicefetch ........... OK (active)
  SIVA-Type ................. OK (active)
```

Useful flags:

| Flag | Effect |
| --- | --- |
| `--host NAME` | Install a specific host from the flake |
| `--build-only` | Prove it builds; change nothing |
| `--regenerate-hardware` | Replace `hardware-configuration.nix` (old one is backed up) |
| `--fetch-assets` / `--no-fetch-assets` | Decide the model download up front |
| `-y`, `--yes` | Unattended; take the safe default for every prompt |

### Prerequisites

- NixOS (26.05 or newer). The script refuses to run anywhere else.
- An EFI machine — `hosts/nixos-btw` uses systemd-boot.
- Roughly 40 GiB free in `/nix` for a first build, plus ~18 GiB for SIVA's LLM
  weights if you want the assistant.
- Nothing else. Flakes do not have to be enabled beforehand; the installer
  passes the experimental features per-command until the new configuration
  makes them permanent.

## 🏠 Hosts

```
nixos-btw   i9-14900K · RTX 4090 · Focusrite Scarlett 2i2 · dual 3440×1440
```

`install.sh` picks the host by `--host`, then by matching `$(hostname)`, then —
if only one exists — that one, and otherwise asks. Adding a machine means
adding a directory under `hosts/` and one entry to the `hosts` attrset in
[`flake.nix`](flake.nix); the installer discovers it from there.

---

## 🖥️ The desktop

![Desktop](assets/desktop.png)

A tiling niri session on dual 3440×1440 ultrawides: an ASCII-art wallpaper, a
slim [waybar](https://github.com/Alexays/Waybar), and a
[quickshell](https://quickshell.org/) layer for widgets and overlays.
Everything is themed to the same OLED-black / white / neon-green (`#00ff41`)
palette — down to the zsh syntax highlighting, the
[starship](https://starship.rs/) prompt, and the Ghostty colour scheme.

### The gradient sweep

Decoration is one idea applied everywhere: a **white → neon-green gradient**
mapped across the *whole view* rather than re-run per element.

niri draws it as the focus ring, with `relative-to="workspace-view"`, so each
focused window shows the slice of the sweep it happens to sit under — white
over on the left of the view, full green by the right. A row of windows reads
as one continuous run of light instead of several identical outlines, and
moving a column re-cuts its colour. The waybar groups take the same sweep
left-to-right, and the quickshell panels carry it as their edge.

The green *bloom* it replaced is gone. A glow was doing the same job as the
edge it sat on and smeared it on true black; window shadows are now near-black
depth instead, invisible over the OLED background by design and earning their
keep only where something lighter is behind them.

**COSMIC** is installed alongside niri rather than instead of it. Both register
a Wayland session, and you choose between them at the login screen.

GTK apps follow the same dark palette: `adw-gtk3-dark` with `Papirus-Dark`
icons. GTK4/libadwaita apps — Nautilus above all — ignore `gtk.theme` and read
the XDG colour-scheme preference instead, so `color-scheme = prefer-dark` is
set in dconf as well; without it Nautilus stays light. niri has no desktop
environment to answer the Settings portal, so that is routed to the GTK
backend ([`modules/nixos/desktop/portals.nix`](modules/nixos/desktop/portals.nix))
to get the preference out to Flatpaks and portal-aware apps.

Default applications ([`modules/home/desktop.nix`](modules/home/desktop.nix)):
**Helium** for web, **mpv** for audio and video, **imv** for images,
**COSMIC Edit** for text. Every mime type is enumerated explicitly — declaring
an association in a `.desktop` is not the same as being the default for it.

## 🔐 SDDM login theme — `sddm-ascii-city`

![SDDM theme](assets/sddm.png)

A custom SDDM theme, packaged as a Nix derivation in
[`pkgs/sddm-ascii-city.nix`](pkgs/sddm-ascii-city.nix) from the sources in
[`sddm-ascii-city/`](sddm-ascii-city) (kept byte-identical to the standalone
[r3dg0d/sddm-ascii-city](https://github.com/r3dg0d/sddm-ascii-city) repo):
animated ASCII rain falling over a procedural ASCII city skyline, a grayscaled
avatar, and a minimalist ASCII login box.

A `systemd` service plays login music straight to the Scarlett 2i2 over ALSA
while the greeter is on screen (the QML greeter has no PipeWire to play
through), and stops the instant a session starts.

### Choosing Niri or COSMIC at the greeter

The login box has a third field:

```
|   user > [ r3dg0d                  ]|
|   pass > [ ********                ]|
|   desk > [ < Niri          2/2  > ]|
```

| Input | Effect |
| --- | --- |
| `←` / `→` | Previous / next desktop — from *any* field, so you never leave the password box |
| `Tab` | `user` → `pass` → `desk` → `user` |
| `↑` / `↓` | Previous / next desktop, when `desk` has focus |
| Click `<` / `>` / the name | Step / advance |
| Scroll over the field | Previous / next |
| `Enter` | Log in with the shown desktop |

**Nothing about the list is hardcoded.** It is SDDM's own `sessionModel`, so it
shows exactly the sessions SDDM found — install a third desktop and it appears
by itself. `sddm.login()` gets the model index, so the highlighted session is
the one that actually starts.

Two environment variables in
[`modules/nixos/desktop/sddm.nix`](modules/nixos/desktop/sddm.nix) make this
work reliably on NixOS, and both are commented at length there:

- `QML_XHR_ALLOW_FILE_READ=1` — lets the theme re-resolve the remembered
  session from `/var/lib/sddm/state.conf` by *basename*. SDDM stores an
  absolute store path, which every rebuild invalidates; without this you
  silently get whichever session sorts first (COSMIC) after each rebuild.
- `QML_DISABLE_DISK_CACHE=1` — Qt keys its compiled-QML cache on path + mtime,
  and every store file has `mtime=1`, so the greeter would otherwise keep
  replaying the QML it compiled the first time you installed the theme.

Test theme changes without logging out:

```sh
nix shell nixpkgs#qt6.qtbase nixpkgs#qt6.qtdeclarative \
  -c ./sddm-ascii-city/test/run-harness.sh
```

(`sddm-greeter-qt6 --test-mode` swallows QML errors, so a broken theme looks
identical to a working one. The harness stubs the four context properties SDDM
injects and asserts on what the selector actually resolved to.)

## 🖼️ `fetch` — animated 3D system info

![fetch](assets/fetch.png)

The terminal is [Ghostty](https://ghostty.org/) — GPU-accelerated, with custom
shader support — running [areofyl/fetch](https://github.com/areofyl/fetch), a
neofetch-style tool that spins a **3D ASCII distro logo** next to the system
info. Pulled in as the `areofyl-fetch` flake input. Ghostty is `$TERMINAL` and
`Mod+Return`; alacritty stays on `Mod+Shift+Return` as a fallback.

> The screenshot was taken in ratty, which Ghostty replaced.
> _TODO: retake it._

## 🧰 Waybar

![Waybar](assets/waybar.png)

Workspaces and focused-window title on the left. In the center, an MPD player
widget — album art, track, a cava visualiser, and previous / play-pause / next /
loop transport buttons — next to the clock. On the right, a status cluster:
weather, temperatures, volume, network, CPU and memory, a
[system-update indicator](#the-waybar-widget), the Mirror toggle, and a power
button that opens the quickshell power menu.

The three groups are edged in successive slices of the
[gradient sweep](#the-gradient-sweep) — white on the left, full `#00ff41` on
the right — so the bar continues the line niri draws around windows.

**Scrolling the volume module** raises the same OSD the `Fn` keys do: the
wheel is wired to `fnkey volume-up` / `fnkey volume-down`, and middle-click to
`fnkey mute`. waybar's pulseaudio module checks for an `on-scroll-*` command
and delegates to it *instead of* its own volume handling, so a notch is still
one 5% step — not two.

## 🪟 Quickshell widgets

![Quickshell power menu](assets/quickshell.png)

Hand-written [quickshell](https://quickshell.org/) components in
[`config/quickshell/`](config/quickshell), all in the same neon-green theme and
driven by IPC (`qs ipc call <target> toggle`):

- **OSD** — the Fn-key on-screen display; see [the Fn key row](#-the-fn-key-row)
- **Web search** — a SearXNG prompt on `Fn+F4`; see [the Fn key row](#-the-fn-key-row)
- **Clipboard manager** — `cliphist` history with fuzzy search (`Mod+C`)
- **Wi-Fi picker** — `nmcli` network menu (waybar network click)
- **Power menu** — logout / restart / shutdown / sleep
- **Mirror** — a floating webcam window
- **SIVA overlays** — the voice-assistant status panel, live agentic screen
  stream, dictation overlay, voice-model browser, and enrollment wizard

> Quickshell does **not** hot-reload this config the way niri does. After
> editing anything under `config/quickshell/`, restart it — `pkill quickshell`
> then `qs -d`, or just log out and back in — or the change will not appear.

---

## ⌨️ The Fn key row

`Fn` + `F1…F12` is wired end to end: every key does its job *and* draws an
on-screen display for it.

| Key | Action | Backend |
| --- | --- | --- |
| `F1` / `F2` | Display brightness − / + | DDC/CI over I²C ([below](#display-brightness-on-desktop-monitors)) |
| `F3` | Toggle the niri overview | `niri msg action toggle-overview` |
| `F4` | Web search prompt | quickshell → SearXNG on `localhost:8888` |
| `F5` | Microphone mute switch | `wpctl` on `@DEFAULT_AUDIO_SOURCE@` |
| `F6` | Webcam mirror | the quickshell Mirror widget |
| `F7` / `F8` / `F9` | Previous / play-pause / next | `playerctl` (MPRIS) |
| `F10` | Mute output | `wpctl` on `@DEFAULT_AUDIO_SINK@` |
| `F11` / `F12` | Volume − / + | `wpctl`, capped at 100% |

`Mod+O` and `Mod+S` are keyboard-independent aliases for the overview and the
search prompt. Scrolling the waybar volume module and middle-clicking it go
through the same `fnkey` actions, so they raise the same OSD.

### How it fits together

One dispatcher, [`fnkey`](pkgs/fnkeys), sits behind every binding in
[`config/niri/config.kdl`](config/niri/config.kdl). It performs the action,
reads back the state the system actually landed in, and hands that to the
quickshell OSD as a small JSON payload:

```sh
fnkey volume-up
qs ipc call osd notify '{"kind":"bar","icon":"󰕾","label":"Volume","value":63}'
```

Two reasons it is built this way rather than binding `wpctl` to the keys
directly. The OSD can never disagree with reality, because the number it shows
was read *after* the change — not predicted before it. And the IPC call is
best-effort: if quickshell is not running, the key still works, it just does so
quietly.

The OSD ([`config/quickshell/Osd.qml`](config/quickshell/Osd.qml)) draws on
every monitor, in two shapes — a segmented meter for brightness and volume, a
toast with one detail line for the switches and the transport. 75% black glass,
neon-green glow, corner brackets, scanlines; a muted channel turns red.

The bindings use the standard `XF86*` keysyms the keyboard's Fn layer emits, so
they do not collide with the bare `F7`/`F8`/`F9` SIVA binds. If a key does
nothing, find out what it really sends with `wev` and rename the bind — niri
hot-reloads the file, so it is a one-line fix.

### Display brightness on desktop monitors

Two 3440×1440 ultrawides have no `/sys/class/backlight`. Their panel brightness
is a **DDC/CI** register the GPU writes over the display cable's I²C lines, so
`brightnessctl` has nothing to talk to and the keys are dead out of the box.

[`monitor-brightness`](pkgs/monitor-brightness) drives it through `ddcutil`
(VCP feature `0x10`), with the two things that make it usable on a keypress:

- **Cached bus discovery.** `ddcutil detect` costs about a second, so the I²C
  bus numbers are probed once into `$XDG_RUNTIME_DIR` and every later call is a
  direct `--bus N setvcp`.
- **Coalesced writes.** A held key produces far more events than a panel can
  answer over I²C. The level is updated instantly in a state file — which is
  what the OSD reads — while a single background applier drains it towards the
  hardware, collapsing a burst of presses into the few writes the monitors can
  actually take.

Access comes from `hardware.i2c.enable` plus the `i2c` group, both set in
[`modules/nixos/desktop/fnkeys.nix`](modules/nixos/desktop/fnkeys.nix). **The
group membership only lands on your next login**, so brightness stays dead
until you log out and back in after the first rebuild.

```sh
monitor-brightness status   # which backend, which buses, what level
monitor-brightness detect   # re-probe after replugging a cable
monitor-brightness set 60
ddcutil detect              # the raw view, when the wrapper finds nothing
```

If no DDC-capable display answers, it falls back to `brightnessctl` on an
internal backlight rather than failing, so the same keys work on a laptop.

### The search prompt

`Fn+F4` (or `Mod+S`) opens
[`WebSearch.qml`](config/quickshell/WebSearch.qml): type, press Enter, and the
query opens in the local **SearXNG** instance —
`http://localhost:8888/search?q=…`, the same one
[`services.searx`](modules/nixos/services.nix) already runs for the browser
omnibox and for SIVA's `web_search` tool. Nothing reaches a third-party search
box on the way out. SearXNG's `!bangs` are passed through untouched, and the
recent-query list is in memory only — it dies with the session.

```sh
qs ipc call websearch toggle          # the prompt
qs ipc call websearch query "ddcutil" # search without the UI
```

---

## 💤 Screensaver

Five minutes with no keyboard or pointer input and the NixOS logo takes over
both monitors, animated with
[terminaltexteffects](https://github.com/ChrisBuilds/terminaltexteffects).
The first key or mouse movement puts the desktop back.

The logo is `nixoslogo-ascii-art.txt`, trimmed of its blank border to 99×47
characters and installed into the store, so the screensaver does not depend on
this checkout being present.

```sh
nixos-screensaver start | stop | toggle | status   # drive it by hand
systemctl --user status screensaver                # the idle timer
```

### How it fits together

**swayidle** is the timer, in a user service
([`modules/nixos/desktop/screensaver.nix`](modules/nixos/desktop/screensaver.nix)).
It speaks `ext_idle_notifier_v1`, so "no input" means what the compositor says
it means rather than something polled — and two useful behaviours come free
with that protocol:

- Apps holding an idle inhibitor suppress the timeout, so a film is not
  interrupted. This is why swayidle is used rather than hypridle, which can be
  told to ignore inhibitors.
- The `resume` event fires on the input that wakes the session, so the
  keypress that dismisses the screensaver is consumed by it rather than
  landing in whatever window was underneath.

Worth knowing before wondering why it never appeared: the inhibitor is
broader than "video". Chromium-based browsers take the wake lock for **any**
media playback, audio included — a tab quietly playing music holds the
screensaver off exactly as a fullscreen film does. `wpctl status` shows which
streams are `[active]`.

**[`nixos-screensaver`](pkgs/nixos-screensaver)** puts it on screen: one
fullscreen terminal per connected monitor, each running an effect loop that
picks at random from ~30 tte effects and holds the assembled logo for a beat
before dissolving into the next. Every effect is passed
`--final-gradient-stops 00ff41 39ff14 00ff41`, so the animation stays on the
rice's palette whichever one comes up. (`synthgrid` is the one effect excluded
for that reason — it is the only one that does not take the flag.)

Two details in there are load-bearing and non-obvious:

- **It uses alacritty, not the ghostty everything else uses.** ghostty
  defaults to `gtk-single-instance = detect`, so launching it while one is
  already running hands the request to the existing process instead of
  starting a new one — and the second monitor silently never gets a window.
  alacritty forks a fresh process every time.
- **Font size is the only thing that sizes the logo,** because it is a fixed
  block of characters and nothing scales it. The failure is one-sided: too
  small merely looks small, but too large leaves the terminal with fewer than
  47 rows and tte crops the logo rather than shrinking it. The default 16
  gives about 55 rows on a 1440px panel; `services.screensaver.fontSize`
  lowers it for shorter monitors.

niri fullscreens the terminals through a window rule keyed on the
`nixos-screensaver` app-id — an app-id rather than a title, because a title
belongs to whatever is running in the terminal and can change underneath you.

```nix
services.screensaver.timeout = 300;   # seconds of no input
services.screensaver.fontSize = 16;
services.screensaver.enable = false;  # turn the whole thing off
```

---

## 🎙️ SIVA — a local agentic voice assistant

![SIVA overlay](assets/siva.png)

[**SIVA**](https://github.com/r3dg0d/siva) (Super Intelligent Voice Assistant)
is a fully-local, agentic desktop assistant. Press **F8**, talk, and it sees the
screen (vision via llama.cpp), reasons out loud in the overlay, drives the
desktop — cursor, clicks, typing, window management — then speaks its answer. It
has **durable cross-session memory** via
[MemPalace](https://github.com/MemPalace/mempalace) (what `programs.nix-ld` is
enabled for) and can search the web through the local SearXNG. No cloud, no API
keys.

| Key | Tool | What it does |
| --- | --- | --- |
| **F7** | [siva-voicefetch](https://github.com/r3dg0d/siva-voicefetch) | Browse/download RVC voice models for TTS |
| **F8** | [siva](https://github.com/r3dg0d/siva) | Push-to-talk agentic voice assistant |
| **F9** | [siva-type](https://github.com/r3dg0d/siva-type) | AI dictation — speak to type anywhere |
| *"Siva"* | siva-wake | Wake word — fires F8 hands-free |

### How it is packaged

The three upstream repos are **vendored** into
[`pkgs/siva/src`](pkgs/siva), [`pkgs/siva-type/src`](pkgs/siva-type) and
[`pkgs/siva-voicefetch/src`](pkgs/siva-voicefetch) and built as real
derivations: interpreters pinned, every runtime tool (`whisper-cli`, `piper`,
`pw-record`, `wpctl`, `wtype`, `ydotool`, `grim`, `tesseract`, `niri`, `socat`,
`sox`, …) wrapped onto `PATH`, and the scripts' old `~/.local/bin` references
rewritten to point inside the derivation. Nothing has to be copied into your
home directory for the stack to work.

They are vendored rather than pulled as flake inputs so the exact code that
runs on this machine is what ships — including work not yet pushed upstream.
Re-sync from a development checkout by copying `bin/` (and `lib/`) over
`pkgs/<name>/src/`.

> **Migrating from a hand-installed copy:** `~/.local/bin` comes first on the
> user's `PATH` (`home.sessionPath`), so old copies of `siva`, `siva-daemon`,
> `siva-type`, … sitting there will *shadow* the packaged ones — and those old
> copies still point back into `~/.local/bin` instead of the store.
> `install.sh` reports this as **"No shadowed SIVA copies"** and prints the
> exact `rm` to run. Deleting them is left to you.

### Services

Everything is a **systemd user service** — nothing runs as root, and nothing
depends on niri's `spawn-at-startup`, so the whole stack comes up under COSMIC
too.

| Unit | Starts at | Restart | Notes |
| --- | --- | --- | --- |
| `siva-llama-server.service` | `default.target` | `on-failure`, no give-up | The LLM backend. No Wayland needed, so it is warm before you finish logging in (the user has `linger`). |
| `siva.service` | `graphical-session.target` | `on-failure`, 5×/5 min | The orchestrator. `Wants=` llama-server. |
| `siva-wake.service` | `graphical-session.target` | `on-failure`, 5×/5 min | `Requires=siva.service` — nothing to toggle without it. |
| `siva-type.service` | `graphical-session.target` | `on-failure`, 5×/5 min | Dictation. |
| `siva-voicefetch.service` | `graphical-session.target` | `on-failure`, 5×/5 min | Voice-model downloader. |

`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` are **not**
hardcoded anywhere: both `niri --session` and `cosmic-session` import the
session environment into systemd and pull up `graphical-session.target`, and
the units hang off that.

```sh
systemctl --user status siva.service
journalctl --user -u siva-llama-server.service -f
systemctl --user restart siva.service
```

The F7/F8/F9 keys run the *toggle clients*, which send one JSON message to the
daemon's socket and start the daemon themselves if the unit is stopped — so
they are safe to press whatever state things are in.

### llama-server

Configured entirely through Nix options
([`modules/nixos/siva/llama-server.nix`](modules/nixos/siva/llama-server.nix)):

```nix
services.siva.llama = {
  host = "127.0.0.1";        # loopback only — the server is unauthenticated,
  port = 8090;               # and an assertion stops you binding it wider
  modelDir = "…/models/gemma-4-31b";
  model    = "gemma-4-31B-it-qat-UD-Q4_K_XL.gguf";
  mmproj   = "mmproj-F16.gguf";
  contextSize = 4096;        # also exported to the daemons as SIVA_LLAMA_CTX
  gpuLayers = 99;
  cuda = true;               # follows my.nvidia.enable
};
```

An `ExecCondition` checks the weights are readable before starting, so a
machine without them logs one skip instead of a restart loop. Hardening is on
(`ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges`,
address-family restrictions, …) but deliberately stops short of
`MemoryDenyWriteExecute` and `PrivateDevices`, which break CUDA.

DaVinci Resolve and the LLM both want the 4090's VRAM, so a small watcher
(`davinci-llm-pause.service`) stops the server while `resolve` is running and
restarts it on quit — but only if *it* stopped it, so a manual stop stays
stopped.

### Models and assets

The weights are **not** in the nix store — ~18 GB of the LLM plus ~250 MB of
speech models, all user data that changes independently of the system.

```sh
siva-fetch-assets      # whisper STT + piper voice + openWakeWord (idempotent)
```

The LLM GGUFs go in `services.siva.llama.modelDir` by hand (the script prints
the exact command). Then:

```sh
systemctl --user restart siva-llama-server
```

The wake word needs a one-time enrollment before `siva-wake` does anything:

```sh
siva-enroll            # say "Siva" a few times
```

### SIVA-Voicefetch

Searches voice-models.com, downloads and unpacks RVC v2 models into
`~/.local/share/siva/voices`, and publishes the chosen one to
`~/.local/share/siva/voice.json` — the single file `siva-daemon` reads to decide
between RVC and plain piper. That file is the entire integration surface
between them, so no extra wiring is needed.

The RVC *inference* stack (torch, transformers, the vendored RVC code) is far
too large and churn-prone to pin here, so it lives in a user-owned virtualenv
built on demand:

```sh
siva-rvc-setup         # ~2.5 GB of torch; idempotent
```

Microphone selection is **not** hardcoded. Both this and `siva-daemon`
enumerate inputs through `wpctl` at runtime and share the choice in
`~/.local/share/siva/mic.json`, so swapping audio interfaces just works.

### SIVA-Type and input permissions

Typing into the focused surface is Wayland-native, not X11 — XWayland is not
required anywhere in the stack:

- **`wtype`** uses the `zwp_virtual_keyboard_v1` protocol, which niri
  implements. This is the normal path and needs **no privileges at all**.
- **`ydotool`** is the uinput fallback for surfaces that refuse virtual-keyboard
  input, and for SIVA's pointer control. It needs `/dev/uinput`, which
  `programs.ydotool` provides through a *system* `ydotoold` socket group-owned
  by `ydotool`.

**The one unavoidable permission:** the user is in the `ydotool` group
(`modules/nixos/core.nix`), which grants access to that socket — and therefore
the ability to synthesise arbitrary input system-wide. That is inherent to
uinput-level control; there is no narrower mechanism. Nothing runs as root, and
no blanket `/dev/uinput` permission is granted to every process. Drop the group
(and `services.siva.enable = false`) if you do not want it.

## 🖼️ Wallpaper

The canonical copy lives in the repository at
[`assets/wallpapers/wallpaper.jpg`](assets/wallpapers). Home Manager
materialises it at `~/Pictures/Wallpaper/wallpaper.jpg`:

```nix
home.file."Pictures/Wallpaper/wallpaper.jpg".source = ../../assets/wallpapers/wallpaper.jpg;
```

Both sessions are pointed at that path:

- **niri** — `swaybg` via `spawn-at-startup` in
  [`config/niri/config.kdl`](config/niri/config.kdl) (through `sh -c` so `$HOME`
  is expanded rather than hardcoded)
- **COSMIC** — `cosmic-bg`'s RON config, written declaratively in
  [`modules/home/desktop.nix`](modules/home/desktop.nix)

To change it, replace the file in `assets/wallpapers/` and rebuild.

> Because the COSMIC background config is a store symlink, COSMIC
> Settings › Wallpaper becomes read-only. Delete that block in
> `modules/home/desktop.nix` if you would rather pick wallpapers from the GUI.

---

## 🛠️ Custom tools

- **`nixos-update`** — one command for the kernel pin, the flake inputs, the nix
  profile, the flatpaks and the firmware, then a single rebuild with a closure
  diff to approve. Backed by `nixos-update-check` on a timer and a waybar
  widget. See [Updating](#-updating).
- **[feathershot](https://github.com/r3dg0d/feathershot) MKII** — a native
  Wayland screenshot + annotation tool bound to `PrtSc`. `grim`/`slurp` capture
  → a Quickshell overlay for arrows, boxes, circles, freehand and text →
  composited back onto the original capture with cairo at native resolution.
- **`fnkey`** — the dispatcher behind every `Fn` + `F1…F12` binding: does the
  thing, then hands the resulting state to the quickshell OSD. See
  [The Fn key row](#-the-fn-key-row).
- **`monitor-brightness`** — DDC/CI brightness for monitors with no backlight
  sysfs node, with cached bus discovery and coalesced writes so it survives a
  held key. See
  [Display brightness](#display-brightness-on-desktop-monitors).
- **`nixos-screensaver`** — the NixOS logo animated with
  [terminaltexteffects](https://github.com/ChrisBuilds/terminaltexteffects)
  across both monitors after five idle minutes. See
  [Screensaver](#-screensaver).
- **[SIVA](https://github.com/r3dg0d/siva)** +
  [siva-type](https://github.com/r3dg0d/siva-type) +
  [siva-voicefetch](https://github.com/r3dg0d/siva-voicefetch)
- **[sddm-ascii-city](https://github.com/r3dg0d/sddm-ascii-city)** — the login theme

## 📦 Daily-driver software

Installed declaratively — mostly [nixpkgs](https://search.nixos.org/packages),
a few Flatpaks, plus flake inputs and vendored derivations.

### Web & communication
| App | Source | Use |
|-----|--------|-----|
| [Helium](https://github.com/imputnet/helium-linux) | vendored AppImage | Primary browser (defaults to local SearXNG via managed policy) |
| Firefox / Tor Browser | nixpkg | Secondary / anonymous browsing |
| FreeTube | nixpkg | Privacy-friendly YouTube client |
| browsh | nixpkg | Text-mode browsing in the terminal (drives a headless Firefox) |
| Thunderbird | nixpkg | Email (Gmail replacement) |
| SimpleX Chat · CoyIM · irssi | nixpkg | Private messaging · XMPP/OTR · IRC |

### Creative & media
| App | Source | Use |
|-----|--------|-----|
| **DaVinci Resolve** 21 | vendored ([`pkgs/davinci-resolve.nix`](pkgs/davinci-resolve.nix)) | Video editing (NVENC on the 4090) |
| OBS Studio (CUDA/NVENC) | nixpkg module | Screen recording (wlrobs on niri, ONNX background removal) |
| Blender | **Flatpak** `org.blender.Blender` | 3D |
| mpv · Jellyfin (server + client) | nixpkg | Playback · home media |
| mpd + rmpc · EasyEffects | nixpkg | Music daemon + TUI · PipeWire effects |

### Gaming
| App | Source | Use |
|-----|--------|-----|
| Steam (Proton, Remote Play) | nixpkg module | Gaming |
| ProtonPlus | **Flatpak** `com.vysp3r.ProtonPlus` | Proton/Wine version manager |
| PCSX2 · PrismLauncher | nixpkg | PS2 emulation · Minecraft |
| Hydra | wrapped | Game launcher |
| WiVRn | nixpkg module | OpenXR streaming to a standalone headset |

### Productivity
Obsidian · etesync-dav (calendar) · LibreTranslate.

### Privacy & security
Mullvad VPN + encrypted Mullvad DNS (ad/tracker blocking) · Lokinet (`.loki`,
custom-fixed build) · KeePassXC · Monero · qBittorrent · self-hosted SearXNG ·
Wireshark · sqlmap · smap · hashcat.

### Dev & local AI
Claude Code · OpenCode · Codex · VSCodium · Neovim · gh · Docker ·
libvirt/QEMU + virt-manager · the Android SDK/NDK · ARM64 and i686-mingw32
cross-compilers — and the local AI stack: `ollama-cuda`, `llama.cpp` (CUDA),
`whisper.cpp`, `piper-tts`, MemPalace.

### Rice runtime
Ghostty · rofi · waybar · quickshell · mako · swaybg · fastfetch · starship ·
cliphist · Bibata cursors · JetBrains Mono Nerd Font · adw-gtk3-dark +
Papirus-Dark for GTK.

---

## 📁 Layout

```
├── flake.nix                    # inputs, overlays, the hosts map
├── install.sh                   # fresh-machine bootstrap + self-check
│
├── hosts/
│   └── nixos-btw/
│       ├── default.nix          # MACHINE-SPECIFIC only: boot, GPU model, the
│       │                        #   Scarlett filter chain, login music, tz
│       └── hardware-configuration.nix   # generated; never copied between machines
│
├── modules/
│   ├── nixos/                   # everything PORTABLE
│   │   ├── options.nix          #   my.username / my.homeDirectory / my.dotfilesDir
│   │   ├── core.nix             #   nix, the user, shells, fonts, logind,
│   │   │                        #   NTFS support for the external backup SSD
│   │   ├── kernel.nix           #   nixpkgs' latest, or Linus' mainline tree
│   │   ├── updater.nix          #   nixos-update + its check timer
│   │   ├── networking.nix       #   NetworkManager, Mullvad DNS, lokinet
│   │   ├── audio.nix            #   PipeWire + WirePlumber
│   │   ├── hardware/nvidia.nix
│   │   ├── desktop/{sddm,niri,cosmic,portals,apps}.nix
│   │   ├── desktop/fnkeys.nix   #   Fn + F1…F12: i2c access + the tools
│   │   ├── desktop/screensaver.nix  # swayidle → the idle screensaver
│   │   ├── programs.nix         #   CLI + security tooling
│   │   ├── services.nix         #   Jellyfin, SearXNG, WiVRn
│   │   ├── virtualisation.nix   #   libvirt/QEMU
│   │   ├── development.nix      #   Android SDK, cross-compilers
│   │   └── siva/                #   the voice stack: options + user services
│   │       ├── default.nix · llama-server.nix · voicefetch.nix · type.nix
│   └── home/                    # Home Manager: shell.nix · desktop.nix · services.nix
│
├── pkgs/                        # everything this repo builds itself
│   ├── default.nix              #   the overlay (also the nixpkgs overrides)
│   ├── nixos-updater/           #   the update checker/updater + waybar widget
│   ├── linux-mainline/          #   torvalds/linux, pinned in pin.json
│   ├── helium.nix               #   the browser: AppImage + Ozone-Wayland wrapper
│   ├── fnkeys/                  #   the Fn + F1…F12 dispatcher
│   ├── monitor-brightness/      #   DDC/CI brightness for the ultrawides
│   ├── nixos-screensaver/       #   idle screensaver + the trimmed logo
│   ├── sddm-ascii-city.nix · siva/ · siva-type/ · siva-voicefetch/
│   ├── siva-fetch-assets.nix · davinci-resolve.nix
│   └── hydralauncher-wayland.nix · quickshell-mirror.nix · mingw32-cc.nix
│
├── sddm-ascii-city/             # the SDDM theme sources (+ test/run-harness.sh)
├── assets/wallpapers/           # the canonical wallpaper
└── config/                      # dotfiles symlinked live into ~/.config
                                 #   (niri, waybar, quickshell, rofi, mako, mpv,
                                 #    rmpc, nvim, fastfetch, scripts)
```

Two deliberate rules shape this:

- **`config/` is symlinked *out of* the store** (`mkOutOfStoreSymlink`), so
  editing `config/niri/config.kdl` takes effect immediately — niri hot-reloads
  it — with no rebuild. Nothing in the *system* closure depends on the checkout
  location, so a machine with the repo somewhere else still boots and logs in.
- **`hosts/` vs `modules/`** is the portable/machine-specific split. If a
  setting names a UUID, a boot device, a specific GPU, a specific audio
  interface, or a path under someone's home, it belongs in `hosts/`.

## 🧩 Flake inputs & overlays

- **[nixpkgs](https://github.com/NixOS/nixpkgs)** `nixos-26.05` +
  **[home-manager](https://github.com/nix-community/home-manager)** `release-26.05`
- **[areofyl/fetch](https://github.com/areofyl/fetch)** — the animated 3D `fetch`
- Overlays: everything in [`pkgs/`](pkgs), plus `lokinet` patched to build from
  source (nixpkgs marks it broken)

Every input is fetchable from the network, so a clone of this repository is all
a fresh machine needs.

## 🧳 Portability

Machine-specific things — filesystems, UUIDs, boot device, GPU model, NIC,
CPU, the audio interface — live only in `hosts/<name>/`. Everything else is
portable, so installing this environment on a second computer is:

```sh
mkdir hosts/newbox
cp hosts/nixos-btw/default.nix hosts/newbox/default.nix   # then trim it
# add `newbox = { system = "x86_64-linux"; user = "…"; };` to flake.nix
./install.sh --host newbox
```

`install.sh` generates that machine's own `hardware-configuration.nix` and will
**not** overwrite one whose UUIDs already resolve locally.

There are no local-path flake inputs, so nothing has to exist outside the
clone. (`install.sh` still checks for `git+file://` inputs and reports a
missing checkout up front, in case one is ever added.)

## 🔑 Secrets

Nothing secret is committed. The configuration references exactly one file
outside the repo — `/etc/searxng.env`, holding the SearXNG instance key —
which `install.sh` generates with `mode 0600` if it is missing.
The VanillaAmerica+ bot reads its token from a `.env` in its own working copy,
which is likewise never in this repository (and its unit has a
`ConditionPathExists` so it stays quiet on machines that lack it).

---

## 🔄 Updating

`nixos-update` moves every source this machine pulls from and then does **one**
rebuild that picks all of it up at once:

```sh
nixos-update                # everything, with a diff to approve before switching
nixos-update -y --gc        # unattended, then prune generations older than 14d
nixos-update --dry          # build and show the diff, never activate
nixos-update-check          # only look; change nothing
```

| step | what moves | turn off with |
|---|---|---|
| kernel | `pkgs/linux-mainline/pin.json` → newest `torvalds/linux` tag | `--no-kernel` |
| flake | `flake.lock` — nixpkgs, home-manager, `fetch` | `--no-flake` |
| profile | `nix profile upgrade --all` | `--no-profile` |
| flatpak | `flatpak update` + prune unused runtimes | `--no-flatpak` |
| firmware | `fwupdmgr update` — **opt-in**, it flashes hardware | *(on with `--firmware`)* |
| rebuild | `nixos-rebuild build` → diff → `switch` | `--no-rebuild`, `--boot`, `--dry` |

Nothing is activated without showing you an [`nvd`](https://khumba.net/projects/nvd)
diff of the closure first — and the build happens *before* that prompt, so a
build failure leaves the running system untouched.

The old manual route still works, of course:

```sh
cd ~/nixos-dotfiles
nix flake update                          # all inputs
nix flake update nixpkgs                  # just one
sudo nixos-rebuild switch --flake .#nixos-btw
```

### The waybar widget

![Waybar](assets/waybar.png)

`custom/nixupdate` in the right-hand cluster shows a ❄ with the number of
pending updates — dim green when there is nothing to do, glowing green when
there is, amber when the booted kernel is no longer the current one. Hovering
lists what is waiting, per source.

- **left click** — `nixos-update` in a ghostty window
- **right click** — re-check now, with output
- **middle click** — re-check quietly in the background

A systemd **user** timer (`nixos-update-check.timer`, every
`my.updater.interval`, default 6h) refreshes the answer and raises `RTMIN+13` at
waybar, so the count drops the moment an update finishes rather than on the next
poll. The widget itself only ever reads
`~/.cache/nixos-updater/status.json` — it never does network work on waybar's
interval.

```nix
my.updater.enable    = true;   # the commands + the widget's data
my.updater.autoCheck = true;   # the timer
my.updater.interval  = "6h";
```

### Tracking the mainline kernel

Off by default; this host boots nixpkgs' newest packaged kernel. To follow
Linus' tree instead — release candidates included:

```nix
my.kernel.mainline.enable = true;   # hosts/nixos-btw/default.nix
my.kernel.mainline.trackRC = true;  # false = final releases only
```

The tag is **pinned** in [`pkgs/linux-mainline/pin.json`](pkgs/linux-mainline/pin.json)
rather than resolved during evaluation, because a configuration that changed
underneath you between two rebuilds would not be reproducible. `nixos-update`
rewrites that file; `nixos-kernel-pin` does it on its own:

```sh
nixos-kernel-pin --print     # pinned vs newest upstream
nixos-kernel-pin             # bump to newest (~250 MB fetch)
nixos-kernel-pin v7.1        # pin something specific — this is the rollback
```

Know what this costs before enabling it: **no binary cache has it**, so every
bump is a 20-60 minute kernel compile plus a rebuild of every out-of-tree
module. NVIDIA's proprietary driver in particular often fails to build against
a fresh `-rc`; when that happens the *build* fails, which is safe — the running
system is untouched — and the fix is to pin back a tag. Keep more than one
generation in the boot menu while tracking `-rc` kernels.

## 🩺 Troubleshooting

**Check it builds before you switch.** A failed build changes nothing; a failed
switch does.

```sh
nixos-rebuild build --flake .#nixos-btw   # or: ./install.sh --build-only
nix flake check                           # evaluates AND builds every host
```

| Symptom | Look at |
| --- | --- |
| A SIVA service is dead | `journalctl --user -u siva.service -n 50` |
| SIVA answers nothing | `systemctl --user status siva-llama-server` — usually the model path or VRAM |
| llama-server "skipped" | the weights are missing; `ls "$(nix eval --raw .#nixosConfigurations.nixos-btw.config.services.siva.llama.modelDir)"` |
| Wake word never fires | `siva-enroll` has not been run, or `~/.local/share/siva/wake/verifier.pkl` is stale — see [`siva-wake-websearch`](https://github.com/r3dg0d/siva) notes; re-enroll |
| Greeter shows an old theme | `QML_DISABLE_DISK_CACHE` is not taking effect — clear `/var/lib/sddm/.cache` |
| Greeter looks blank | run the harness (above); the greeter itself hides QML errors |
| Wrong desktop after a rebuild | `QML_XHR_ALLOW_FILE_READ=1` missing from the display-manager environment |
| No sound / no mic in SIVA | `wpctl status`; SIVA's choice is in `~/.local/share/siva/mic.json` |
| Typing does not work | `systemctl status ydotoold` and `id` — you must be in the `ydotool` group |
| Wallpaper missing | Home Manager has not run for that user; `systemctl status home-manager-$USER` |
| An AppImage app paints a blank window | see below — it is the NVIDIA/Ozone trap, not a crash |
| A new quickshell widget never appears | quickshell does not hot-reload; `pkill quickshell && qs -d` |
| `Fn`+`F1`/`F2` does nothing | `monitor-brightness status` — if it says `brightnessctl`, no DDC display answered: check `id` for the `i2c` group (needs a fresh login) and `ls /dev/i2c-*` |
| Another `Fn` key does nothing | `wev` and press it; the keysym it prints is what the bind in `config/niri/config.kdl` should be named |
| An `Fn` key works but shows no OSD | quickshell is not running — the action is deliberately independent of it |
| Screensaver never fires | `systemctl --user status screensaver`; something may be holding an idle inhibitor — check with `nixos-screensaver start` that it works at all |
| Screensaver logo looks cropped | the terminal has fewer than 47 rows — lower `services.screensaver.fontSize` |
| Screensaver only covers one monitor | a terminal failed to spawn; `nixos-screensaver stop` then `start`, and check `journalctl --user -u screensaver` |
| `nixos-update` reports a section error | run `nixos-update-check` by hand; the failing step prints its own message |

### AppImage apps that paint a blank window

This has now bitten two packages here — Hydra Launcher and Helium — and the
process looks perfectly healthy while it happens, so exit codes prove nothing.
**Screenshot the window and actually look at it.** Two causes, both from the
same root: a bundled Chromium/Electron never passes through the nixpkgs
wrapper, so the global `NIXOS_OZONE_WL=1` does nothing for it.

1. `--ozone-platform-hint=auto` is silently ignored; the app picks X11 and goes
   through XWayland. Only an explicit `--ozone-platform=wayland` works.
2. On Wayland the bundled EGL cannot drive the NVIDIA card
   (`pci id … driver (null)` → `failed to create dri2 screen`), the GPU process
   dies at init, and the window paints solid white or black. GLVND has to be
   pointed at the NVIDIA ICD **by filename** —
   `__EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json`.
   Naming the whole `egl_vendor.d` directory is not enough: Mesa's
   `50_mesa.json` still wins and fails identically.

Both fixes go in a `makeWrapper --run` guarded on `$WAYLAND_DISPLAY`, and the
`.desktop` `Exec=` must be repointed at the wrapper or the launcher bypasses it.
Working examples: [`pkgs/helium.nix`](pkgs/helium.nix) and
[`pkgs/hydralauncher-wayland.nix`](pkgs/hydralauncher-wayland.nix).

Useful commands:

```sh
systemctl --user status siva-llama-server.service
journalctl --user -u siva-type.service -f
systemctl --user list-units 'siva*'
systemd-analyze --user verify /etc/systemd/user/siva.service
nix build .#siva && ./result/bin/siva-daemon      # run a daemon by hand
```

## ⏪ Rollback

A `nixos-rebuild switch` never destroys the previous generation.

```sh
sudo nixos-rebuild switch --rollback          # back one generation, now
sudo nix-env --list-generations -p /nix/var/nix/profiles/system
sudo nixos-rebuild switch --flake .#nixos-btw --rollback
```

If the machine will not boot at all, every generation is still an entry in the
systemd-boot menu — pick the previous one there, then investigate.

To undo a repository change rather than a system one, `git` is the answer:
`git log`, `git revert <commit>`, rebuild.

<div align="center">

*I use NixOS, btw.* 🐧

</div>
