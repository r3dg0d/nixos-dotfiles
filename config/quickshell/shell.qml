// Quickshell root — OLED black / white / neon-green (#00ff41).
//
// Everything here is a self-contained component with its own IPC target, so a
// widget is reachable as `qs ipc call <target> toggle` from a keybind or from a
// waybar module. This file only decides what exists.
import QtQuick
import Quickshell
import "Mirror"

ShellRoot {
    // SIVA voice assistant overlays (F8 assistant, F7 voicefetch, F9 dictation)
    Siva {}
    SivaVoicefetch {}
    SivaType {}
    SivaEnroll {}
    Stream {}       // live dual-monitor feed shown while SIVA operates agentically

    Wifi {}         // nmcli wifi picker; `qs ipc call wifi toggle` (waybar network click)
    Power {}        // power menu; `qs ipc call power toggle` (waybar power click)
    Mirror {}       // floating webcam mirror; `qs ipc call mirror toggle` (waybar mirror click)
    Feathershot {}  // screenshot annotation overlay; opened by the `feathershot` CLI
    Clipboard {}    // cliphist history picker; `qs ipc call clipboard toggle` (Mod+C)
    Updater {}      // system updates; `qs ipc call updater toggle` (waybar ❄ click)
}
