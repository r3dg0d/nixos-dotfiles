#!/usr/bin/env python3
"""Waybar music widget backed by MPD — the same daemon rmpc drives, so state
and controls stay in sync between the bar and the TUI.

Speaks the MPD protocol directly over TCP; no mpc/python-mpd dependency.

  status   one-shot JSON for a waybar custom module
  watch    same, but blocks on MPD `idle` and reprints on every change
  toggle   play/pause
  next     next track
  prev     previous track
  loop     cycle repeat: off -> all -> one
  art      print a path to cover art for the waybar image module
"""
import hashlib
import json
import os
import socket
import subprocess
import sys
import urllib.parse
import urllib.request

HOST, PORT = os.environ.get("MPD_HOST", "127.0.0.1"), int(os.environ.get("MPD_PORT", 6600))
CACHE = os.path.expanduser("~/.cache/waybar-albumart")
PLACEHOLDER = os.path.expanduser("~/.config/rmpc/assets/default-art.jpg")
SELF = os.path.abspath(__file__)

# Nerd-font icons as \u escapes on purpose — literal PUA glyphs get mangled to
# empty strings by editors and tooling. Same convention as waybar/config.jsonc.
ICON_PLAY, ICON_PAUSE, ICON_STOP = "\uf04b", "\uf04c", "\uf04d"   # fa play/pause/stop
ICON_NEXT, ICON_PREV = "\uf051", "\uf048"                          # fa step-fwd/back
ICON_REPEAT = "\U000f0456"                                         # md repeat
ICON_REPEAT_ONE = "\U000f0458"                                     # md repeat-once
ICON_REPEAT_OFF = "\U000f0457"                                     # md repeat-off


class Mpd:
    def __init__(self):
        self.sock = socket.create_connection((HOST, PORT), timeout=5)
        self.f = self.sock.makefile("rwb")
        self.f.readline()  # banner

    def cmd(self, line):
        self.f.write((line + "\n").encode())
        self.f.flush()
        out = []
        while True:
            raw = self.f.readline()
            if not raw:
                raise ConnectionError("mpd closed the connection")
            s = raw.decode("utf-8", "replace").rstrip("\n")
            if s.startswith("OK"):
                return out
            if s.startswith("ACK"):
                raise RuntimeError(s)
            out.append(s)

    def kv(self, line):
        d = {}
        for s in self.cmd(line):
            if ": " in s:
                k, v = s.split(": ", 1)
                d.setdefault(k, v)
        return d

    def binary(self, cmd, uri):
        """Fetch a binary blob (albumart / readpicture) across chunked offsets."""
        data, offset = b"", 0
        while True:
            self.f.write(f'{cmd} "{esc(uri)}" {offset}\n'.encode())
            self.f.flush()
            size = chunk = None
            while True:
                raw = self.f.readline()
                if not raw:
                    raise ConnectionError("mpd closed")
                s = raw.decode("utf-8", "replace").rstrip("\n")
                if s.startswith("ACK"):
                    raise RuntimeError(s)
                if s.startswith("size: "):
                    size = int(s[6:])
                elif s.startswith("binary: "):
                    chunk = int(s[8:])
                    break
                elif s.startswith("OK"):
                    return data
            payload = self.f.read(chunk)
            self.f.read(1)  # trailing newline
            self.f.readline()  # OK
            data += payload
            offset += chunk
            if size is None or offset >= size:
                return data

    def idle(self):
        self.sock.settimeout(None)
        self.f.write(b"idle player options mixer\n")
        self.f.flush()
        while True:
            raw = self.f.readline()
            if not raw:
                raise ConnectionError("mpd closed")
            s = raw.decode("utf-8", "replace").rstrip("\n")
            if s.startswith("OK") or s.startswith("ACK"):
                return


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def fmt_time(sec):
    try:
        sec = int(float(sec))
    except (TypeError, ValueError):
        return "0:00"
    return f"{sec // 60}:{sec % 60:02d}"


def describe(status, song):
    """(title, artist) with a filename fallback for untagged tracks."""
    title = song.get("Title")
    if not title:
        base = os.path.basename(song.get("file", ""))
        title = os.path.splitext(base)[0] or "Nothing playing"
    return title, song.get("Artist", "")


