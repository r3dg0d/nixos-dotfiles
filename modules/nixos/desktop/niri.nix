# Niri — the primary session. `programs.niri.enable` installs the compositor
# and registers /run/current-system/sw/share/wayland-sessions/niri.desktop,
# which is how it reaches the SDDM session list.
#
# The compositor's own configuration is KDL, not Nix: config/niri/config.kdl,
# symlinked into place by Home Manager so it stays hot-reloadable.
{ pkgs, ... }:

{
  programs.niri.enable = true;

  environment.systemPackages = with pkgs; [
    waybar
    swaybg
    mako
    rofi
    cliphist
    grim
    slurp
    emojipick
    quickshell-mirror
    # Quickshell widgets import these directly.
    qt6.qtmultimedia
    qt6.qtdeclarative
    qt6.qtsvg
    # X11 apps under niri (JVM apps like simplex-chat-desktop need XWayland)
    xwayland-satellite
  ];
}
