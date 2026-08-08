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

  # ---- SIVA voice-assistant stack ---------------------------------------
  siva = final.callPackage ./siva { };
  siva-type = final.callPackage ./siva-type { };
  siva-voicefetch = final.callPackage ./siva-voicefetch { };
  siva-fetch-assets = final.callPackage ./siva-fetch-assets.nix { };

  # ---- applications -----------------------------------------------------
  davinci-resolve-studio-unofficial = final.callPackage ./davinci-resolve.nix { };

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
