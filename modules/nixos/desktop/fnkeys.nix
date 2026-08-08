# Fn + F1…F12 — the media/system key row.
#
# The bindings themselves are in config/niri/config.kdl and all of them call
# `fnkey` (pkgs/fnkeys), which does the work and drives the quickshell OSD
# (config/quickshell/Osd.qml). This module only supplies what those need from
# the *system*: the tools, and I²C access for display brightness.
#
# Why I²C: these are desktop ultrawides, not a laptop panel. There is no
# /sys/class/backlight for them — their brightness is a DDC/CI register the GPU
# writes over the display cable's I²C lines. Reaching it needs the i2c-dev
# character devices, which is exactly what hardware.i2c.enable sets up: the
# module is loaded at boot and udev hands /dev/i2c-* to the `i2c` group.
{ config, pkgs, ... }:

{
  hardware.i2c.enable = true;

  # Without this the user gets EACCES on /dev/i2c-* and monitor-brightness
  # silently falls back to the (non-existent) internal backlight.
  users.users.${config.my.username}.extraGroups = [ "i2c" ];

  environment.systemPackages = with pkgs; [
    fnkey             # the dispatcher every Fn binding calls
    monitor-brightness # DDC/CI brightness for the external monitors
    ddcutil           # the underlying DDC/CI client, kept for debugging
    playerctl         # MPRIS transport for F7/F8/F9
  ];
}
