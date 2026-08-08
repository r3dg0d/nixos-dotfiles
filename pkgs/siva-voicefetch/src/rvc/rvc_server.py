#!/usr/bin/env python
"""SIVA Voicefetch — resident RVC v2 conversion server.

Runs inside the siva rvc venv (see siva-rvc-setup); clients talk
newline-JSON over /tmp/siva-rvc.sock via the `siva-rvc` wrapper:

  {"cmd":"ping"}                          -> {"ok":true,"loaded":"<pth|''>"}
  {"cmd":"convert","pth":...,"index":"",
   "in":...,"out":...,"transpose":0,
   "index_rate":0.5}                      -> {"ok":true} | {"ok":false,"error":...}
  {"cmd":"quit"}

fairseq-free: the content encoder is the transformers port of ContentVec
(lengyue233/content-vec-best), pitch is RMVPE, and the synthesizer comes
from RVC-Project's vendored pure-torch infer_pack. The last generator
stays cached; hubert/rmvpe load once. Everything falls back to CPU if
CUDA is unavailable or out of memory (the LLM owns most of the 4090).
"""

import json
import math
import os
import socket
import sys
import time
import traceback

RVC_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(RVC_DIR, "pylib"))
ASSETS = os.path.join(RVC_DIR, "assets")
SOCK = "/tmp/siva-rvc.sock"
IDLE_EXIT = 30 * 60           # free VRAM if unused for 30 min

import numpy as np            # noqa: E402
import torch                  # noqa: E402
import torch.nn.functional as F  # noqa: E402
import soundfile as sf        # noqa: E402
import torchaudio             # noqa: E402

F0_MIN, F0_MAX = 50.0, 1100.0
F0_MEL_MIN = 1127 * math.log(1 + F0_MIN / 700)
F0_MEL_MAX = 1127 * math.log(1 + F0_MAX / 700)


