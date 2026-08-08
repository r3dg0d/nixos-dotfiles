# NVIDIA proprietary driver. The parts that depend on which card is actually
# fitted (`open`, power management, PRIME offload) stay overridable — this
# module only sets what every NVIDIA machine in this config needs.
{ lib, config, ... }:

{
  options.my.nvidia.enable = lib.mkEnableOption "the NVIDIA proprietary driver" // {
    default = true;
  };

  config = lib.mkIf config.my.nvidia.enable {
    # Required for NVENC in OBS and for the CUDA stack (ollama-cuda,
    # llama.cpp for SIVA); nouveau has neither.
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true; # required for 32-bit Steam games / Proton

    hardware.nvidia = {
      modesetting.enable = true; # required for Wayland (niri, cosmic)
      nvidiaSettings = true;
      # `open` (the open kernel module) is only correct on Turing and newer, so
      # the host decides. mkDefault keeps it overridable per machine.
      open = lib.mkDefault true;
    };
  };
}
