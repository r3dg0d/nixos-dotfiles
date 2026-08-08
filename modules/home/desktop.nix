# Desktop dotfiles: the live-editable config symlinks, cursor theme, default
# applications, the wallpaper, and Ghostty.
{ config, lib, pkgs, osConfig, ... }:

let
  # config/ is symlinked *out of* the store on purpose: editing
  # ~/nixos-dotfiles/config/niri/config.kdl takes effect immediately (niri
  # hot-reloads it) instead of needing a rebuild. Only these convenience
  # symlinks depend on the checkout location; nothing in the system closure
  # does, so a machine with the repo elsewhere still boots.
  dotfiles = "${osConfig.my.dotfilesDir}/config";
  liveLink = path: config.lib.file.mkOutOfStoreSymlink path;

  # …the wallpaper, in contrast, is a real store copy: it should exist and be
  # correct on a fresh machine before the repo is even cloned to its final
  # location.
  wallpaper = ../../assets/wallpapers/wallpaper.jpg;
  wallpaperTarget = "Pictures/Wallpaper/wallpaper.jpg";
  wallpaperPath = "${config.home.homeDirectory}/${wallpaperTarget}";

  # ---- default-application mime tables -------------------------------------
  # Each list is the MimeType= line of the app's own .desktop, split by kind:
  # declaring an association is not the same as being the *default* for it, so
  # every type is named explicitly here. `assign` turns a list into the
  # { "<mime>" = [ "<desktop>" ]; } shape xdg.mimeApps wants.
  assign = desktop: mimes: lib.genAttrs mimes (_: [ desktop ]);

  audioMimes = [
    "application/ogg" "application/x-cue" "application/x-ogg"
    "application/x-ogm-audio" "audio/3gpp" "audio/3gpp2" "audio/aac"
    "audio/ac3" "audio/aiff" "audio/AMR" "audio/amr-wb" "audio/dv"
    "audio/eac3" "audio/flac" "audio/m3u" "audio/m4a" "audio/mp1" "audio/mp2"
    "audio/mp3" "audio/mp4" "audio/mpeg" "audio/mpeg2" "audio/mpeg3"
    "audio/mpegurl" "audio/mpg" "audio/musepack" "audio/ogg" "audio/opus"
    "audio/rn-mpeg" "audio/scpls" "audio/vnd.dolby.heaac.1"
    "audio/vnd.dolby.heaac.2" "audio/vnd.dts" "audio/vnd.dts.hd"
    "audio/vnd.rn-realaudio" "audio/vnd.wave" "audio/vorbis" "audio/wav"
    "audio/webm" "audio/x-aac" "audio/x-adpcm" "audio/x-aiff" "audio/x-ape"
    "audio/x-m4a" "audio/x-matroska" "audio/x-mp1" "audio/x-mp2"
    "audio/x-mp3" "audio/x-mpegurl" "audio/x-mpg" "audio/x-ms-asf"
    "audio/x-ms-wma" "audio/x-musepack" "audio/x-pls" "audio/x-pn-au"
    "audio/x-pn-realaudio" "audio/x-pn-wav" "audio/x-pn-windows-pcm"
    "audio/x-realaudio" "audio/x-scpls" "audio/x-shorten" "audio/x-tta"
    "audio/x-vorbis" "audio/x-vorbis+ogg" "audio/x-wav" "audio/x-wavpack"
  ];

  videoMimes = [
    "application/mxf" "application/sdp" "application/smil"
    "application/streamingmedia" "application/vnd.apple.mpegurl"
    "application/vnd.ms-asf" "application/vnd.rn-realmedia"
    "application/vnd.rn-realmedia-vbr" "application/x-extension-mp4"
    "application/x-matroska" "application/x-mpegurl" "application/x-ogm"
    "application/x-ogm-video" "application/x-smil"
    "application/x-streamingmedia" "video/3gp" "video/3gpp" "video/3gpp2"
    "video/avi" "video/divx" "video/dv" "video/fli" "video/flv" "video/mkv"
    "video/mp2t" "video/mp4" "video/mp4v-es" "video/mpeg" "video/msvideo"
    "video/ogg" "video/quicktime" "video/vnd.avi" "video/vnd.divx"
    "video/vnd.mpegurl" "video/vnd.rn-realvideo" "video/webm" "video/x-avi"
    "video/x-flc" "video/x-flic" "video/x-flv" "video/x-m4v"
    "video/x-matroska" "video/x-mpeg2" "video/x-mpeg3" "video/x-ms-afs"
    "video/x-ms-asf" "video/x-msvideo" "video/x-ms-wmv" "video/x-ms-wmx"
    "video/x-ms-wvxvideo" "video/x-ogm" "video/x-ogm+ogg" "video/x-theora"
    "video/x-theora+ogg"
  ];

  imageMimes = [
    "image/avif" "image/bmp" "image/gif" "image/heif" "image/jpeg"
    "image/jpg" "image/jxl" "image/pjpeg" "image/png" "image/qoi"
    "image/tiff" "image/tiff-fx" "image/webp" "image/x-bmp"
    "image/x-farbfeld" "image/x-png"
  ];

  # COSMIC Edit's .desktop only declares text/plain; the rest are the
  # everyday source/config types that should still open in it rather than
  # falling through to whatever else claims them.
  textMimes = [
    "text/plain" "text/markdown" "text/csv" "text/x-log" "text/x-readme"
    "text/x-python" "text/x-shellscript" "text/x-c" "text/x-c++"
    "text/x-java" "text/x-lua" "text/x-nix" "text/x-rust" "text/x-go"
    "text/css" "text/javascript" "text/xml"
    "application/json" "application/x-shellscript" "application/toml"
    "application/x-yaml" "application/yaml" "application/xml"
    "application/x-zerosize"
  ];
