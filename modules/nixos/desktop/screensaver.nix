# Idle screensaver for the niri session.
#
# swayidle is the timer: it speaks ext-idle-notify-v1, so "no input" means what
# the compositor says it means — real keyboard and pointer activity — rather
# than something polled. After `timeout` seconds it starts the screensaver, and
# the *first* input event after that runs `resume`, which takes it away again.
#
# Two things come free with that protocol and are worth knowing:
#
#   * Apps that hold an idle inhibitor suppress the timeout, so a film is not
#     interrupted. This is swayidle's whole reason for being here rather than
#     hypridle, which can be told to ignore inhibitors.
#   * The resume event fires on the input that wakes the session, so the
#     keypress that dismisses the screensaver is swallowed by it rather than
#     landing in whatever window is underneath.
#
# The inhibitor behaviour is broader than "video", and that is worth knowing
# before wondering why the screensaver never appeared: Chromium-based browsers
# take the wake lock for *any* media playback, audio included. A browser tab
# quietly playing music holds the screensaver off exactly as a fullscreen film
# does. Nothing polls or guesses here — the compositor is asked, and it
# answers with whatever its clients have told it.
#
# The screensaver itself — the terminals, the animation, the logo — is
# pkgs/nixos-screensaver. This module only decides when it runs.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.screensaver;
in
{
  options.services.screensaver = {
    enable = lib.mkEnableOption "the niri idle screensaver" // { default = true; };

    package = lib.mkPackageOption pkgs "nixos-screensaver" { };

    timeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Seconds with no keyboard or pointer input before the screensaver
        starts. Idle inhibitors — fullscreen video, mostly — pause the count.
      '';
    };

    fontSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16;
      description = ''
        Terminal font size for the screensaver, which is what decides how much
        of the monitor the logo covers: it is a fixed 99x47 block of
        characters and nothing scales it.

        The failure mode is one-sided. Too small merely looks small; too large
        leaves the terminal with fewer than 47 rows, and the logo is cropped
        rather than shrunk. On a 1440px-tall panel 16 gives roughly 55 rows.
        Lower it for shorter monitors.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.screensaver = {
      description = "Idle screensaver (swayidle → nixos-screensaver)";

      # Wayland-only, and it needs WAYLAND_DISPLAY/NIRI_SOCKET, which
      # niri-session puts into the user manager's environment before this
      # target is reached.
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      startLimitIntervalSec = 300;
      startLimitBurst = 5;

      environment.NIXOS_SCREENSAVER_FONT_SIZE = toString cfg.fontSize;

      serviceConfig = {
        Type = "simple";

        # -w makes swayidle wait for each command to finish before carrying
        # on, so a slow start cannot overlap with the resume that cancels it.
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.swayidle}/bin/swayidle -w"
          "timeout ${toString cfg.timeout} '${lib.getExe cfg.package} start'"
          "resume '${lib.getExe cfg.package} stop'"
        ];

        # Whatever state it leaves behind, the screensaver should not outlive
        # the service.
        ExecStopPost = "${lib.getExe cfg.package} stop";

        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
      };
    };
  };
}
