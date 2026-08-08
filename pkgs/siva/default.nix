{ lib
, stdenvNoCC
, makeWrapper
, python3
, bash
, coreutils
, procps
, util-linux
, socat
, sox
, curl
, wget
, jq
, imagemagick
, grim
, wtype
, ydotool
, tesseract
, niri
, pipewire
, wireplumber
, whisper-cpp
, piper-tts
, siva-voicefetch
}:

let
  # siva-daemon is stdlib-only; siva-wake and siva-enroll need the wake-word
  # stack (openWakeWord itself is a pure-Python wheel that lives in
  # ~/.local/share/siva/pylib — see the siva-fetch-assets script — and is
  # pulled in with an explicit sys.path.insert, so it is not listed here).
  pythonEnv = python3.withPackages (ps: with ps; [
    numpy
    scipy
    scikit-learn
    onnxruntime
    tqdm
    requests
  ]);

  runtimePath = lib.makeBinPath [
    pythonEnv
    bash
    coreutils
    procps # pgrep, used to find a running siva-wake
    util-linux # setsid
    socat # the toggle scripts talk to the daemon socket
    sox # wake-word enrollment beeps + 16k resample
    curl
    wget
    jq
    imagemagick # `convert` for screenshot downscaling before vision calls
    grim # screen capture (wlr-screencopy)
    wtype # virtual keyboard (Wayland text input)
    ydotool # uinput-level pointer/keyboard control
    tesseract # agentic OCR: click-by-on-screen-text
    niri # `niri msg` window/workspace introspection
    pipewire # pw-record / pw-play
    wireplumber # wpctl (mic enumeration, ducking desktop audio)
    whisper-cpp # whisper-cli STT
    piper-tts # speech synthesis
    siva-voicefetch # siva-rvc, when an RVC voice is selected
  ];
in
stdenvNoCC.mkDerivation {
  pname = "siva";
  version = "1.2.0";
  src = ./src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/siva
    install -m644 lib/siva_wake_common.py $out/lib/siva/

    for f in bin/*; do
      # skip anything that is not a script (e.g. a stray __pycache__)
      [ -f "$f" ] || continue
      install -m755 "$f" "$out/bin/$(basename "$f")"
    done

    # These scripts were written against a hand-installed ~/.local/bin layout.
    # Repoint the intra-stack references at this derivation so nothing depends
    # on files having been copied into the user's home.
    substituteInPlace $out/bin/siva \
      --replace-fail '"$HOME/.local/bin/siva-daemon"' "$out/bin/siva-daemon"
    substituteInPlace $out/bin/siva-enroll \
      --replace-fail 'os.path.expanduser("~/.local/bin/siva-wake")' '"'"$out/bin/siva-wake"'"'
    # siva-rvc ships in the siva-voicefetch package; resolve it off PATH, which
    # the wrapper below pins.
    substituteInPlace $out/bin/siva-daemon \
      --replace-fail 'os.path.join(HOME, ".local/bin/siva-rvc")' '"siva-rvc"'

    runHook postInstall
  '';

  postFixup = ''
    # Pin the interpreters. patchShebangs cannot do this on its own here: it
    # resolves against the build inputs, and a plain `#!/usr/bin/env python3`
    # would otherwise survive into the output and be satisfied by whatever the
    # wrapper's PATH happened to provide.
    for f in $out/bin/*; do
      substituteInPlace "$f" \
        --replace-quiet '#!/usr/bin/env python3' '#!${pythonEnv}/bin/python3' \
        --replace-quiet '#!/usr/bin/env bash' '#!${bash}/bin/bash'
    done

    for f in $out/bin/*; do
      wrapProgram "$f" \
        --prefix PATH : ${runtimePath} \
        --prefix PYTHONPATH : $out/lib/siva
    done
  '';

  meta = with lib; {
    description = "SIVA — local voice assistant with agentic desktop control (vendored from github.com/r3dg0d/siva)";
    homepage = "https://github.com/r3dg0d/siva";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "siva";
  };
}
