"""Shared wake-word plumbing for SIVA (enrollment + runtime listener).

Uses openWakeWord's pretrained melspectrogram + speech-embedding models as a
frozen feature extractor; the actual "Siva" detector is a small logistic
regression trained on the user's own enrollment clips, so it is inherently
speaker-biased — a feature, not a bug.
"""
import os
import pickle

import numpy as np

WAKE_DIR = os.path.expanduser("~/.local/share/siva/wake")
MELSPEC = os.path.join(WAKE_DIR, "melspectrogram.onnx")
EMBEDDING = os.path.join(WAKE_DIR, "embedding_model.onnx")
VERIFIER = os.path.join(WAKE_DIR, "verifier.pkl")

WINDOW = 16          # embedding frames per scoring window (~1.28 s of audio)
FRAME_SEC = 0.08     # one embedding frame per 80 ms of audio
CHUNK_SAMPLES = 1280  # 80 ms at 16 kHz — the streaming step size


def make_features():
    from openwakeword.utils import AudioFeatures
    return AudioFeatures(melspec_model_path=MELSPEC,
                         embedding_model_path=EMBEDDING,
                         sr=16000, ncpu=2, inference_framework="onnx")


def clip_embeddings(feats, wav_path, lead_silence=0.6):
    """(n_frames, 96) embeddings for a mono 16 kHz 16-bit WAV file.

    Lead-in silence is prepended because at runtime the wake word arrives at
    the *end* of the scoring window (preceded by room tone); clips are also
    padded out so even a bare "Siva." yields full-size windows."""
    import wave
    with wave.open(wav_path, "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1, wav_path
        audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    audio = np.pad(audio, (int(16000 * lead_silence), 0))
    min_len = int(16000 * (WINDOW + 4) * FRAME_SEC)
    if len(audio) < min_len:
        audio = np.pad(audio, (0, min_len - len(audio)))
    return feats._get_embeddings(audio)


def positive_windows(emb, max_start=12):
    """Training windows for a clip whose wake word sits near the start —
    early windows place the word everywhere from window-start to window-end,
    matching how it slides past at runtime."""
    last = min(len(emb) - WINDOW, max_start)
    return [emb[i:i + WINDOW].reshape(-1) for i in range(0, last + 1)]


def all_windows(emb, step=1):
    """Every scoring window in a clip (for negative examples)."""
    return [emb[i:i + WINDOW].reshape(-1)
            for i in range(0, len(emb) - WINDOW + 1, step)]


def load_verifier():
    with open(VERIFIER, "rb") as f:
        d = pickle.load(f)
    return d["clf"], d["threshold"]


def save_verifier(clf, threshold, meta=None):
    with open(VERIFIER, "wb") as f:
        pickle.dump({"clf": clf, "threshold": float(threshold),
                     "meta": meta or {}}, f)
