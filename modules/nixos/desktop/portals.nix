# xdg-desktop-portal: screencasting, file pickers and the screenshot API for
# Wayland sessions.
{ pkgs, ... }:

{
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
    # NB: the COSMIC module adds xdg-desktop-portal-cosmic to extraPortals, so
    # the "*" fallback above is no longer unambiguous. Nothing to do here —
    # programs/wayland/niri.nix already sets xdg.portal.config.niri.default to
    # "gnome;gtk", and xdg-desktop-portal-cosmic ships its own
    # COSMIC-portals.conf, so each session keeps its own portal. Setting
    # config.niri.default here conflicts with niri.nix and fails the build.
  };

  # gvfs = trash / mounting / network shares for Nautilus
  services.gvfs.enable = true;

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };
}
