# Linus' mainline kernel, straight from the torvalds/linux tags on GitHub —
# including -rc tags, which is the point: nixpkgs' `linux_testing` only moves
# when someone updates kernels-org.json, and its stable kernels never carry an
# -rc at all.
#
# The tag this builds is *pinned* in ./pin.json rather than resolved at
# evaluation time, because evaluation has no network and a config that changed
# under you between two rebuilds would not be reproducible. `nixos-update`
# rewrites that file (see pkgs/nixos-updater/kernel-pin) and the rebuild that
# follows picks the new tag up.
#
# Building this compiles a whole kernel from scratch — no binary cache has it —
# so budget 20-60 minutes on first use. See modules/nixos/kernel.nix for the
# switch that turns it on, and for why out-of-tree modules (NVIDIA above all)
# are the thing most likely to break against an -rc.
{ lib, buildLinux, fetchFromGitHub, ... }@args:

let
  pin = lib.importJSON ./pin.json;
in
buildLinux (
  (removeAttrs args [ "fetchFromGitHub" ])
  // {
    pname = "linux-mainline";
    inherit (pin) version;

    # "7.2-rc6" -> "7.2.0-rc6", which is what the kernel itself calls its
    # module directory. Same transformation nixpkgs' own mainline.nix uses.
    modDirVersion = lib.versions.pad 3 pin.version;

    src = fetchFromGitHub {
      owner = "torvalds";
      repo = "linux";
      inherit (pin) rev hash;
    };

    # nixpkgs' common-config.nix is written against the kernels nixpkgs
    # actually ships. A newer mainline tree routinely renames or drops
    # symbols it sets, and every one of those is a hard error by default on
    # x86_64. Downgrading them to warnings is what makes tracking an -rc
    # practical at all; the resulting kernel just falls back to the defconfig
    # value for whatever nixpkgs asked for and could not get.
    ignoreConfigErrors = true;

    # Every patch nixpkgs carries targets a released kernel and will not
    # apply to a tree this far ahead.
    kernelPatches = [ ];

    extraMeta = {
      branch = lib.versions.majorMinor pin.version;
      description = "Linus' mainline kernel, pinned to tag ${pin.rev}";
    };
  }
    // (args.argsOverride or { })
)