in
{
  # ---- wallpaper -----------------------------------------------------------
  # The canonical copy lives in the repository (assets/wallpapers). Home
  # Manager materialises it at the path both compositors are pointed at.
  home.file.${wallpaperTarget}.source = wallpaper;

  # niri draws it with swaybg (see config/niri/config.kdl). COSMIC has its own
  # background daemon, configured here so the same image shows up in both
  # sessions. Schema is cosmic-bg's RON config; `same-on-all` makes the one
  # `all` entry cover every output.
  #
  # NOTE: the cosmic block makes COSMIC Settings > Wallpaper read-only (it
  # cannot write to a store symlink). Drop it if you would rather pick
  # wallpapers from the GUI.
  xdg.configFile = lib.mkMerge [
    # ---- live-editable configs --------------------------------------------
    (lib.genAttrs
      [ "nvim" "niri" "waybar" "rofi" "mako" "quickshell" "mpv" "rmpc" "fastfetch" ]
      (name: {
        source = liveLink "${dotfiles}/${name}/";
        recursive = true;
      }))

    {
      # ---- COSMIC background ----------------------------------------------
      # cosmic-bg's RON config; `same-on-all` makes the one `all` entry cover
      # every output.
      "cosmic/com.system76.CosmicBackground/v1/same-on-all".text = "true";
      "cosmic/com.system76.CosmicBackground/v1/all".text = ''
        (
            output: "all",
            source: Path("${wallpaperPath}"),
            filter_by_theme: true,
            rotation_frequency: 300,
            filter_method: Lanczos,
            scaling_mode: Zoom,
            sampling_method: Alphanumeric,
        )
      '';

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

  # ---- GTK theme -----------------------------------------------------------
  # adw-gtk3-dark: libadwaita's dark palette backported to GTK3, so GTK3 and
  # GTK4 apps look like one set instead of two. Papirus-Dark for icons.
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  # GTK4/libadwaita apps — Nautilus above all — hardcode their own stylesheet
  # and ignore gtk.theme entirely. What they *do* follow is this colour-scheme
  # preference, so without it Nautilus stays stubbornly light. The gtk-theme
  # key is the same value again for anything reading it out of dconf.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "adw-gtk3-dark";
  };

  # ---- default applications ------------------------------------------------
  xdg.mimeApps = {
    enable = true;
    defaultApplications = lib.mkMerge [
      {
        # Helium is the default browser (pkgs/helium.nix). Its .desktop is
        # named helium.desktop and ships the same MimeType= line Chromium
        # does, so these are the types it actually claims.
        "text/html" = [ "helium.desktop" ];
        "application/xhtml+xml" = [ "helium.desktop" ];
        "x-scheme-handler/http" = [ "helium.desktop" ];
        "x-scheme-handler/https" = [ "helium.desktop" ];
        "x-scheme-handler/about" = [ "helium.desktop" ];
        "x-scheme-handler/unknown" = [ "helium.desktop" ];
      }
      (assign "mpv.desktop" (audioMimes ++ videoMimes))
      (assign "imv.desktop" imageMimes)
      (assign "com.system76.CosmicEdit.desktop" textMimes)
    ];
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
