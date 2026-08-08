{ lib
, stdenvNoCC
, makeWrapper
, python3
, bash
, coreutils
, procps
, util-linux
, socat
, curl
, wget
, unzip
, ffmpeg
, sox
, pipewire
, piper-tts
}:

let
  # The daemon itself is stdlib-only. siva-rvc drives the RVC inference stack,
  # which lives in a user-owned virtualenv under ~/.local/share/siva/rvc
  # (built by `siva-rvc-setup`) because the RVC wheels are far too large and
  # churn-prone to pin here; this python3 is only the interpreter that runs it.
  runtimePath = lib.makeBinPath [
    python3
    bash
    coreutils
    procps
    util-linux # setsid
    socat
    curl
    wget
    unzip
    ffmpeg # resampling downloaded voice models / previews
    sox
    pipewire # pw-play for voice previews
    piper-tts # the default (non-RVC) voice
  ];

  # Injected into siva-rvc-setup ahead of its smoke test. `$RVC_DIR` must reach
  # the script literally (it is the setup script's own variable), which is why
  # this is built here and passed through escapeShellArg rather than written
  # inline in the shell phase.
  installServerSnippet = ''
    install -Dm644 "${placeholder "out"}/share/siva-voicefetch/rvc_server.py" "$RVC_DIR/rvc_server.py"

    echo "== smoke test =="'';
in
stdenvNoCC.mkDerivation {
  pname = "siva-voicefetch";
  version = "1.0.1";
  src = ./src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/siva-voicefetch
    for f in bin/*; do
      # skip anything that is not a script (e.g. a stray __pycache__)
      [ -f "$f" ] || continue
      install -m755 "$f" "$out/bin/$(basename "$f")"
    done
    install -m644 rvc/rvc_server.py $out/share/siva-voicefetch/

    substituteInPlace $out/bin/siva-voicefetch \
      --replace-fail '"$HOME/.local/bin/siva-voicefetch-daemon"' \
                     "$out/bin/siva-voicefetch-daemon"

    # siva-rvc looks for rvc_server.py inside the venv directory it builds, but
    # upstream's setup script never puts it there (it was hand-copied on the
    # original machine). Install it from this package instead, and point the
    # smoke test at the siva-rvc on PATH rather than a ~/.local/bin copy.
    substituteInPlace $out/bin/siva-rvc-setup \
      --replace-fail 'echo "== smoke test =="' ${lib.escapeShellArg installServerSnippet} \
      --replace-fail '[[ -x "$HOME/.local/bin/siva-rvc" ]]' 'command -v siva-rvc >/dev/null' \
      --replace-fail '"$HOME/.local/bin/siva-rvc" --check' 'siva-rvc --check'

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
      wrapProgram "$f" \
        --prefix PATH : ${runtimePath} \
        --set-default SIVA_RVC_SERVER $out/share/siva-voicefetch/rvc_server.py
    done
  '';

  meta = with lib; {
    description = "SIVA Voicefetch — RVC v2 voice-model downloader for SIVA (vendored from github.com/r3dg0d/siva-voicefetch)";
    homepage = "https://github.com/r3dg0d/siva-voicefetch";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "siva-voicefetch";
  };
}
