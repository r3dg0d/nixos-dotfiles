# SDDM as the display manager, running the ascii-city theme.
#
# The theme is a Nix package (pkgs/sddm-ascii-city.nix) installed into
# systemPackages, which is what puts it under
# /run/current-system/sw/share/sddm/themes/ascii-city — the directory SDDM
# searches. Nothing is ever copied into /usr/share by hand.
#
# The greeter's session selector reads SDDM's own sessionModel, so every
# installed session (Niri, COSMIC, and anything added later) shows up with no
# further configuration: see modules/nixos/desktop/{niri,cosmic}.nix.
{ pkgs, ... }:

{
  # SDDM's Wayland greeter still wants the X server bits present for X11
  # sessions and for the keyboard-layout plumbing.
  services.xserver = {
    enable = true;
    autoRepeatDelay = 200;
    autoRepeatInterval = 35;
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "ascii-city"; # resolved from the sddm-ascii-city package below
  };

  environment.systemPackages = [ pkgs.sddm-ascii-city ];

  # The greeter's desktop switcher re-resolves the remembered session out of
  # /var/lib/sddm/state.conf (SDDM stores it as an absolute store path, which
  # every rebuild invalidates — see the comment in the theme's Main.qml). Qt 6
  # refuses XMLHttpRequest reads of local files unless this is set, and without
  # it the greeter would silently default to the alphabetically-first session
  # (COSMIC) instead of whichever desktop was last used.
  systemd.services.display-manager.environment.QML_XHR_ALLOW_FILE_READ = "1";

  # Qt caches compiled QML in ~/.cache/sddm-greeter-qt6/qmlcache and decides
  # the cache is still valid from the source file's *path* and *mtime*. SDDM
  # loads the theme through the stable /run/current-system/sw/share/... path,
  # and every file in the nix store has mtime=1 (1970-01-01) — so neither the
  # cache key nor the staleness check ever changes when the theme does. The
  # greeter then keeps replaying whatever QML was compiled the first time the
  # theme was installed, and no amount of rebuilding or logging out updates it.
  # (Qt does not compare file size either: a 14448 -> 19131 byte change was
  # still served from cache.) Disabling the disk cache costs one QML compile
  # per greeter start and is the only reliable fix short of renaming the theme
  # directory on every change.
  systemd.services.display-manager.environment.QML_DISABLE_DISK_CACHE = "1";
}
