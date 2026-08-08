# A tiny amount of shared vocabulary so no module has to hardcode a username
# or a /home path. Everything else that varies per machine lives in
# hosts/<name>/default.nix.
{ lib, config, ... }:

let
  cfg = config.my;
in
{
  options.my = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "r3dg0d";
      description = ''
        The primary interactive user. Their account, groups, shell and Home
        Manager configuration are all derived from this, so pointing it at a
        different name is enough to move the whole desktop to another login.
      '';
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.username}";
      defaultText = lib.literalExpression ''"/home/''${config.my.username}"'';
      description = "Home directory of the primary user.";
    };

    dotfilesDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.homeDirectory}/nixos-dotfiles";
      defaultText = lib.literalExpression ''"''${config.my.homeDirectory}/nixos-dotfiles"'';
      description = ''
        Where this repository is checked out on the running machine.

        Only used for the live-editable config symlinks Home Manager creates
        (config/niri, config/waybar, …) so that editing a dotfile takes effect
        without a rebuild. Nothing in the *system* closure depends on it, so a
        machine whose checkout lives elsewhere still boots and logs in fine —
        it just loses the edit-without-rebuild convenience until this is set.
      '';
    };
  };
}
