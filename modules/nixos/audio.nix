# PipeWire (with WirePlumber, which the NixOS module enables by default) as the
# only sound server. The PulseAudio compatibility layer is what most desktop
# apps — and SIVA's pw-record/pw-play calls — actually talk to.
#
# Filter chains that name a specific capture device are machine-specific and
# live in the host module.
{ pkgs, ... }:

{
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    # WirePlumber is the session manager; SIVA uses its `wpctl` to enumerate
    # microphones and to duck desktop audio while it is listening.
    wireplumber.enable = true;
  };

  # let the pipewire daemon find the LSP LV2 plugins used by the host's
  # filter-chain definitions
  services.pipewire.extraLv2Packages = [ pkgs.lsp-plugins ];

  environment.systemPackages = with pkgs; [
    easyeffects # PipeWire effects GUI
    lsp-plugins # LV2 plugins (expander for the deep eboy voice chain)
  ];
}
