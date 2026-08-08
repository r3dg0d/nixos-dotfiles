# Everything portable about this workstation. A host imports this module set
# plus its own hardware-configuration.nix and whatever is genuinely
# machine-specific (see hosts/<name>/default.nix).
{ ... }:

{
  imports = [
    ./options.nix
    ./core.nix
    ./kernel.nix
    ./updater.nix
    ./networking.nix
    ./audio.nix
    ./hardware/nvidia.nix
    ./desktop/sddm.nix
    ./desktop/niri.nix
    ./desktop/fnkeys.nix
    ./desktop/cosmic.nix
    ./desktop/portals.nix
    ./desktop/apps.nix
    ./programs.nix
    ./services.nix
    ./virtualisation.nix
    ./development.nix
    ./siva
  ];
}
