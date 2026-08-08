# SIVA-Voicefetch — the RVC voice-model downloader.
#
# siva-voicefetch-daemon owns /tmp/siva-voicefetch.sock and drives the
# Quickshell overlay (config/quickshell/SivaVoicefetch.qml). It searches
# voice-models.com, downloads and unpacks RVC v2 models into
# ~/.local/share/siva/voices, and publishes the chosen voice to
# ~/.local/share/siva/voice.json — which is the single file siva-daemon reads
# to decide whether to speak through RVC or plain piper. That file is the
# entire integration surface between the two, so nothing else has to be wired
# up for them to talk.
#
# Audio device selection is *not* configured here: the daemon (and siva-daemon,
# with which it shares ~/.local/share/siva/mic.json) enumerates inputs through
# wpctl at runtime, so plugging in a different interface just works.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.siva.voicefetch;
  sivaCfg = config.services.siva;
in
{
  options.services.siva.voicefetch = {
    enable = lib.mkEnableOption "SIVA-Voicefetch" // { default = true; };
    package = lib.mkPackageOption pkgs "siva-voicefetch" { };
  };

  config = lib.mkIf (sivaCfg.enable && cfg.enable) {
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.siva-voicefetch = {
      description = "SIVA-Voicefetch daemon (RVC voice-model downloader)";
      documentation = [ "https://github.com/r3dg0d/siva-voicefetch" ];
      # Needs the graphical session for its overlay and PipeWire for previews.
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      startLimitIntervalSec = 300;
      startLimitBurst = 5;
      wantedBy = [ "graphical-session.target" ];

      environment = sivaCfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/siva-voicefetch-daemon";
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
  };
}