def build_status(m):
    status = m.kv("status")
    song = m.kv("currentsong")
    state = status.get("state", "stop")
    title, artist = describe(status, song)

    if state == "stop" and not song:
        return {"text": "", "tooltip": "MPD stopped", "class": "stopped", "alt": "stopped"}

    label = f"{title} — {artist}" if artist else title
    icon = {"play": ICON_PLAY, "pause": ICON_PAUSE}.get(state, ICON_STOP)

    elapsed, dur = status.get("elapsed", 0), status.get("duration", 0)
    tip = [title]
    if artist:
        tip.append(f"by {artist}")
    if song.get("Album"):
        tip.append(f"from {song['Album']}")
    tip.append(f"{fmt_time(elapsed)} / {fmt_time(dur)}")
    rep, sing = status.get("repeat") == "1", status.get("single") == "1"
    tip.append("repeat: " + ("one" if rep and sing else "all" if rep else "off"))

    return {
        "text": f"{icon}  {label}",
        "tooltip": "\n".join(tip),
        "class": state,
        "alt": state,
    }


# ---------------------------------------------------------------- album art

def art_key(song):
    ident = (song.get("Artist", ""), song.get("Album", ""), song.get("Title", ""))
    if not any(ident):
        ident = (song.get("file", ""),)
    return hashlib.sha1("|".join(ident).encode()).hexdigest()


# Edit/rip descriptors that appear in these filenames but never in an official
# catalogue title. Dropping them makes the relevance check far less noisy.
NOISE = {
    "slowed", "reverb", "sped", "up", "speed", "nightcore", "remix", "edit",
    "official", "lyrics", "lyric", "version", "mix", "audio", "video", "hd",
    "bass", "boosted", "extended", "bootleg", "hardstyle", "tiktok", "tik",
    "tok", "prod", "feat", "ft", "the", "a", "an", "and", "x", "vs",
    "aryan", "classic", "save", "europe", "agartha", "perfection", "part",
}


def tokens(s):
    out = set()
    for t in "".join(c.lower() if c.isalnum() else " " for c in s).split():
        if t not in NOISE and len(t) > 1:
            out.add(t)
    return out


def scrape(song, dest):
    """Look the track up on the iTunes Search API (keyless) and cache the cover.

    iTunes always returns *something*, so a nearest match on a nightcore/remix
    rip would otherwise give confidently wrong art. Candidates are scored on
    token containment against the query and rejected below MIN_SCORE, which
    turns a bad guess into the neutral placeholder instead.
    """
    MIN_SCORE = 0.6

    artist, title = song.get("Artist", ""), song.get("Title", "")
    terms = " ".join(x for x in (artist, title) if x)
    if not terms:
        base = os.path.basename(song.get("file", ""))
        terms = os.path.splitext(base)[0]
    if not terms.strip():
        return False

    want = tokens(terms)
    if not want:
        return False

    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
        {"term": terms, "entity": "song", "limit": 5})
    try:
        with urllib.request.urlopen(url, timeout=6) as r:
            data = json.load(r)
    except Exception:
        return False

    best, best_score = None, 0.0
    for res in data.get("results") or []:
        cand = tokens(f"{res.get('artistName', '')} {res.get('trackName', '')}")
        if not cand:
            continue
        score = len(want & cand) / len(want)
        if score > best_score:
            best, best_score = res, score

    if not best or best_score < MIN_SCORE:
        return False

    art = best.get("artworkUrl100")
    if not art:
        return False
    art = art.replace("100x100bb", "600x600bb")
    try:
        with urllib.request.urlopen(art, timeout=6) as r:
            blob = r.read()
    except Exception:
        return False
    if len(blob) < 512:
        return False
    with open(dest, "wb") as fh:
        fh.write(blob)
    return True


