# SIVA-Type — AI-enhanced voice dictation.
#
# siva-type-daemon owns /tmp/siva-type.sock, records through pw-record,
# transcribes with whisper-cli, has the same local llama-server rewrite the
# draft in the selected persona, and types the result into whatever surface is
# focused.
#
# The typing step is the only part with a platform constraint, and it is
# Wayland-native, not X11:
#
#   * `wtype` uses the zwp_virtual_keyboard_v1 protocol, which niri implements.
#     This is the normal path and needs no privileges at all.
#   * `ydotool` is the uinput fallback for surfaces that refuse virtual-keyboard
#     input. It needs write access to /dev/uinput, which `programs.ydotool`
#     (enabled in modules/nixos/siva/default.nix) provides through a *system*
#     ydotoold socket group-owned by `ydotool` — the user is in that group, so
#     nothing here runs as root and no blanket /dev/uinput permission is
#     granted to every process on the machine.
#
# There is no X11 assumption anywhere in the stack; XWayland is not required.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.siva.type;
  sivaCfg = config.services.siva;
in
{
  options.services.siva.type = {
    enable = lib.mkEnableOption "SIVA-Type" // { default = true; };
    package = lib.mkPackageOption pkgs "siva-type" { };
  };

  config = lib.mkIf (sivaCfg.enable && cfg.enable) {
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.siva-type = {
      description = "SIVA-Type daemon (AI voice dictation)";
      documentation = [ "https://github.com/r3dg0d/siva-type" ];
      after = [ "graphical-session.target" "siva-llama-server.service" ];
      wants = [ "siva-llama-server.service" ];
      startLimitIntervalSec = 300;
      startLimitBurst = 5;
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        YDOTOOL_SOCKET = "/run/ydotoold/socket";
      } // sivaCfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/siva-type-daemon";
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
