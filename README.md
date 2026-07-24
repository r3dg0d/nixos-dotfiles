<div align="center">

# ❄️ nixos-dotfiles

**A fully-declarative NixOS flake for `nixos-btw` — a [niri](https://github.com/YaLTeR/niri) Wayland rice in OLED black, white, and neon green (`#00ff41`).**

Ricing, a local agentic voice assistant, degoogled daily drivers, gaming, video editing, and privacy tooling — all reproducible from one `nixos-rebuild`.

</div>

---

## 🖥️ The desktop

![Desktop](assets/desktop.png)

A tiling niri session on dual 3440×1440 ultrawides: an ASCII-art wallpaper, a slim [waybar](https://github.com/Alexays/Waybar), and a [quickshell](https://quickshell.org/) layer for widgets and overlays. Everything is themed to the same OLED-black / white / neon-green (`#00ff41`) palette — down to the zsh syntax highlighting and the [starship](https://starship.rs/) prompt.

## 🖼️ `fetch` — animated 3D system info

![fetch](assets/fetch.png)

The terminal is [ratty](https://github.com/orhun/ratty) (GPU-rendered, with inline 3D graphics), running [areofyl/fetch](https://github.com/areofyl/fetch) — a neofetch-style tool that spins a **3D ASCII distro logo** next to the system info (i9-14900K, RTX 4090, niri on Wayland). Pulled in as the `areofyl-fetch` flake input.

## 🔐 SDDM login theme — `sddm-ascii-city`

![SDDM theme](assets/sddm.png)

A custom SDDM theme (built as a Nix derivation in [`configuration.nix`](configuration.nix)): animated ASCII "matrix" rain falling over an ASCII city skyline, a grayscaled avatar, and a minimalist login box. A `systemd` service even plays login music straight to the Scarlett 2i2 over ALSA while the greeter is on screen (the QML greeter has no PipeWire to play through), and stops the instant a session starts.

## 🧰 Waybar

![Waybar](assets/waybar.png)

Workspaces and focused-window title on the left, clock in the center, and a status cluster on the right — weather, temperatures, volume, network, CPU and memory, and a power button that opens the quickshell power menu.

## 🪟 Quickshell widgets

![Quickshell power menu](assets/quickshell.png)

Hand-written [quickshell](https://quickshell.org/) components in [`config/quickshell/`](config/quickshell), all in the same neon-green theme and driven by IPC (`qs ipc call <target> toggle`):

- **Clipboard manager** — `cliphist` history with fuzzy search (`Mod+C`)
- **Wi-Fi picker** — `nmcli` network menu (waybar network click)
- **Power menu** — logout / restart / shutdown / sleep (waybar power click, shown above)
- **SIVA overlays** — the voice-assistant status panel, live agentic screen stream, and enrollment wizard

## 🎙️ SIVA — a local agentic voice assistant

![SIVA overlay](assets/siva.png)

[**SIVA**](https://github.com/r3dg0d/siva) (Super Intelligent Voice Assistant) is my own fully-local, agentic desktop assistant for niri. Press **F8**, talk, and it sees the screen (gemma-4 vision via llama.cpp), reasons out loud in the overlay, and drives the desktop — cursor, clicks, typing, window management — then speaks its answer. It has **durable cross-session memory** via [MemPalace](https://github.com/MemPalace/mempalace) (that's what `programs.nix-ld` is enabled for). The whole stack runs on the RTX 4090 with no cloud and no API keys.

The stack is wired into this config via niri binds and a `systemd` user service:

| Key | Tool | What it does |
|-----|------|--------------|
| **F7** | [siva-voicefetch](https://github.com/r3dg0d/siva-voicefetch) | Toggle RVC voice models for TTS |
| **F8** | [siva](https://github.com/r3dg0d/siva) | Push-to-talk agentic voice assistant |
| **F9** | [siva-type](https://github.com/r3dg0d/siva-type) | AI dictation — speak to type anywhere |

> DaVinci Resolve and SIVA's LLM both want the 4090's VRAM, so a small user service pauses `siva-llm` while `resolve` is running and restarts it on quit (see [`home.nix`](home.nix)).

## 🛠️ Custom tools

Tools I built that this config depends on:

- **[feathershot](config/scripts)** — a native Wayland screenshot + annotation tool (`grim`/`slurp` capture → GTK/Cairo editor for arrows, boxes, circles, text, freehand). Replaces niri's built-in screenshot on `PrtSc`.
- **[SIVA](https://github.com/r3dg0d/siva)** + [siva-type](https://github.com/r3dg0d/siva-type) + [siva-voicefetch](https://github.com/r3dg0d/siva-voicefetch) — the voice-assistant stack above.
- **quickshell widgets** — the clipboard/wifi/power/SIVA components in [`config/quickshell/`](config/quickshell).
- **sddm-ascii-city** — the login theme above.
- **Deep eboy voice** — a PipeWire filter-chain virtual mic (downward expander → shelving EQ → gain) defined in [`configuration.nix`](configuration.nix), selectable in Discord/OBS.

## 📦 Daily-driver software

Installed declaratively — mostly [nixpkgs](https://search.nixos.org/packages), a few Flatpaks, plus flake inputs and vendored derivations.

### Web & communication
| App | Source | Use |
|-----|--------|-----|
| [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium) | nixpkg | Primary browser (defaults to local SearXNG) |
| Firefox / Tor Browser | nixpkg | Secondary / anonymous browsing |
| FreeTube | nixpkg | Privacy-friendly YouTube client |
| Thunderbird | nixpkg | Email (Gmail replacement) |
| Vesktop | nixpkg | Discord (Vencord baked in) |
| SimpleX Chat · CoyIM · irssi | nixpkg | Private messaging · XMPP/OTR · IRC |

### Creative & media
| App | Source | Use |
|-----|--------|-----|
| **DaVinci Resolve** 21 | vendored derivation ([`davinci-resolve.nix`](davinci-resolve.nix)) | Video editing (NVENC on the 4090) |
| OBS Studio (CUDA/NVENC) | nixpkg module | Screen recording (wlrobs on niri) |
| Blender | **Flatpak** `org.blender.Blender` | 3D |
| mpv · Jellyfin Media Player | nixpkg | Playback · home media |
| mpd + rmpc · EasyEffects | nixpkg | Music daemon + TUI · PipeWire effects |

### Gaming
| App | Source | Use |
|-----|--------|-----|
| Steam (Proton, Remote Play) | nixpkg module | Gaming |
| ProtonPlus | **Flatpak** `com.vysp3r.ProtonPlus` | Proton/Wine version manager |
| PCSX2 · PrismLauncher | nixpkg | PS2 emulation · Minecraft |
| Hytale Launcher | **Flatpak** `com.hypixel.HytaleLauncher` | Hytale |

### Productivity
Obsidian · OnlyOffice · etesync-dav (calendar) · LibreTranslate — degoogled replacements for notes, docs, calendar, and translation.

### Privacy & security
Mullvad VPN + encrypted Mullvad DNS (ad/tracker blocking) · Lokinet (`.loki`, custom-fixed build) · KeePassXC · Monero (GUI/CLI) · qBittorrent · self-hosted SearXNG · Wireshark/termshark · sqlmap · smap · hashcat.

### Dev & local AI
Claude Code · OpenCode · Antigravity · VSCodium · Neovim (+ `nil`, `nixpkgs-fmt`) · gh · Docker — and a local AI stack: `ollama-cuda`, `llama.cpp` (CUDA), `whisper.cpp`, `piper-tts`, and MemPalace powering SIVA.

### Rice runtime
ratty (terminal) · rofi · waybar · quickshell · mako · swaybg · fastfetch · starship · cliphist · Bibata cursors · JetBrains Mono Nerd Font.

## 🧩 Flake inputs & overlays

- **[nixpkgs](https://github.com/NixOS/nixpkgs)** `nixos-26.05` + **[home-manager](https://github.com/nix-community/home-manager)** `release-26.05`
- **[areofyl/fetch](https://github.com/areofyl/fetch)** — animated 3D `fetch` tool (`areofyl-fetch`)
- Overlays: `ratty` pinned to v0.5.0 (Wayland clipboard fix); `lokinet` patched to build from source (nixpkgs marks it broken)
- Vendored: `davinci-resolve.nix` (bumped from [creatorkostas/davinci-resolve-nixos](https://github.com/creatorkostas/davinci-resolve-nixos))

## 📁 Layout

```
├── flake.nix               # inputs + the nixos-btw system
├── configuration.nix       # system: niri, nvidia, services, systemPackages, SDDM theme
├── home.nix                # home-manager: zsh/starship, dotfile symlinks, user services
├── davinci-resolve.nix     # vendored Resolve 21 derivation
├── hardware-configuration.nix
├── sddm-ascii-city/        # custom animated SDDM theme
└── config/                 # dotfiles symlinked into ~/.config (niri, waybar, quickshell,
                            #   rofi, mako, mpv, rmpc, nvim, ratty, fastfetch, scripts)
```

## 🚀 Rebuild

```sh
sudo nixos-rebuild switch --flake ~/nixos-dotfiles#nixos-btw
```

Hardware-specific bits (NVIDIA RTX 4090, Focusrite Scarlett 2i2, the two ultrawides) live in `configuration.nix` / `hardware-configuration.nix` — adjust for your machine.

<div align="center">

*I use NixOS, btw.* 🐧

</div>
