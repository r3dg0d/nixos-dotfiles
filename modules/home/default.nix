# Home Manager configuration for the primary user.
#
# Imported from the flake as a NixOS-module Home Manager user, so `osConfig`
# is the surrounding NixOS configuration — which is where the username, home
# directory and checkout location come from. Nothing here hardcodes a path
# under /home.
{ osConfig, ... }:

{
  imports = [
    ./shell.nix
    ./desktop.nix
    ./services.nix
  ];

  home.username = osConfig.my.username;
  home.homeDirectory = osConfig.my.homeDirectory;
  home.stateVersion = "26.05";

  programs.git.enable = true;
}