class Engine:
    def __init__(self):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.half = self.device == "cuda"
        self.hubert = None
        self.final_proj = None
        self.rmvpe = None
        self.net_g = None
        self.net_pth = ""
        self.tgt_sr = 40000
        self.if_f0 = 1
        self.version = "v2"

    def to_cpu(self):
        self.device, self.half = "cpu", False
        self.hubert = self.rmvpe = self.net_g = None
        self.net_pth = ""
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

    def load_shared(self):
        if self.hubert is None:
            from transformers import HubertModel
            self.hubert = HubertModel.from_pretrained(
                os.path.join(ASSETS, "contentvec")).to(self.device).eval()
            if self.half:
                self.hubert = self.hubert.half()
            # final_proj (768->256) lives in the checkpoint but not in the
            # HubertModel class — only v1 models need it
            try:
                from safetensors.torch import load_file
                sd = load_file(os.path.join(ASSETS, "contentvec", "model.safetensors"))
                w, b = sd.get("final_proj.weight"), sd.get("final_proj.bias")
                if w is not None:
                    self.final_proj = (w.to(self.device), b.to(self.device))
            except Exception:
                self.final_proj = None
        if self.rmvpe is None:
            from infer.lib.rmvpe import RMVPE
            self.rmvpe = RMVPE(os.path.join(ASSETS, "rmvpe.pt"),
                               is_half=self.half, device=self.device)

    def load_model(self, pth):
        if pth == self.net_pth and self.net_g is not None:
            return
        from infer.lib.infer_pack.models import (
            SynthesizerTrnMs256NSFsid, SynthesizerTrnMs256NSFsid_nono,
            SynthesizerTrnMs768NSFsid, SynthesizerTrnMs768NSFsid_nono)
        cpt = torch.load(pth, map_location="cpu", weights_only=False)
        self.tgt_sr = cpt["config"][-1]
        cpt["config"][-3] = cpt["weight"]["emb_g.weight"].shape[0]
        self.if_f0 = cpt.get("f0", 1)
        self.version = cpt.get("version", "v1")
        cls = {("v1", 1): SynthesizerTrnMs256NSFsid,
               ("v1", 0): SynthesizerTrnMs256NSFsid_nono,
               ("v2", 1): SynthesizerTrnMs768NSFsid,
               ("v2", 0): SynthesizerTrnMs768NSFsid_nono}[(self.version, self.if_f0)]
        if self.if_f0:
            net_g = cls(*cpt["config"], is_half=self.half)
        else:
            net_g = cls(*cpt["config"])
        del net_g.enc_q
        net_g.load_state_dict(cpt["weight"], strict=False)
        net_g = net_g.eval().to(self.device)
        self.net_g = net_g.half() if self.half else net_g.float()
        self.net_pth = pth

    # — pipeline (RVC vc/pipeline.py, simplified: rmvpe f0, whole clip) —
    def convert(self, pth, index_path, wav_in, wav_out,
                transpose=0, index_rate=0.5):
        self.load_shared()
        self.load_model(pth)

        audio, sr = sf.read(wav_in, dtype="float32", always_2d=True)
        audio = audio.mean(axis=1)
        if sr != 16000:
            audio = torchaudio.functional.resample(
                torch.from_numpy(audio), sr, 16000).numpy()
        pad = 8000                                   # 0.5 s reflect padding
        audio = np.pad(audio, (pad, pad), mode="reflect")

        feats = torch.from_numpy(audio).unsqueeze(0).to(self.device)
        feats = feats.half() if self.half else feats.float()
        with torch.no_grad():
            out = self.hubert(feats).last_hidden_state       # (1, T/320, 768)
            if self.version == "v1":
                if self.final_proj is None:
                    raise RuntimeError("v1 model needs final_proj weights")
                out = F.linear(out, *self.final_proj)
            feats = out

        if index_path and os.path.exists(index_path) and index_rate > 0:
            import faiss
            index = faiss.read_index(index_path)
            big = index.reconstruct_n(0, index.ntotal)
            npy = feats[0].float().cpu().numpy()
            score, ix = index.search(npy, k=8)
            weight = np.square(1 / (score + 1e-9))
            weight /= weight.sum(axis=1, keepdims=True)
            npy = np.sum(big[ix] * np.expand_dims(weight, axis=2), axis=1)
            mixed = torch.from_numpy(npy).unsqueeze(0).to(feats)
            feats = index_rate * mixed + (1 - index_rate) * feats

        feats = F.interpolate(feats.permute(0, 2, 1), scale_factor=2
                              ).permute(0, 2, 1)             # 50 -> 100 fps
        p_len = min(audio.shape[0] // 160, feats.shape[1])
        feats = feats[:, :p_len]

        args = ()
        if self.if_f0:
            f0 = self.rmvpe.infer_from_audio(audio, thred=0.03)
            f0 *= pow(2, transpose / 12)
            f0 = np.pad(f0, (0, max(0, p_len - len(f0))))[:p_len]
            f0_mel = 1127 * np.log(1 + f0 / 700)
            f0_mel[f0_mel > 0] = (f0_mel[f0_mel > 0] - F0_MEL_MIN) * 254 / (
                F0_MEL_MAX - F0_MEL_MIN) + 1
            coarse = np.rint(np.clip(f0_mel, 1, 255)).astype(np.int64)
            pitch = torch.from_numpy(coarse).unsqueeze(0).to(self.device)
            pitchf = torch.from_numpy(f0.astype(np.float32)).unsqueeze(0).to(self.device)
            if self.half:
                pitchf = pitchf.half()
            args = (pitch, pitchf)

        sid = torch.LongTensor([0]).to(self.device)
        lens = torch.LongTensor([p_len]).to(self.device)
        with torch.no_grad():
            audio_out = self.net_g.infer(feats, lens, *args, sid)[0][0, 0]
        audio_out = audio_out.float().cpu().numpy()

        pad_tgt = int(0.5 * self.tgt_sr)
        audio_out = audio_out[pad_tgt:-pad_tgt or None]
        peak = np.abs(audio_out).max()
        if peak > 1:
            audio_out = audio_out / peak * 0.99
        sf.write(wav_out, audio_out, self.tgt_sr)


def handle(engine, req):
    cmd = req.get("cmd")
    if cmd == "ping":
        return {"ok": True, "loaded": engine.net_pth,
                "device": engine.device}
    if cmd == "quit":
        os._exit(0)
    if cmd == "convert":
        t0 = time.time()
        try:
            engine.convert(req["pth"], req.get("index", ""), req["in"],
                           req["out"], int(req.get("transpose", 0)),
                           float(req.get("index_rate", 0.5)))
        except torch.cuda.OutOfMemoryError:
            engine.to_cpu()                    # LLM hogs VRAM — retry on CPU
            engine.convert(req["pth"], req.get("index", ""), req["in"],
                           req["out"], int(req.get("transpose", 0)),
                           float(req.get("index_rate", 0.5)))
        return {"ok": True, "secs": round(time.time() - t0, 2),
                "device": engine.device}
    return {"ok": False, "error": f"unknown cmd {cmd!r}"}


def main():
    engine = Engine()
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    os.chmod(SOCK, 0o666)
    srv.listen(4)
    srv.settimeout(IDLE_EXIT)
    while True:
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            os._exit(0)
        with conn:
            f = conn.makefile("r")
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    resp = handle(engine, json.loads(line))
                except Exception as e:
                    traceback.print_exc()
                    resp = {"ok": False, "error": str(e)[:300]}
                try:
                    conn.sendall((json.dumps(resp) + "\n").encode())
                except OSError:
                    break


if __name__ == "__main__":
    main()
