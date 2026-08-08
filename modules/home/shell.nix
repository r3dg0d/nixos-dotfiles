# Shells and the prompt: zsh as the login shell, starship themed to match the
# OLED-black / white / neon-green rice.
{ pkgs, ... }:

{
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

  # user-installed scripts
  home.sessionPath = [ "$HOME/.local/bin" "$HOME/Scripts" ];

  home.packages = with pkgs; [
    neovim
    ripgrep
    nil
    nixpkgs-fmt
    nodejs
    gcc
    fastfetch # ricey system info
  ];
}