def cmd_art():
    os.makedirs(CACHE, exist_ok=True)
    try:
        m = Mpd()
        song = m.kv("currentsong")
    except Exception:
        print(PLACEHOLDER)
        return
    if not song:
        print(PLACEHOLDER)
        return

    key = art_key(song)
    hit, miss = os.path.join(CACHE, key + ".jpg"), os.path.join(CACHE, key + ".miss")

    if os.path.exists(hit):
        print(hit)
        return

    # Embedded picture, then a cover file next to the track — both local & instant.
    for cmd in ("readpicture", "albumart"):
        try:
            blob = m.binary(cmd, song["file"])
            if blob and len(blob) > 512:
                with open(hit, "wb") as fh:
                    fh.write(blob)
                print(hit)
                return
        except Exception:
            pass

    # Nothing local. Show the placeholder now and scrape in the background so
    # the next poll picks up the real cover without ever blocking waybar.
    print(PLACEHOLDER)
    if not os.path.exists(miss):
        subprocess.Popen(
            [sys.executable, SELF, "_scrape"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)


def cmd_scrape():
    """Background half of `art`: fetch and cache, marking failures so we only try once."""
    os.makedirs(CACHE, exist_ok=True)
    try:
        song = Mpd().kv("currentsong")
    except Exception:
        return
    if not song:
        return
    key = art_key(song)
    hit, miss = os.path.join(CACHE, key + ".jpg"), os.path.join(CACHE, key + ".miss")
    if os.path.exists(hit) or os.path.exists(miss):
        return
    if not scrape(song, hit):
        open(miss, "w").close()


# ---------------------------------------------------------------- commands

def refresh(sig):
    subprocess.run(["pkill", f"-RTMIN+{sig}", "waybar"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"

    if action == "_scrape":
        cmd_scrape()
        return
    if action == "art":
        cmd_art()
        return

    if action == "watch":
        while True:
            try:
                m = Mpd()
                while True:
                    print(json.dumps(build_status(m)), flush=True)
                    m.idle()
            except Exception:
                print(json.dumps({"text": "", "tooltip": "MPD unreachable",
                                  "class": "offline", "alt": "offline"}), flush=True)
                import time
                time.sleep(5)

    try:
        m = Mpd()
    except Exception:
        if action in ("status", "playicon", "loopicon"):
            print(json.dumps({"text": "", "tooltip": "MPD unreachable",
                              "class": "offline", "alt": "offline"}))
        return

    if action == "status":
        print(json.dumps(build_status(m)))

    elif action == "playicon":
        st = m.kv("status").get("state", "stop")
        print(json.dumps({
            "text": ICON_PAUSE if st == "play" else ICON_PLAY,
            "tooltip": "Pause" if st == "play" else "Play",
            "class": st,
        }))

    elif action == "loopicon":
        s = m.kv("status")
        rep, sing = s.get("repeat") == "1", s.get("single") == "1"
        if rep and sing:
            print(json.dumps({"text": ICON_REPEAT_ONE, "tooltip": "Repeat: one", "class": "one"}))
        elif rep:
            print(json.dumps({"text": ICON_REPEAT, "tooltip": "Repeat: all", "class": "all"}))
        else:
            print(json.dumps({"text": ICON_REPEAT_OFF, "tooltip": "Repeat: off", "class": "off"}))

    elif action == "toggle":
        st = m.kv("status").get("state", "stop")
        if st == "play":
            m.cmd("pause 1")
        elif st == "pause":
            m.cmd("pause 0")
        else:
            m.cmd("play")
        refresh(10)

    # MPD starts playing when you skip while paused. Restore the previous
    # transport state so the skip buttons never surprise you with sound.
    elif action in ("next", "prev"):
        was = m.kv("status").get("state", "stop")
        m.cmd("next" if action == "next" else "previous")
        if was != "play":
            m.cmd("pause 1")
        refresh(10)

    elif action == "loop":
        s = m.kv("status")
        rep, sing = s.get("repeat") == "1", s.get("single") == "1"
        if not rep:                 # off -> all
            m.cmd("repeat 1")
            m.cmd("single 0")
        elif rep and not sing:      # all -> one
            m.cmd("single 1")
        else:                       # one -> off
            m.cmd("repeat 0")
            m.cmd("single 0")
        refresh(11)

    else:
        print(f"unknown action: {action}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
