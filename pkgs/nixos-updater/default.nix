# The update stack: one checker, one updater, one waybar renderer, one kernel
# pin bumper. See modules/nixos/updater.nix for the switches that wire them to
# the system, and README.md for what each one actually does.
{ lib
, stdenvNoCC
, makeWrapper
, python3
, bash
, coreutils
, gnused
, git
, nvd
, procps
, nix
}:

let
  commands = [
    "nixos-update"
    "nixos-update-check"
    "nixos-update-waybar"
    "nixos-kernel-pin"
  ];

  # Pinned because the scripts would misbehave without exactly these: git for
  # `ls-remote` against torvalds/linux, nvd for the closure diff, pkill to
  # signal waybar, sed/coreutils for the plumbing.
  runtimeDeps = [ coreutils gnused git nvd procps ];
in
stdenvNoCC.mkDerivation {
  pname = "nixos-updater";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash python3 ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec/nixos-updater
    install -m644 nixos_updater.py $out/libexec/nixos-updater/
    for cmd in ${lib.concatStringsSep " " commands}; do
      install -m755 "$cmd" $out/libexec/nixos-updater/
    done
    patchShebangs $out/libexec/nixos-updater

    for cmd in ${lib.concatStringsSep " " commands}; do
      # $out/bin first: these commands call each other by name (nixos-update
      # runs nixos-kernel-pin and then nixos-update-check), and that has to
      # work when one is invoked by its store path rather than off PATH.
      makeWrapper $out/libexec/nixos-updater/$cmd $out/bin/$cmd \
        --prefix PATH : $out/bin \
        --prefix PATH : ${lib.makeBinPath runtimeDeps} \
        --suffix PATH : ${lib.makeBinPath [ nix ]} \
        --prefix PYTHONPATH : $out/libexec/nixos-updater
    done

    runHook postInstall
  '';

  # nix is a *suffix*, not a prefix: on a running NixOS the client should be
  # the one the daemon was built with, so /run/current-system/sw/bin wins and
  # this is only the fallback. nixos-rebuild, sudo, flatpak and fwupdmgr are
  # deliberately not in here at all — they are properties of the machine being
  # updated, and pinning a second copy of any of them would be wrong.

  meta = {
    description = "Check and apply updates across nixpkgs, flake inputs, flatpaks, the nix profile, firmware and the mainline kernel";
    mainProgram = "nixos-update";
    platforms = lib.platforms.linux;
  };
}
