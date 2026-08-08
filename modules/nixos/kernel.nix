# Which kernel this machine boots.
#
# Two choices: nixpkgs' newest packaged kernel (the default — cached, tested,
# boring) or Linus' mainline tree pinned to a tag in pkgs/linux-mainline/pin.json
# (bleeding edge, compiled locally, moved by `nixos-update --kernel`).
{ config, lib, pkgs, ... }:

let
  cfg = config.my.kernel;
  usesNvidia = lib.elem "nvidia" config.services.xserver.videoDrivers;
in
{
  options.my.kernel = {
    mainline = {
      enable = lib.mkEnableOption ''
        booting Linus' mainline kernel from the tag pinned in
        pkgs/linux-mainline/pin.json instead of nixpkgs' latest.

        Understand what this costs before turning it on:

        * **No binary cache has it.** Every pin bump is a full kernel compile,
          20-60 minutes depending on the machine, and every out-of-tree module
          (NVIDIA, VirtualBox, v4l2loopback…) is rebuilt against it.
        * **Out-of-tree modules break first.** NVIDIA's proprietary driver
          regularly fails to build against an -rc for weeks after the merge
          window; when that happens the *rebuild* fails, which is inconvenient
          but safe — the running system is untouched. Pin back with
          `nixos-kernel-pin v<older-tag>` and rebuild.
        * **Keep a working generation.** The bootloader menu is the escape
          hatch when an -rc does not boot, so do not garbage-collect down to a
          single entry while tracking one.

        `nixos-update` moves the pin; `nixos-kernel-pin v<tag>` rolls it back
      '';

      trackRC = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether `nixos-update` may pin a release candidate. With this off it
          only ever moves to final releases (v7.2, v7.3, …), which is a much
          quieter tree while still being ahead of nixpkgs.

          Only affects what the updater *picks*; the pin file is always
          authoritative for what gets built.
        '';
      };
    };
  };

  config = {
    boot.kernelPackages = lib.mkDefault (
      if cfg.mainline.enable then pkgs.linuxPackages-mainline else pkgs.linuxPackages_latest
    );

    warnings = lib.optional (cfg.mainline.enable && usesNvidia) ''
      my.kernel.mainline.enable is on and this host uses the proprietary NVIDIA
      driver. NVIDIA's kernel module frequently does not build against a
      mainline -rc. If `nixos-rebuild` fails inside nvidia-x11, roll the pin
      back (`nixos-kernel-pin v<previous-tag>`) or set
      my.kernel.mainline.trackRC = false.
    '';
  };
}
