# User services owned by Home Manager.
#
# The SIVA stack's own units are NOT here — they are declared by the NixOS
# modules under modules/nixos/siva, so that a machine gets a working assistant
# from `nixos-rebuild switch` alone. What is left is mpd and the one bit of
# cross-application arbitration that only makes sense for this user.
{ config, pkgs, ... }:

{
  # mpd — indexes ~/Music recursively; rmpc connects to it on localhost:6600
  services.mpd = {
    enable = true;
    musicDirectory = "${config.home.homeDirectory}/Music";
    extraConfig = ''
      auto_update "yes"

      audio_output {
        type "pipewire"
        name "PipeWire Output"
      }
    '';
  };

  # ~/.config/mpd/mpd.conf for manual `mpd` invocations — mirrors the
  # service config above (same db/state paths) so they stay in sync
  xdg.configFile."mpd/mpd.conf".text = ''
    music_directory     "${config.home.homeDirectory}/Music"
    playlist_directory  "${config.home.homeDirectory}/.local/share/mpd/playlists"
    db_file             "${config.home.homeDirectory}/.local/share/mpd/mpd.db"
    state_file          "${config.home.homeDirectory}/.local/share/mpd/state"
    sticker_file        "${config.home.homeDirectory}/.local/share/mpd/sticker.sql"
    auto_update         "yes"

    audio_output {
      type "pipewire"
      name "PipeWire Output"
    }
  '';

  # DaVinci Resolve and the SIVA LLM both want the GPU's VRAM, and Resolve
  # OOMs when llama.cpp is holding the model. This watcher stops the llama
  # server while a `resolve` process is alive and restarts it once Resolve
  # quits — but only if *it* stopped the service (so a manual stop stays
  # stopped).
  systemd.user.services.davinci-llm-pause = {
    Unit = {
      Description = "Pause the SIVA LLM (free VRAM) while DaVinci Resolve runs";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "davinci-llm-pause" ''
        set -u
        pgrep="${pkgs.procps}/bin/pgrep"
        systemctl="${pkgs.systemd}/bin/systemctl"
        unit=siva-llama-server.service
        paused_by_us=0
        while true; do
          if "$pgrep" -x resolve >/dev/null 2>&1; then
            if "$systemctl" --user is-active --quiet "$unit"; then
              echo "DaVinci Resolve detected — stopping $unit to free VRAM"
              "$systemctl" --user stop "$unit" && paused_by_us=1
            fi
          elif [ "$paused_by_us" = 1 ]; then
            echo "DaVinci Resolve closed — restarting $unit"
            "$systemctl" --user start "$unit"
            paused_by_us=0
          fi
          sleep 5
        done
      '';
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
