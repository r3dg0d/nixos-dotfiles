{ lib
, writeShellApplication
, curl
, python3
, coreutils
, gnugrep
}:

# Downloads the SIVA runtime assets that are too large (or too licence-bound)
# to live in the nix store: the whisper.cpp STT model, the piper TTS voice, and
# the openWakeWord wheel plus its feature-extractor ONNX models.
#
# Everything lands under ~/.local/share/siva, which is exactly where the
# daemons look. Idempotent: an asset that is already present is left alone, so
# this is safe to re-run and safe to run from the installer.
#
# The large LLM GGUFs are deliberately NOT fetched here — see the message at
# the end of the script. `services.siva.llama.modelDir` says where they belong.
writeShellApplication {
  name = "siva-fetch-assets";
  runtimeInputs = [ curl python3 coreutils gnugrep ];
  text = ''
    set -euo pipefail

    SHARE="''${XDG_DATA_HOME:-$HOME/.local/share}/siva"
    mkdir -p "$SHARE" "$SHARE/piper" "$SHARE/wake" "$SHARE/pylib"

    say()  { printf '\033[1;32m==\033[0m %s\n' "$*"; }
    warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

    # get <url> <dest> [min-bytes]
    get() {
      local url=$1 dest=$2 min=''${3:-1024}
      if [ -s "$dest" ] && [ "$(stat -c %s "$dest")" -ge "$min" ]; then
        say "have $(basename "$dest")"
        return 0
      fi
      say "fetching $(basename "$dest")"
      curl -fL --retry 3 --retry-delay 2 --progress-bar "$url" -o "$dest.part"
      mv "$dest.part" "$dest"
    }

    say "SIVA runtime assets -> $SHARE"

    # ---- speech to text (whisper.cpp) ----
    get https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin \
        "$SHARE/ggml-base.en.bin" 100000000

    # ---- speech synthesis (piper) ----
    get https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx \
        "$SHARE/piper/en_US-lessac-medium.onnx" 40000000
    get https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json \
        "$SHARE/piper/en_US-lessac-medium.onnx.json" 1000

    # ---- wake word (openWakeWord) ----
    # A pure-Python wheel, not packaged in nixpkgs. siva-wake adds this
    # directory to sys.path explicitly, so a --target install is enough; no
    # virtualenv and nothing on the system python.
    if [ -d "$SHARE/pylib/openwakeword" ]; then
      say "have openwakeword"
    else
      say "installing openwakeword into $SHARE/pylib"
      python3 -m pip install --quiet --no-deps --target "$SHARE/pylib" openwakeword
    fi

    # openWakeWord's shared feature extractor (melspectrogram + embeddings).
    get https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/melspectrogram.onnx \
        "$SHARE/wake/melspectrogram.onnx" 500000
    get https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/embedding_model.onnx \
        "$SHARE/wake/embedding_model.onnx" 500000

    echo
    if [ -s "$SHARE/wake/verifier.pkl" ]; then
      say "wake-word verifier present"
    else
      warn "no wake-word verifier yet — run 'siva-enroll' and say the wake"
      warn "   word a few times. Until then siva-wake waits instead of"
      warn "   listening (it does not fail, it just does nothing)."
    fi

    echo
    say "done. The LLM weights are NOT fetched by this script:"
    # printf rather than a heredoc: a heredoc terminator inside a Nix
    # indented string is at the mercy of the formatter's re-indentation.
    printf '%s\n' \
      "" \
      "  SIVA talks to a llama.cpp server that must be pointed at a local GGUF." \
      "  Put the model + multimodal projector where services.siva.llama.modelDir" \
      "  says (default ~/models/gemma-4-31b), under the filenames configured in" \
      "  services.siva.llama.model / .mmproj — for example:" \
      "" \
      "      huggingface-cli download <repo> <file> --local-dir ~/models/gemma-4-31b" \
      "" \
      "  Then:  systemctl --user restart siva-llama-server" \
      ""
  '';

  meta = with lib; {
    description = "Download SIVA's STT/TTS/wake-word runtime assets into ~/.local/share/siva";
    platforms = platforms.linux;
  };
}
