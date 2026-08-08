# Desktop applications and the handful that need system-level configuration
# (managed browser policy, OBS with NVENC, Steam's firewall holes).
{ pkgs, ... }:

{
  # Terminals. ghostty is $TERMINAL and the daily driver; alacritty is the
  # fallback that Mod+Shift+Return opens when a Ghostty change breaks something.
  environment.systemPackages = with pkgs; [
    ghostty
    alacritty
    nautilus
    file-roller
    helium # default browser — Chromium fork, AppImage vendored + Ozone-Wayland wrapped
    freetube
    keepassxc
    thunderbird # Gmail replacement
    etesync-dav # Degoogled calendar
    immich # Photos
    libretranslate # Google Translate replacement
    obsidian
    vscodium # Coding IDE
    simplex-chat-desktop
    coyim
    irssi
    tor-browser
    tor
    monero-gui
    monero-cli
    qbittorrent
    localsend
    mpv
    imv
    yt-dlp
    ffmpeg
    video2x # ML upscaler/frame interpolator — AppImage vendored, launcher entry opens a ghostty prompt
    jellyfin-media-player # Jellyfin desktop client (native player, for this PC)
    prismlauncher
    pcsx2 # PlayStation 2 emulator
    hydralauncher-wayland # Hydra game launcher (Electron + embedded bittorrent), Ozone-Wayland wrapped
    davinci-resolve-studio-unofficial # video editor 21.0.3 — vendored from creatorkostas/davinci-resolve-nixos, version-bumped
    areofyl-fetch # animated 3D `fetch` tool (github:areofyl/fetch, via flake overlay)
    browsh # text-mode web browser (drives a headless Firefox, renders to the TTY)
    mullvad-vpn
    rmpc # Music player TUI
    mpd # Music Player Daemon
  ];

  programs.firefox.enable = true;

  # Managed policy that makes the local SearXNG the default (omnibox) search
  # engine. This module writes /etc/chromium/policies — which is still the
  # right path after the switch from ungoogled-chromium to Helium: Helium
  # inherits ungoogled-chromium's policy directory rather than branding its
  # own (`strings` on its binary turns up /etc/chromium/policies and nothing
  # else), so the policy carries over untouched.
  programs.chromium = {
    enable = true;
    defaultSearchProviderEnabled = true;
    defaultSearchProviderSearchURL = "http://localhost:8888/search?q={searchTerms}";
    defaultSearchProviderSuggestURL = "http://localhost:8888/autocompleter?q={searchTerms}";
    extraOpts.DefaultSearchProviderName = "SearXNG";
  };

  # Screen recording on niri via the wlr-screencopy protocol.
  programs.obs-studio = {
    enable = true;
    # cudaSupport builds OBS against the NVIDIA stack so the NVENC
    # encoders show up (https://nixos.wiki/wiki/OBS_Studio)
    package = pkgs.obs-studio.override { cudaSupport = true; };
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-3d-effect
      obs-advanced-masks
      obs-stroke-glow-shadow
      obs-backgroundremoval # ONNX portrait segmentation (green-screen-less bg removal)
    ];
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };

  # Flatpak (installs the flatpak pkg + sets up the service; portals already enabled above)
  services.flatpak.enable = true;
}
