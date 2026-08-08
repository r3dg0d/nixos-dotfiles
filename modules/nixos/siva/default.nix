# SIVA — the local voice-assistant stack.
#
# Architecture, as it actually works (see pkgs/siva/src/bin):
#
# This module holds the options the whole stack shares, and the system-level
# support it needs (the ydotoold socket, nix-ld for MemPalace's wheels, the
# tools on the interactive $PATH). The user services that supervise the
# daemons are added in the commits that follow.
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

    # Fail the build rather than the login if someone points SIVA at root.
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "services.siva.user must not be root — SIVA drives a user's graphical session.";
      }
    ];
  };
}
