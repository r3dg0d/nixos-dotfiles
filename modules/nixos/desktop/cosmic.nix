# COSMIC desktop, installed alongside niri rather than replacing it.
#
# Both register a Wayland session with SDDM (niri.desktop / cosmic.desktop) and
# the ascii-city greeter's `desk >` row picks between them, so this is purely
# additive: enabling COSMIC does not change which compositor logs in by
# default, only which ones are offered.
#
# SDDM stays the display manager. `services.desktopManager.cosmic` ships
# cosmic-greeter as a *package* (COSMIC's screen locker needs it) but does not
# enable it as the greeter, which is why cosmic-greeter is left disabled below
# rather than merely unmentioned.
{ lib, ... }:

{
  services.desktopManager.cosmic.enable = true;

  # Be explicit: if a future nixpkgs makes the COSMIC module opt *out* of SDDM
  # by turning its own greeter on, this keeps ascii-city as the login screen
  # instead of silently swapping it. mkDefault so a host can still choose it.
  services.displayManager.cosmic-greeter.enable = lib.mkDefault false;
}
