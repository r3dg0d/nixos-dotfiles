# Every package this configuration builds itself, exposed as a single overlay
# so they are reachable as plain `pkgs.<name>` from any module (and from
# `nix build .#<name>` via the flake's `packages` output).
#
# Two kinds of entry live here:
#   * new packages — the SDDM theme, the SIVA stack, small wrappers
#   * overrides of nixpkgs packages that are broken or too old for this machine
final: prev: {

  # ---- desktop ----------------------------------------------------------
  sddm-ascii-city = final.callPackage ./sddm-ascii-city.nix { };
  quickshell-mirror = final.callPackage ./quickshell-mirror.nix { };
  hydralauncher-wayland = final.callPackage ./hydralauncher-wayland.nix { };

  # The Fn + F1…F12 key row: `fnkey` dispatches every binding in
  # config/niri/config.kdl and drives the quickshell OSD; monitor-brightness is
  # the DDC/CI half, since desktop ultrawides have no backlight sysfs node.
  fnkey = final.callPackage ./fnkeys { };
  monitor-brightness = final.callPackage ./monitor-brightness { };

  # Idle screensaver: the NixOS logo animated with terminaltexteffects, one
  # fullscreen terminal per monitor. Driven by swayidle — see
  # modules/nixos/desktop/screensaver.nix.
  nixos-screensaver = final.callPackage ./nixos-screensaver { };

  # ---- system maintenance -----------------------------------------------
  nixos-updater = final.callPackage ./nixos-updater { };

  # Linus' mainline tree, pinned to a tag in pkgs/linux-mainline/pin.json.
  # `linuxPackagesFor` wraps it into a full kernel package set (out-of-tree
  # modules included), which is what boot.kernelPackages wants.
  linux-mainline = final.callPackage ./linux-mainline { };
  linuxPackages-mainline = final.linuxPackagesFor final.linux-mainline;

  # ---- SIVA voice-assistant stack ---------------------------------------
  siva = final.callPackage ./siva { };
  siva-type = final.callPackage ./siva-type { };
  siva-voicefetch = final.callPackage ./siva-voicefetch { };
  siva-fetch-assets = final.callPackage ./siva-fetch-assets.nix { };

  # ---- applications -----------------------------------------------------
  davinci-resolve-studio-unofficial = final.callPackage ./davinci-resolve.nix { };

  # Helium browser — AppImage-only upstream, Ozone-Wayland wrapped like Hydra.
  helium = final.callPackage ./helium.nix { };

  # Video2X upscaler. This *shadows* nixpkgs' own video2x (also 6.4.0, built
  # from source) on purpose: that build's ffmpeg has no libplacebo filter, so
  # `-p libplacebo` dies with "Filter not found" — and libplacebo is the one
  # backend fast enough for feature-length material (~100 FPS vs 1–20 for the
  # ncnn models). Upstream's AppImage carries its own ffmpeg and does support
  # it, and it also gets a .desktop entry and icon, which nixpkgs' ships none of.
  video2x = final.callPackage ./video2x.nix { };

  # ---- toolchains -------------------------------------------------------
  mingw32-cc = final.callPackage ./mingw32-cc.nix { };

  # ---- nixpkgs overrides ------------------------------------------------

  # Lokinet: nixpkgs marks the package broken because its pinned release
  # doesn't compile against nixpkgs' newer system spdlog/fmt. Upstream's
  # intended from-source build uses the bundled oxen-logging submodules
  # instead, so build it that way.
  lokinet = prev.lokinet.overrideAttrs (old: {
    buildInputs = final.lib.filter (p: (p.pname or "") != "spdlog") old.buildInputs;
    cmakeFlags = old.cmakeFlags ++ [ "-DOXEN_LOGGING_FORCE_SUBMODULES=ON" ];
    postInstall = (old.postInstall or "") + ''
      # cmake links lokinet against the bundled spdlog but doesn't install it
      find . -name 'libspdlog.so*' -exec cp -av {} $out/lib/ \;
      patchelf --set-rpath "$out/lib" $out/lib/libspdlog.so.*.*.*
      # services.lokinet expects the mainnet bootstrap inside the package
      install -Dm644 ${final.fetchurl {
        url = "https://seed.lokinet.org/lokinet.signed";
        hash = "sha256-0SegVsdpGE3WQ8PbsDiO7tQLviYdCU3Eihd49yt8Lws=";
      }} $out/share/bootstrap.signed
    '';
    meta = old.meta // { broken = false; };
  });
}
