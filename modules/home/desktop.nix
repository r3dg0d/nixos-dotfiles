# Desktop dotfiles: the live-editable config symlinks, Ghostty, the cursor
# theme and default applications.
{ config, lib, pkgs, osConfig, ... }:

let
  # config/ is symlinked *out of* the store on purpose: editing
  # ~/nixos-dotfiles/config/niri/config.kdl takes effect immediately (niri
  # hot-reloads it) instead of needing a rebuild. Only these convenience
  # symlinks depend on the checkout location; nothing in the system closure
  # does, so a machine with the repo elsewhere still boots.
  dotfiles = "${osConfig.my.dotfilesDir}/config";
  liveLink = path: config.lib.file.mkOutOfStoreSymlink path;

in
{
  xdg.configFile = lib.mkMerge [
    # ---- live-editable configs --------------------------------------------
    (lib.genAttrs
      [ "nvim" "niri" "ratty" "waybar" "rofi" "mako" "quickshell" "mpv" "rmpc" "fastfetch" ]
      (name: {
        source = liveLink "${dotfiles}/${name}/";
        recursive = true;
      }))

    {
      # ---- Ghostty ---------------------------------------------------------
      # Written as a plain config file rather than through programs.ghostty so
      # it does not depend on that module existing in a given Home Manager
      # release. Themed to match the rest of the rice: OLED black, white text,
      # neon-green cursor and selection.
      "ghostty/config".text = ''
        font-family = JetBrainsMono Nerd Font Mono
        font-size = 12

        background = #000000
        foreground = #ffffff
        background-opacity = 1.0

        cursor-color = #00ff41
        cursor-style = block
        cursor-style-blink = true

        selection-background = #00ff41
        selection-foreground = #000000

        # normal
        palette = 0=#0a0a0a
        palette = 1=#ff2b2b
        palette = 2=#00ff41
        palette = 3=#d8d8d8
        palette = 4=#5f5f5f
        palette = 5=#8c8c8c
        palette = 6=#39ff14
        palette = 7=#f2f2f2
        # bright
        palette = 8=#3a3a3a
        palette = 9=#ff5555
        palette = 10=#39ff14
        palette = 11=#ffffff
        palette = 12=#8c8c8c
        palette = 13=#bcbcbc
        palette = 14=#00ff41
        palette = 15=#ffffff

        window-decoration = false
        window-padding-x = 8
        window-padding-y = 8
        confirm-close-surface = false
        shell-integration = zsh
      '';
    }
  ];

  # ---- cursor --------------------------------------------------------------
  # Bibata Modern Classic cursor (gtk + x11 themes, XCURSOR_* env vars)
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };

  # ---- default applications ------------------------------------------------
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "chromium-browser.desktop" ];
      "application/xhtml+xml" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/http" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/https" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/about" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/unknown" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/qrc" = [ "kyber-linuxport-qrc.desktop" ];
      "x-scheme-handler/nxm" = [ "kyber-linuxport-nxm.desktop" ];
    };
  };

  # Hide these apps from the rofi drun launcher without uninstalling them.
  # Each entry shadows the package-provided .desktop (matched by filename, so
  # attr name/case must match) with NoDisplay=true. rmpc is a TUI kept for the
  # mpd setup; alacritty/firefox/dualcpy are just decluttered from the menu.
  xdg.desktopEntries = {
    rmpc = { name = "rmpc"; noDisplay = true; };
    firefox = { name = "firefox"; noDisplay = true; };
    Alacritty = { name = "Alacritty"; noDisplay = true; };
    dualcpy = { name = "dualcpy"; noDisplay = true; };
  };

  # ---- rice runtime bits ---------------------------------------------------
  home.packages = with pkgs; [
    swaybg # wallpaper
    mako # notification daemon
    libnotify # notify-send for testing notifications
    nautilus # file manager
    wl-clipboard # clipboard for wayland
    brightnessctl # backlight keys
    pavucontrol # audio control (waybar click)
  ];
}
