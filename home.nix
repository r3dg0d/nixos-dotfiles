{ config, pkgs, ... }:
let
  dotfiles = "${config.home.homeDirectory}/nixos-dotfiles/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;
in


{
    home.username = "r3dg0d";
    home.homeDirectory = "/home/r3dg0d";
    programs.git.enable = true;
    home.stateVersion = "26.05";

    programs.bash = {
	    enable = true;
	    shellAliases = {
		    btw = "echo I use nixos, btw";
	    };
    };

    # zsh with autocomplete + syntax highlighting + autosuggestions
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting = {
        enable = true;
        highlighters = [ "main" "brackets" ];
      };
      history = {
        size = 50000;
        save = 50000;
        ignoreDups = true;
        share = true;
      };
      shellAliases = {
        btw = "echo I use nixos, btw";
        ll = "ls -lah --color=auto";
        ls = "ls --color=auto";
        grep = "grep --color=auto";
        ff = "fastfetch";
      };
      initContent = ''
        # let gpg's terminal pinentry attach to this tty
        export GPG_TTY="$(tty)"

        # neon-green autosuggestion + syntax highlight tuning
        ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
        typeset -gA ZSH_HIGHLIGHT_STYLES
        ZSH_HIGHLIGHT_STYLES[command]="fg=#00ff41,bold"
        ZSH_HIGHLIGHT_STYLES[builtin]="fg=#00ff41"
        ZSH_HIGHLIGHT_STYLES[alias]="fg=#39ff14"
        ZSH_HIGHLIGHT_STYLES[path]="fg=#ffffff,underline"
        ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=#ff2b2b,bold"
      '';
    };

    # starship prompt themed OLED-black / white / neon-green
    programs.starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        format = "[](#00ff41)$username$hostname$directory$git_branch$git_status$cmd_duration$character";
        username = {
          show_always = true;
          style_user = "bg:#00ff41 fg:#000000 bold";
          style_root = "bg:#ff2b2b fg:#000000 bold";
          format = "[ $user ]($style)";
        };
        hostname = {
          ssh_only = false;
          style = "bg:#0a0a0a fg:#00ff41 bold";
          format = "[@$hostname ]($style)";
        };
        directory = {
          style = "fg:#ffffff bold";
          format = "[  $path ]($style)";
          truncation_length = 4;
        };
        git_branch = {
          symbol = " ";
          style = "fg:#39ff14";
          format = "[$symbol$branch ]($style)";
        };
        git_status = {
          style = "fg:#ff2b2b";
          format = "[$all_status$ahead_behind ]($style)";
        };
        cmd_duration = {
          min_time = 500;
          style = "fg:#666666";
          format = "[ $duration ]($style)";
        };
        character = {
          success_symbol = "[](fg:#00ff41)";
          error_symbol = "[](fg:#ff2b2b)";
        };
      };
    };

    home.sessionVariables = {
      TERMINAL = "ratty";
    };

    # user-installed scripts (SIVA stack lives here)
    home.sessionPath = [ "$HOME/.local/bin" "$HOME/Scripts" ];

    # SIVA's llama.cpp backend as a user service so a CUDA-OOM crash
    # self-heals (Restart=on-failure) instead of leaving the assistant
    # throwing ConnectionRefused until the next reboot. It only needs the
    # GPU + localhost, no Wayland, so it can start with the user session.
    systemd.user.services.siva-llm = {
      Unit = {
        Description = "SIVA LLM backend (llama.cpp, gemma-4-31B + vision)";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${config.home.homeDirectory}/.local/bin/siva-llm";
        Restart = "on-failure";
        RestartSec = 5;
        # give a crashed CUDA context a moment to be reclaimed before retry
        StartLimitIntervalSec = 0;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # DaVinci Resolve and the SIVA LLM both want the 4090's VRAM, and Resolve
    # OOMs when llama.cpp is holding gemma-4-31B. This watcher stops siva-llm
    # while a `resolve` process is alive and restarts it once Resolve quits —
    # but only if *it* stopped the service (so a manual stop stays stopped).
    systemd.user.services.davinci-llm-pause = {
      Unit = {
        Description = "Pause SIVA LLM (free VRAM) while DaVinci Resolve runs";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = pkgs.writeShellScript "davinci-llm-pause" ''
          set -u
          pgrep="${pkgs.procps}/bin/pgrep"
          systemctl="${pkgs.systemd}/bin/systemctl"
          paused_by_us=0
          while true; do
            if "$pgrep" -x resolve >/dev/null 2>&1; then
              if "$systemctl" --user is-active --quiet siva-llm.service; then
                echo "DaVinci Resolve detected — stopping siva-llm to free VRAM"
                "$systemctl" --user stop siva-llm.service && paused_by_us=1
              fi
            elif [ "$paused_by_us" = 1 ]; then
              echo "DaVinci Resolve closed — restarting siva-llm"
              "$systemctl" --user start siva-llm.service
              paused_by_us=0
            fi
            sleep 5
          done
        '';
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };

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

    # Bibata Modern Classic cursor (gtk + x11 themes, XCURSOR_* env vars)
    home.pointerCursor = {
      gtk.enable = true;
      x11.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    xdg.configFile."nvim" = {
      source = create_symlink "${dotfiles}/nvim/";
      recursive = true;
    };
    xdg.configFile."niri" = {
      source = create_symlink "${dotfiles}/niri/";
      recursive = true;
    };
    xdg.configFile."ratty" = {
      source = create_symlink "${dotfiles}/ratty/";
      recursive = true;
    };
    xdg.configFile."waybar" = {
      source = create_symlink "${dotfiles}/waybar/";
      recursive = true;
    };
    xdg.configFile."rofi" = {
      source = create_symlink "${dotfiles}/rofi/";
      recursive = true;
    };
    xdg.configFile."mako" = {
      source = create_symlink "${dotfiles}/mako/";
      recursive = true;
    };
    xdg.configFile."quickshell" = {
      source = create_symlink "${dotfiles}/quickshell/";
      recursive = true;
    };
    xdg.configFile."mpv" = {
      source = create_symlink "${dotfiles}/mpv/";
      recursive = true;
    };
    xdg.configFile."rmpc" = {
      source = create_symlink "${dotfiles}/rmpc/";
      recursive = true;
    };
    xdg.configFile."fastfetch" = {
      source = create_symlink "${dotfiles}/fastfetch/";
      recursive = true;
    };

    # Hide these apps from the rofi drun launcher without uninstalling them.
    # Each entry shadows the package-provided .desktop (matched by filename, so
    # attr name/case must match) with NoDisplay=true. rmpc is a TUI kept for the
    # mpd setup; alacritty/firefox/dualcpy are just decluttered from the menu.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = [ "chromium-browser.desktop" ];
        "application/xhtml+xml" = [ "chromium-browser.desktop" ];
        "x-scheme-handler/http" = [ "chromium-browser.desktop" ];
        "x-scheme-handler/https" = [ "chromium-browser.desktop" ];
        "x-scheme-handler/about" = [ "chromium-browser.desktop" ];
        "x-scheme-handler/unknown" = [ "chromium-browser.desktop" ];
      };
    };

    xdg.desktopEntries = {
      rmpc      = { name = "rmpc";      noDisplay = true; };
      firefox   = { name = "firefox";   noDisplay = true; };
      Alacritty = { name = "Alacritty"; noDisplay = true; };
      dualcpy   = { name = "dualcpy";   noDisplay = true; };
    };

    home.packages = with pkgs; [
	neovim
	ripgrep
	nil
	nixpkgs-fmt
	nodejs
	gcc
	# rice runtime bits
	swaybg          # wallpaper
	mako            # notification daemon
	libnotify       # notify-send for testing notifications
	nautilus        # file manager
	wl-clipboard    # clipboard for wayland
	brightnessctl   # backlight keys
	pavucontrol     # audio control (waybar click)
	fastfetch       # ricey system info
    ];
}
