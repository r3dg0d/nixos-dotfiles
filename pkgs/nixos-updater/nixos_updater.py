"""Shared vocabulary for the nixos-updater commands.

The three executables (`nixos-update-check`, `nixos-kernel-pin`,
`nixos-update-waybar`) all need the same cache paths, the same idea of what a
"section" is, and the same kernel-tag ordering, so it lives here rather than
being reimplemented three times with three subtly different bugs.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

SCHEMA = 1

FLAKE_DIR = Path(os.environ.get("NIXOS_UPDATER_FLAKE", Path.home() / "nixos-dotfiles"))
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "nixos-updater"
STATUS_FILE = CACHE_DIR / "status.json"
PROBE_DIR = CACHE_DIR / "flake-probe"

KERNEL_REPO = os.environ.get("NIXOS_UPDATER_KERNEL_REPO", "https://github.com/torvalds/linux")
KERNEL_PIN = FLAKE_DIR / "pkgs" / "linux-mainline" / "pin.json"

WAYBAR_SIGNAL = os.environ.get("NIXOS_UPDATER_WAYBAR_SIGNAL", "13")

# Section order is display order — in the tooltip, in the report, everywhere.
SECTIONS = ["flake", "kernel", "flatpak", "profile", "firmware"]
LABELS = {
    "flake": "Flake inputs",
    "kernel": "Mainline kernel",
    "flatpak": "Flatpaks",
    "profile": "Nix profile",
    "firmware": "Firmware",
}
ICONS = {
    "flake": "\uf313",  # nix snowflake
    "kernel": "\uf17c",  # tux
    "flatpak": "\uf487",  # box
    "profile": "\uf49e",  # package
    "firmware": "\uf2db",  # chip
}

# nix subcommands are invoked from units and from a bare login shell alike, so
# never assume the caller enabled the experimental features.
NIX_FLAGS = ["--extra-experimental-features", "nix-command flakes"]


def run(cmd, timeout=180, check=False, **kw):
    """Run a command, capture both streams, and do not raise on a bad exit."""
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=check,
        **kw,
    )


def section(count=0, items=None, error=None, skipped=None):
    """One line of the report: how many updates, and what they are."""
    return {"count": count, "items": items or [], "error": error, "skipped": skipped}


# ---------------------------------------------------------------------------
# kernel tags

VERSION_RE = re.compile(r"^v(\d+)\.(\d+)(?:\.(\d+))?(?:-rc(\d+))?$")


def kernel_sort_key(tag: str):
    """Order tags so 7.2 > 7.2-rc6 > 7.2-rc1 > 7.1.

    Returns None for anything that is not a plain release tag — torvalds/linux
    still carries oddities like v2.6.11-tree — which callers use to filter.
    """
    m = VERSION_RE.match(tag)
    if not m:
        return None
    major, minor, patch, rc = m.groups()
    # An -rc leads up to its release, so releases take the higher stage.
    stage = (0, int(rc)) if rc else (1, 0)
    return (int(major), int(minor), int(patch or 0)) + stage


def is_rc(tag: str) -> bool:
    return "-rc" in tag


def remote_kernel_tags(allow_rc: bool = True) -> list[str]:
    """Every release tag on the mainline repo, oldest first.

    `git ls-remote` rather than the REST API on purpose: no token, no 60/hour
    rate limit shared with everyone else behind this IP, same data.
    """
    proc = run(["git", "ls-remote", "--tags", "--refs", KERNEL_REPO, "v*"], timeout=120)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr.strip().splitlines() or ["git ls-remote failed"])[-1])
    tags = []
    for line in proc.stdout.splitlines():
        parts = line.split("refs/tags/")
        if len(parts) != 2:
            continue
        tag = parts[1].strip()
        key = kernel_sort_key(tag)
        if key and (allow_rc or not is_rc(tag)):
            tags.append((key, tag))
    if not tags:
        raise RuntimeError(f"no usable tags found in {KERNEL_REPO}")
    return [tag for _, tag in sorted(tags)]


def read_pin() -> dict:
    return json.loads(KERNEL_PIN.read_text())


def pinned_tag(pin: dict | None = None) -> str:
    pin = pin if pin is not None else read_pin()
    return pin.get("rev") or "v" + pin.get("version", "").lstrip("v")


# ---------------------------------------------------------------------------
# the status document


def read_status() -> dict | None:
    try:
        return json.loads(STATUS_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def write_status(status: dict) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATUS_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(status, indent=2))
    tmp.replace(STATUS_FILE)  # atomic, so waybar never reads a half-written file


def signal_waybar() -> None:
    """Nudge waybar to re-run the widget's exec immediately."""
    if shutil.which("pkill"):
        subprocess.run(
            ["pkill", f"-RTMIN+{WAYBAR_SIGNAL}", "-x", "waybar"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def mark_running(flag: bool = True) -> None:
    """Flip the in-flight bit so the bar can show a spinner during a check."""
    status = read_status() or {}
    status["running"] = flag
    write_status(status)
    signal_waybar()


def age_string(stamp: int | None) -> str:
    if not stamp:
        return "never"
    delta = int(time.time() - stamp)
    if delta < 90:
        return "just now"
    if delta < 3600:
        return f"{delta // 60}m ago"
    if delta < 86400:
        return f"{delta // 3600}h ago"
    return f"{delta // 86400}d ago"
