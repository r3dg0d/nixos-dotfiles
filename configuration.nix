{ config, lib, pkgs, ... }:

let
  # Custom SDDM theme: animated ASCII rain over an ASCII city (see ./sddm-ascii-city).
  # The avatar is grayscaled at build time to match the monochrome look.
  sddm-ascii-city = pkgs.stdenvNoCC.mkDerivation {
    pname = "sddm-ascii-city";
    version = "1.0";
    src = ./sddm-ascii-city;
    nativeBuildInputs = [ pkgs.imagemagick ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/sddm/themes/ascii-city
      cp -r --no-preserve=mode . $out/share/sddm/themes/ascii-city/
      magick $src/pfp.png -colorspace Gray $out/share/sddm/themes/ascii-city/pfp.png
      runHook postInstall
    '';
  };

  # Hydra Launcher ships as an AppImage with its own bundled Electron, so it
  # never goes through the nixpkgs electron wrapper and ignores NIXOS_OZONE_WL.
  # Two things have to be fixed for it to work under niri:
  #
  #   1. --ozone-platform-hint=auto is NOT honoured by this Electron build; it
  #      silently picks X11 and runs through XWayland. Only the explicit
  #      --ozone-platform=wayland actually selects the Wayland backend.
  #   2. On Wayland the AppImage's *bundled* Mesa libEGL cannot drive the NVIDIA
  #      card ("pci id 10de:2684, driver (null)" -> "failed to create dri2
  #      screen"), the GPU process dies at init and the window paints solid
  #      white/black. GLVND has to be pointed at the NVIDIA ICD explicitly:
  #      pointing it at the whole egl_vendor.d dir is not enough, since Mesa's
  #      50_mesa.json still wins and fails the same way.
  #
  # The .desktop entry is repointed at the wrapper so rofi launches the wrapped
  # binary rather than the bare one.
  hydralauncher-wayland = pkgs.runCommand "hydralauncher-wayland-${pkgs.hydralauncher.version}"
    {
      nativeBuildInputs = [ pkgs.makeWrapper ];
      inherit (pkgs.hydralauncher) meta;
    }
    ''
      mkdir -p $out/bin $out/share/applications
      ln -s ${pkgs.hydralauncher}/share/icons $out/share/icons

      # --no-sandbox: the FHS/bubblewrap env the AppImage runs in cannot use
      # Electron's SUID sandbox (upstream's own .desktop passes it too).
      makeWrapper ${pkgs.hydralauncher}/bin/hydralauncher $out/bin/hydralauncher \
        --add-flags "--no-sandbox" \
        --run 'nvidia_icd=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json
               if [ -n "''${WAYLAND_DISPLAY-}" ]; then
                 set -- --ozone-platform=wayland \
                        --enable-features=WaylandWindowDecorations "$@"
                 [ -e "$nvidia_icd" ] && export __EGL_VENDOR_LIBRARY_FILENAMES="$nvidia_icd"
               fi'

      substitute ${pkgs.hydralauncher}/share/applications/hydralauncher.desktop \
        $out/share/applications/hydralauncher.desktop \
        --replace-fail '${pkgs.hydralauncher}/bin/hydralauncher --no-sandbox' \
                       "$out/bin/hydralauncher"
    '';

  quickshell-mirror = pkgs.symlinkJoin {
    name = "quickshell-mirror-${pkgs.quickshell.version}";
    paths = [ pkgs.quickshell ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f $out/bin/qs $out/bin/quickshell
      makeWrapper ${pkgs.quickshell}/bin/qs $out/bin/qs \
        --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${pkgs.qt6.qtmultimedia}/lib/qt-6/qml \
        --prefix QT_PLUGIN_PATH : ${pkgs.qt6.qtmultimedia}/lib/qt-6/plugins
      makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/quickshell \
        --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${pkgs.qt6.qtmultimedia}/lib/qt-6/qml \
        --prefix QT_PLUGIN_PATH : ${pkgs.qt6.qtmultimedia}/lib/qt-6/plugins
    '';
  };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos-btw"; # Define your hostname.

  # Ad-blocking encrypted Mullvad DNS
  services.resolved = {
	enable = true;

	settings.Resolve = {
	  DNSSEC = "false";
	  DNSOverTLS = "yes";
	  Domains = "~.";

	  # Mullvad's Extended Ad/Tracker/Malware/Social blocking servers
	  FallbackDNS = [
		"192.242.2.5#extended.dns.mullvad.net"
		"2a07:e340::5#extended.dns.mullvad.net"
	  ];
	};
  };

  # Prevent NetworkManager from overriding the resolved settings
  networking.networkmanager.dns = "systemd-resolved";  

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  networking.firewall.allowedTCPPorts = [ 34785 53317 ]; # 53317: LocalSend
  networking.firewall.allowedUDPPorts = [ 53317 ]; # LocalSend discovery

  # Blackholed hosts (written into /etc/hosts).
  networking.extraHosts = ''
    0.0.0.0 paradise-s1.battleye.com
    0.0.0.0 test-s1.battleye.com
    0.0.0.0 paradiseenhanced-s1.battleye.com
  '';

  time.timeZone = "America/Los_Angeles";

  services.xserver = {
    enable = true;
    autoRepeatDelay = 200;
    autoRepeatInterval = 35;
  };
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "ascii-city"; # found via sddm-ascii-city in systemPackages
  };

  # Login-screen music. The QML greeter can't play audio (no PipeWire/PulseAudio
  # exists for the pre-login `sddm` user, and Qt6 MediaPlayer has no ALSA
  # fallback), so instead we play sddmmusic.ogg straight to the sound card via
  # ALSA while the greeter is on screen, and stop the moment a session starts
  # (before the user's PipeWire grabs the device). Runs as root so it can open
  # the ALSA device without audio-group membership. Targets the Scarlett 2i2.
  systemd.services.sddm-login-music = {
    description = "Play login-screen music via ALSA while the SDDM greeter is shown";
    wantedBy = [ "multi-user.target" ];
    after = [ "sound.target" ];
    path = [ pkgs.procps pkgs.mpv ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      ogg=/run/current-system/sw/share/sddm/themes/ascii-city/sddmmusic.ogg
      dev="alsa/plughw:CARD=USB,DEV=0"   # Focusrite Scarlett 2i2 (card id "USB")
      mpvpid=""
      cleanup() { [ -n "$mpvpid" ] && kill "$mpvpid" 2>/dev/null || true; }
      trap cleanup EXIT
      while true; do
        # Match the greeter by process name (comm, truncated to 15 chars),
        # not cmdline — `pgrep -f` false-matches anything mentioning the string.
        if pgrep -x 'sddm-greeter-qt.?' >/dev/null 2>&1; then
          # greeter is on screen — ensure music is playing
          if [ -z "$mpvpid" ] || ! kill -0 "$mpvpid" 2>/dev/null; then
            mpv --no-video --no-terminal --really-quiet \
                --loop-file=inf --volume=60 \
                --audio-device="$dev" "$ogg" &
            mpvpid=$!
          fi
        else
          # logged in (or no greeter) — stop music, free the device
          if [ -n "$mpvpid" ] && kill -0 "$mpvpid" 2>/dev/null; then
            kill "$mpvpid" 2>/dev/null || true
          fi
          mpvpid=""
        fi
        # 1s poll: on login the greeter exits first, and we must release the
        # ALSA device before the user's PipeWire tries to claim it.
        sleep 1
      done
    '';
  };

  # NVIDIA proprietary driver (RTX 4090). Required for NVENC in OBS and
  # for the CUDA stack (ollama-cuda); nouveau has neither.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true; # required for 32-bit Steam games / Proton
  hardware.nvidia = {
    modesetting.enable = true; # required for Wayland (niri)
    open = true;               # open kernel module, recommended for RTX 40-series
    nvidiaSettings = true;
  };

  # Wayland / Niri
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };

  programs.niri.enable = true;
  security.polkit.enable = true;

  # SIVA voice assistant: uinput-level pointer control on Wayland
  programs.ydotool.enable = true;

  # SIVA durable memory (MemPalace): its onnxruntime/chromadb wheels are
  # generic dynamically-linked binaries, so nix-ld lets them run on NixOS.
  # Enables `uv tool install mempalace` (mempalace-mcp) to work.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc   # libstdc++/libgcc for onnxruntime
    zlib
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };
  
  nixpkgs.config.allowUnfree = true;

  # ratty 0.3.0 built arboard without its Wayland backend, so copy/paste
  # silently failed under niri (no X11 DISPLAY to fall back to). Fixed
  # upstream in v0.4.0; pin v0.5.0 until nixpkgs catches up.
  nixpkgs.overlays = [
    (final: prev: {
      ratty = prev.ratty.overrideAttrs (old: rec {
        version = "0.5.0";
        src = final.fetchFromGitHub {
          owner = "orhun";
          repo = "ratty";
          tag = "v${version}";
          hash = "sha256-gQ9qeR9IyPUCy4V2ynnnXeN15Fs7aNDEwjQ+33gonRU=";
        };
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          inherit src;
          name = "ratty-${version}-vendor";
          hash = "sha256-mSb7QCYQ4EL76S7wmSdHBkjE5wzbVK8ln6oPdAv5BuA=";
        };
      });

      # Lokinet: nixpkgs marks the package broken because its pinned release
      # doesn't compile against nixpkgs' newer system spdlog/fmt. Upstream's
      # intended from-source build uses the bundled oxen-logging submodules
      # instead, so build it that way.
      lokinet = prev.lokinet.overrideAttrs (old: {
        buildInputs = final.lib.filter (p: (p.pname or "") != "spdlog") old.buildInputs;
        cmakeFlags = old.cmakeFlags ++ [ "-DOXEN_LOGGING_FORCE_SUBMODULES=ON" ];
        postInstall = (old.postInstall or "") + ''
          # cmake links lokinet against the bundled spdlog but doesn't install it
          find . -name 'libspdlog.so*' -exec cp -av {} $out/lib/ \;
          patchelf --set-rpath "$out/lib" $out/lib/libspdlog.so.*.*.*
          # services.lokinet expects the mainnet bootstrap inside the package
          install -Dm644 ${final.fetchurl {
            url = "https://seed.lokinet.org/lokinet.signed";
            hash = "sha256-0SegVsdpGE3WQ8PbsDiO7tQLviYdCU3Eihd49yt8Lws=";
          }} $out/share/bootstrap.signed
        '';
        meta = old.meta // { broken = false; };
      });
    })
  ];


  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  services.pipewire = {
     enable = true;
     pulse.enable = true;
   };

  # "Deep eboy voice." — virtual mic: Scarlett 2i2 input 1 -> downward
  # expander (LSP, the ATKExpander role) -> low-shelf boost / high-shelf
  # cut (biquads, the BasiQ role) -> slight gain. Select it as the mic in
  # Discord/OBS/etc.
  services.pipewire.extraConfig.pipewire."99-deep-eboy-voice" = {
    "context.modules" = [
      {
        name = "libpipewire-module-filter-chain";
        args = {
          "node.description" = "Deep eboy voice.";
          "media.name" = "Deep eboy voice.";
          "filter.graph" = {
            nodes = [
              {
                type = "lv2";
                name = "expander";
                plugin = "http://lsp-plug.in/plugins/lv2/expander_mono";
                control = {
                  em = 0.0;    # downward mode (gate room noise)
                  al = 0.0631; # threshold ~ -24 dB
                  er = 3.0;    # 1:3 ratio below threshold
                };
              }
              {
                type = "builtin";
                name = "bass";
                label = "bq_lowshelf";
                control = { Freq = 130.0; Q = 0.7; Gain = 4.5; };
              }
              {
                type = "builtin";
                name = "treble";
                label = "bq_highshelf";
                control = { Freq = 9000.0; Q = 0.7; Gain = -2.0; };
              }
              {
                type = "builtin";
                name = "gain";
                label = "linear";
                control = { Mult = 1.25; }; # ~ +2 dB
              }
            ];
            links = [
              { output = "expander:out"; input = "bass:In"; }
              { output = "bass:Out"; input = "treble:In"; }
              { output = "treble:Out"; input = "gain:In"; }
            ];
            inputs = [ "expander:in" ];
            outputs = [ "gain:Out" ];
          };
          "capture.props" = {
            "node.name" = "capture.deep_eboy_voice";
            "node.passive" = true;
            "target.object" = "alsa_input.usb-Focusrite_Scarlett_2i2_USB_Y88R3D723DDED0-00.HiFi__Mic1__source";
            "audio.channels" = 1;
            "audio.position" = [ "MONO" ];
            "stream.dont-remix" = true;
          };
          "playback.props" = {
            "node.name" = "deep_eboy_voice";
            "media.class" = "Audio/Source";
            "audio.channels" = 1;
            "audio.position" = [ "MONO" ];
          };
        };
      }
    ];
  };

  # let the pipewire daemon find the LSP LV2 plugins for the filter-chain
  services.pipewire.extraLv2Packages = [ pkgs.lsp-plugins ];

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.r3dg0d = {
    isNormalUser = true;
    linger = true;  # start user services (mpd) at boot, not just on login
    # sudo + SIVA's ydotoold socket + libvirt (manage VMs without a polkit
    # prompt) + kvm (direct /dev/kvm access for non-libvirt qemu runs)
    extraGroups = [ "wheel" "ydotool" "libvirtd" "kvm" ];
    shell = pkgs.zsh;          # zsh as the login shell
    packages = with pkgs; [
      tree
    ];
  };

  programs.firefox.enable = true;

  # zsh must be enabled system-wide to be a valid login shell
  programs.zsh.enable = true;

  # gvfs = trash / mounting / network shares for Nautilus
  services.gvfs.enable = true;

  # Flatpak (installs the flatpak pkg + sets up the service; portals already enabled above)
  services.flatpak.enable = true;

  # Jellyfin media server — stream movies/TV from this PC to the TV.
  # openFirewall opens 8096 (web UI/API) + 8920 (HTTPS) TCP and UDP
  # 1900/7359 for DLNA + client auto-discovery on the LAN. The service runs
  # as its own `jellyfin` user; add it to the video/render groups so it can
  # reach the RTX 4090's /dev/nvidia* + /dev/dri nodes for NVENC hardware
  # transcoding (enable it under Dashboard > Playback once running).
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  users.users.jellyfin.extraGroups = [ "video" "render" ];

  # The media lives under ~/Videos, but /home/r3dg0d is mode 0700 so the
  # jellyfin user can't traverse into it. A POSIX ACL grants it the traverse
  # (+x) bit on the home dir only — the contents stay unreadable to everyone
  # else. This has to live in tmpfiles rather than a one-off `setfacl`: the
  # users activation snippet runs `chmod <homeMode> /home/r3dg0d` on *every*
  # `nixos-rebuild switch`, and chmod recalculates the ACL mask from the group
  # bits (0 here), silently reducing the named-user entry to `#effective:---`.
  # The explicit `m::x` re-establishes the mask; systemd-tmpfiles-resetup runs
  # after the activation scripts, so it undoes the damage each rebuild.
  systemd.tmpfiles.rules = [
    "a+ /home/r3dg0d - - - - u:jellyfin:x,m::x"
  ];

  # Mullvad VPN daemon (the mullvad-vpn package is the GUI/CLI; this runs the daemon)
  services.mullvad-vpn.enable = true;

  # WiVRn: OpenXR streaming to standalone VR headsets. The module installs the
  # dashboard/server, enables Avahi for headset discovery, and opens port 9757.
  services.wivrn = {
    enable = true;
    openFirewall = true;
    steam.importOXRRuntimes = true;
  };

  # SearXNG metasearch, localhost-only. Secret lives in /etc/searxng.env
  # (not in the repo / nix store); @SEARXNG_SECRET@ is substituted from it.
  services.searx = {
    enable = true;
    environmentFile = "/etc/searxng.env";
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        secret_key = "@SEARXNG_SECRET@";
      };
      search = {
        # feeds the omnibox suggest URL below
        autocomplete = "duckduckgo";
        # expose the JSON API too (default is html only) so SIVA's web_search
        # tool can consume results programmatically — localhost-only anyway
        formats = [ "html" "json" ];
      };
    };
  };

  # Managed policy read by ungoogled-chromium from /etc/chromium/policies:
  # makes the local SearXNG the default (omnibox) search engine.
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
    ];
  };

  # QEMU/KVM virtual machines, managed through libvirt and driven by
  # virt-manager's GUI. The libvirtd module already puts libvirt + the qemu
  # package into systemPackages (so qemu-img, virsh, etc. are on $PATH) and
  # loads the `tun` module, so nothing extra is needed for those.
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore";       # don't resume saved guests on boot, just leave them off
    onShutdown = "shutdown"; # ACPI-shutdown running guests instead of save-to-disk
    qemu = {
      # UEFI/OVMF firmware no longer needs to be wired up by hand — as of
      # 26.05 the module publishes every firmware image shipped with QEMU.
      swtpm.enable = true;                    # emulated TPM 2.0 (Windows 11 guests need it)
      vhostUserPackages = [ pkgs.virtiofsd ]; # virtiofs host<->guest shared folders
    };
  };

  # Redirect host USB devices into a guest from virt-manager's toolbar.
  virtualisation.spiceUSBRedirection.enable = true;

  # The virt-manager GUI. The module also seeds a dconf default so it
  # autoconnects to qemu:///system instead of asking on every launch.
  programs.virt-manager.enable = true;

  # libvirt ships a `default` NAT network (virbr0, 192.168.122.0/24, with
  # dnsmasq handing out DHCP) and libvirtd-config copies its XML into
  # /var/lib/libvirt on every rebuild — but nothing ever marks it autostart,
  # so out of the box every new VM fails with "Network not active". This
  # oneshot flips the autostart flag and brings it up after libvirtd, which
  # makes guest networking work from a cold boot with no manual `virsh`.
  # NOTE: NAT'd guests are reachable from the host, not from the LAN; for
  # LAN-visible guests make a bridge and add it to `allowedBridges`.
  systemd.services.libvirt-default-network = {
    description = "Start and autostart libvirt's default NAT network";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script =
      let
        virsh = "${config.virtualisation.libvirtd.package}/bin/virsh";
      in
      ''
        # Re-define from the package copy if a previous `net-undefine` removed it
        if ! ${virsh} net-info default > /dev/null 2>&1; then
          ${virsh} net-define ${config.virtualisation.libvirtd.package}/var/lib/libvirt/qemu/networks/default.xml
        fi
        ${virsh} net-autostart default
        # Already-running is not an error (e.g. on `nixos-rebuild switch`)
        ${virsh} net-info default | grep -q 'Active:.*yes' || ${virsh} net-start default
      '';
  };

   environment.systemPackages = with pkgs; [
     sddm-ascii-city # custom sddm theme (defined in the let-block above)
     vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
     wget
     git
     thunderbird # Gmail replacement
     etesync-dav # Degoogled calendar
     immich # Photos
     libretranslate # Google Translate replacement
     onlyoffice-desktopeditors # Google Docs replacement
     obsidian
     (pkgs.callPackage ./davinci-resolve.nix { }) # video editor 21.0.3 — vendored from creatorkostas/davinci-resolve-nixos, version-bumped
     ratty
     claude-code
     opencode
     alacritty
     monero-gui
     monero-cli
     vscodium # Coding IDE     
     bibata-cursors
     qbittorrent
     pcsx2 # PlayStation 2 emulator
     vesktop # Discord client (Vencord baked in)
     antigravity # Google vibe-coding IDE
     codex
     tor-browser
     areofyl-fetch # animated 3D `fetch` tool (github:areofyl/fetch, via flake overlay)
     tuiweb # TUI-only web browser: HTML/CSS/JS, images and video as characters (~/Projects/tuiweb, via flake overlay)
     mullvad-vpn
     rofi
     localsend
     docker
     wireshark
     wireshark-cli
     termshark
     freetube
     prismlauncher
     hydralauncher-wayland # Hydra game launcher (Electron + embedded bittorrent), Ozone-Wayland wrapped
     (pkgs.callPackage ./kyber-linuxport-unofficial.nix { })
     sqlmap # Cybersecurity tools (SQLi tool)
     smap # Nmap fork that uses shodan.io
     hashcat
     mpd # Music Player Daemon
     rmpc # Music player TUI
     easyeffects # PipeWire effects GUI
     lsp-plugins # LV2 plugins (expander for the deep eboy voice chain)
     ollama-cuda
     (llama-cpp.override { cudaSupport = true; })
     whisper-cpp # SIVA STT
     wtype # SIVA virtual keyboard
     piper-tts # SIVA voice output
     sox # SIVA wake-word enrollment (beep synth + 16k resample)
     socat # SIVA F7/F8/F9 toggle scripts talk to the daemon sockets
     tesseract # SIVA agentic OCR click-by-text (find on-screen text to click)
     waybar
     swaybg
     simplex-chat-desktop
     xwayland-satellite # X11 apps under niri (JVM apps like simplex-chat-desktop need XWayland)
     mako
     nautilus
     emojipick
     quickshell-mirror
     qt6.qtmultimedia
     qt6.qtdeclarative
     qt6.qtsvg
     v4l-utils
     shellcheck
     cliphist
     mpv
     file-roller
     gh
     grim
     slurp
     ungoogled-chromium
     keepassxc
     coyim
     irssi
     yt-dlp
     ffmpeg
     jellyfin-media-player # Jellyfin desktop client (native player, for this PC)
     gnupg
     tor
     imv
     

       # Secret project dependencies
       # python3 carries the SIVA wake-word deps (numpy/scipy/sklearn/onnxruntime)
       (python3.withPackages (ps: with ps; [ numpy scipy scikit-learn onnxruntime tqdm requests ]))
       openssl
       jq
       figlet
       toilet
       lolcat
   ];

  # Runs the daemon with CAP_NET_ADMIN/CAP_NET_BIND_SERVICE and puts the
  # lokinet CLI in systemPackages. DNS for .loki lives on 127.3.2.1.
  services.lokinet.enable = true;
  services.lokinet.settings.network.keyfile = "identity.key";

  # Route .loki/.snode lookups to lokinet's DNS so they resolve system-wide
  # (browsers included). Lokinet tries to register this itself via
  # SetLinkDNS but the hardened DynamicUser service can't talk to resolved,
  # so do it from a privileged ("+") hook once lokitun0 exists. Per-link
  # DoT/DNSSEC off: the global Mullvad settings would break plain DNS
  # to 127.3.2.1, and the ~loki routing domain wins over global "~.".
  systemd.services.lokinet.serviceConfig.ExecStartPost =
    "+" + pkgs.writeShellScript "lokinet-register-dns" ''
      for _ in $(seq 1 60); do
        ${pkgs.systemd}/bin/resolvectl dns lokitun0 127.3.2.1 2>/dev/null && break
        sleep 0.5
      done
      ${pkgs.systemd}/bin/resolvectl domain lokitun0 '~loki' '~snode'
      ${pkgs.systemd}/bin/resolvectl dnsovertls lokitun0 no
      ${pkgs.systemd}/bin/resolvectl dnssec lokitun0 no
    '';

  # gpg-agent + a pinentry so gpg can prompt for passphrases
  # (fixes "no pinentry"). curses = prompts inside the terminal.
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  fonts.packages = with pkgs; [
	nerd-fonts.jetbrains-mono
	nerd-fonts.symbols-only
  ];

  # Never suspend on its own. The Pulsar PCMK 2 HE keyboard's "System Control"
  # HID interface (event9) spuriously emits KEY_POWER after a stretch of no
  # input, and logind turned that into a suspend -- every single sleep in the
  # journal is "Power key pressed short." followed by "The system will suspend
  # now!", never an idle timeout. It fires again the moment the keyboard
  # re-enumerates on resume, so the machine used to drop straight back to sleep.
  # Suspend is now only reachable deliberately, via the quickshell power widget
  # (`systemctl suspend`, see config/quickshell/Power.qml).
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";            # the bogus event; short press does nothing
    HandlePowerKeyLongPress = "poweroff"; # holding the real case button still works
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
    HandleHibernateKey = "ignore";
    HandleHibernateKeyLongPress = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction = "ignore";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05";

}
