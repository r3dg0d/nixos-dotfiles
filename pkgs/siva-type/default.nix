{ lib
, stdenvNoCC
, makeWrapper
, python3
, bash
, coreutils
, procps
, util-linux
, socat
, pipewire
, wireplumber
, whisper-cpp
, wtype
, ydotool
}:

let
  # siva-type-daemon is stdlib-only Python.
  runtimePath = lib.makeBinPath [
    python3
    bash
    coreutils
    procps
    util-linux # setsid
    socat
    pipewire # pw-record
    wireplumber # wpctl
    whisper-cpp # whisper-cli STT
    # Typing into the focused surface. wtype uses the virtual-keyboard Wayland
    # protocol (niri supports it); ydotool is the uinput fallback for surfaces
    # or compositors that do not.
    wtype
    ydotool
  ];
in
stdenvNoCC.mkDerivation {
  pname = "siva-type";
  version = "1.0.1";
  src = ./src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    for f in bin/*; do
      # skip anything that is not a script (e.g. a stray __pycache__)
      [ -f "$f" ] || continue
      install -m755 "$f" "$out/bin/$(basename "$f")"
    done

    substituteInPlace $out/bin/siva-type \
      --replace-fail '"$HOME/.local/bin/siva-type-daemon"' "$out/bin/siva-type-daemon"

    runHook postInstall
  '';

  postFixup = ''
    # See the note in pkgs/siva/default.nix: pin the interpreters rather than
    # leaving `#!/usr/bin/env` to be resolved off the wrapper's PATH.
    for f in $out/bin/*; do
      substituteInPlace "$f" \
        --replace-quiet '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
        --replace-quiet '#!/usr/bin/env bash' '#!${bash}/bin/bash'
    done

    for f in $out/bin/*; do
      wrapProgram "$f" --prefix PATH : ${runtimePath}
    done
  '';

  meta = with lib; {
    description = "SIVA-Type — AI-enhanced voice dictation (vendored from github.com/r3dg0d/siva-type)";
    homepage = "https://github.com/r3dg0d/siva-type";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "siva-type";
  };
}
