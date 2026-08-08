# The update stack: `nixos-update` / `nixos-update-check`, the timer that keeps
# their answer fresh, and the waybar widget that displays it.
#
# The commands themselves live in pkgs/nixos-updater; this module is only the
# wiring — where the flake is, which host to build, whether the mainline kernel
# pin is even relevant, and which signal wakes the bar.
{ config, lib, pkgs, ... }:

let
  cfg = config.my.updater;

  commands = [ "nixos-update" "nixos-update-check" "nixos-update-waybar" "nixos-kernel-pin" ];

  # The scripts read their configuration from the environment so they stay
  # usable standalone (`NIXOS_UPDATER_FLAKE=/some/checkout nixos-update-check`).
  # Baking the defaults into a wrapper is what makes them Just Work from a
  # shell, from waybar, and from the timer alike — --set-default, so an explicit
  # variable in the caller's environment still wins.
  env = {
    NIXOS_UPDATER_FLAKE = config.my.dotfilesDir;
    NIXOS_UPDATER_HOST = config.networking.hostName;
    NIXOS_UPDATER_KERNEL = if config.my.kernel.mainline.enable then "1" else "0";
    NIXOS_UPDATER_WAYBAR_SIGNAL = toString cfg.waybarSignal;
  };

  updater = pkgs.symlinkJoin {
    name = "nixos-updater-${pkgs.nixos-updater.version}-configured";
    paths = [ pkgs.nixos-updater ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for cmd in ${lib.concatStringsSep " " commands}; do
        wrapProgram $out/bin/$cmd \
          ${lib.concatStringsSep " \\\n          "
            (lib.mapAttrsToList (k: v: "--set-default ${k} ${lib.escapeShellArg v}") env)}
      done
    '';
  };

  checkFlags = lib.optionalString (!config.my.kernel.mainline.trackRC) " --no-rc";
in
{
  options.my.updater = {
    enable = lib.mkEnableOption "the nixos-update tool set" // { default = true; };

    autoCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the update check on a timer, so the waybar widget has a fresh
        answer without anyone asking for one. Only ever *checks* — nothing is
        downloaded, built, or activated without `nixos-update`.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      example = "1d";
      description = ''
        How often the check runs, as a systemd time span. It resolves every
        flake input against upstream, which is real network traffic — an hour
        is the sensible floor.
      '';
    };

    waybarSignal = lib.mkOption {
      type = lib.types.ints.between 1 30;
      default = 13;
      description = ''
        Real-time signal the check sends to waybar when it finishes, so the bar
        refreshes immediately instead of on its next poll. Must match the
        `signal` field of the custom/nixupdate module in
        config/waybar/config.jsonc. 10-12 are already taken by the music and
        mirror widgets.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ updater ];

    # A user unit, not a system one: the status cache lives in the user's
    # XDG_CACHE_HOME, the nix profile it inspects is the user's, and signalling
    # waybar means signalling a process in the user's session.
    systemd.user.services.nixos-update-check = lib.mkIf cfg.autoCheck {
      description = "Check for NixOS, flatpak, kernel and firmware updates";
      # Nothing here is urgent, and all of it is either network- or disk-bound;
      # losing the race against a login is better than slowing one down.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${updater}/bin/nixos-update-check --quiet${checkFlags}";
        Nice = 15;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.nixos-update-check = lib.mkIf cfg.autoCheck {
      description = "Periodic update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "3min"; # let the session settle before hitting the network
        OnUnitActiveSec = cfg.interval;
        Persistent = true; # catch up after the machine was off
        RandomizedDelaySec = "5min";
      };
    };
  };
}
