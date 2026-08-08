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

  environment.systemPackages = with pkgs; [
    easyeffects # PipeWire effects GUI — where the mic chain lives
    lsp-plugins # LV2 plugins EasyEffects hosts (expander, EQ, gain)
  ];
}
