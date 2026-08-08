# SIVA — the local voice-assistant stack.
#
# Architecture, as it actually works (see pkgs/siva/src/bin):
#
#   siva-daemon              long-lived orchestrator. Owns /tmp/siva.sock and
#                            speaks newline-JSON to the Quickshell overlay
#                            (config/quickshell/Siva.qml). Captures audio with
#                            pw-record, transcribes with whisper-cli, talks to
#                            llama-server over HTTP on 127.0.0.1:8090, acts on
#                            the desktop through niri msg / ydotool / wtype /
#                            grim / tesseract, and speaks through piper.
#   siva-wake                always-on "Siva" wake-word listener. On a
#                            confirmed detection it sends {"type":"toggle"} to
#                            siva-daemon's socket — exactly like pressing F8.
#   siva                     the F8 toggle script. Talks to the socket; starts
#                            the daemon itself if it is not running.
#   siva-enroll              wake-word enrollment wizard (trains verifier.pkl).
#
# So the daemons are the things worth supervising, and the toggle scripts are
# just clients. That is exactly how the units below are shaped: one user
# service per daemon, nothing invented around the client scripts.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.siva;
  home = config.users.users.${cfg.user}.home;
in
{
  imports = [
    ./llama-server.nix
  ];

  options.services.siva = {
    enable = lib.mkEnableOption "the SIVA voice assistant" // { default = true; };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.my.username;
      defaultText = lib.literalExpression "config.my.username";
      description = "User whose graphical session SIVA runs in. Never root.";
    };

    package = lib.mkPackageOption pkgs "siva" { };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/share/siva";
      defaultText = lib.literalExpression ''"''${home}/.local/share/siva"'';
      description = ''
        Where SIVA keeps its runtime assets: the whisper model, the piper
        voice, the openWakeWord wheel and models, downloaded RVC voices and
        the persisted microphone choice. Populated by `siva-fetch-assets`;
        deliberately not in the nix store, since it is multi-gigabyte
        user data that changes independently of the system.
      '';
    };

    wake.enable = lib.mkEnableOption "the always-on \"Siva\" wake-word listener" // {
      default = true;
    };

    searxngUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8888";
      description = ''
        SearXNG instance backing SIVA's `web_search` tool. Localhost by
        default — see modules/nixos/services.nix, which runs one bound to
        127.0.0.1 only.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { SIVA_VAD_ENDSIL = "0.9"; };
      description = "Extra environment variables for every SIVA user service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.siva-fetch-assets
      # The daemons shell out to these; they are on the wrapped PATH already,
      # but having them in the system profile keeps manual debugging sane.
      pkgs.whisper-cpp # SIVA STT
      pkgs.piper-tts # SIVA voice output
      pkgs.wtype # SIVA virtual keyboard
      pkgs.sox # SIVA wake-word enrollment (beep synth + 16k resample)
      pkgs.socat # SIVA F7/F8/F9 toggle scripts talk to the daemon sockets
      pkgs.tesseract # SIVA agentic OCR click-by-text (find on-screen text to click)
      # The wake-word stack, on the interactive $PATH as well as inside the
      # siva package's wrapper — this is what makes hand-running siva-wake or
      # poking at openWakeWord in a REPL work.
      (pkgs.python3.withPackages (ps: with ps; [
        numpy
        scipy
        scikit-learn
        onnxruntime
        tqdm
        requests
      ]))
    ];

    # uinput-level pointer control on Wayland. The module creates the
    # `ydotool` group and a ydotoold socket at /run/ydotoold/socket; the user
    # is added to that group in modules/nixos/core.nix, which is what makes
    # this work *without* running anything as root.
    programs.ydotool.enable = true;

    # SIVA durable memory (MemPalace): its onnxruntime/chromadb wheels are
    # generic dynamically-linked binaries, so nix-ld lets them run on NixOS.
    # Enables `uv tool install mempalace` (mempalace-mcp) to work.
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      stdenv.cc.cc # libstdc++/libgcc for onnxruntime
      zlib
    ];

    systemd.user.services.siva = {
      description = "SIVA voice assistant daemon";
      documentation = [ "https://github.com/r3dg0d/siva" ];
      # Wayland, PipeWire and the ydotoold socket all have to exist first, so
      # this is a graphical-session service rather than a default.target one.
      # Both niri (`niri --session`) and cosmic-session import the session
      # environment into systemd and pull up graphical-session.target, so the
      # unit sees WAYLAND_DISPLAY / XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS
      # without any of them being hardcoded here.
      after = [ "graphical-session.target" "siva-llama-server.service" ];
      wants = [ "siva-llama-server.service" ];
      # A crash loop here is usually a missing model or a dead llama-server,
      # neither of which fixes itself quickly — back off rather than spin.
      # (These belong in [Unit]; systemd silently ignores them in [Service].)
      startLimitIntervalSec = 300;
      startLimitBurst = 5;
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        SIVA_SEARXNG = cfg.searxngUrl;
        SIVA_LLAMA_CTX = toString config.services.siva.llama.contextSize;
        YDOTOOL_SOCKET = "/run/ydotoold/socket";
      } // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/siva-daemon";
        Restart = "on-failure";
        RestartSec = 3;
        # A crash loop here is usually a missing model or a dead llama-server,
        # neither of which fixes itself quickly — back off rather than spin.

        # Hardening. Kept deliberately mild: SIVA's entire job is to look at
        # and drive the desktop, so it needs /tmp (its own socket lives at
        # /tmp/siva.sock and the overlay connects to it), the Wayland socket,
        # PipeWire, /dev/uinput via ydotoold, and the GPU nodes. What is left
        # is still worth having.
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectClock = true;
      };
    };

    systemd.user.services.siva-wake = lib.mkIf cfg.wake.enable {
      description = "SIVA wake-word listener (\"Siva\")";
      documentation = [ "https://github.com/r3dg0d/siva" ];
      # Nothing to toggle until the daemon owns its socket.
      after = [ "graphical-session.target" "siva.service" ];
      requires = [ "siva.service" ];
      startLimitIntervalSec = 300;
      startLimitBurst = 5;
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      environment = cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/siva-wake";
        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectClock = true;
      };
    };

    # Fail the build rather than the login if someone points SIVA at root.
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "services.siva.user must not be root — SIVA drives a user's graphical session.";
      }
    ];
  };
}
