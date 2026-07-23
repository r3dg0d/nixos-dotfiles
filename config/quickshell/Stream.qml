// SIVA agentic live-stream overlay (Invincible theme).
// Appears while SIVA is operating the computer autonomously and shows a live
// feed of BOTH ultrawide monitors (DP-1 Alienware, DP-2 ASUS) side by side,
// the action it is currently taking, and a marker at its cursor/click target.
// The overlay is mirrored onto EVERY monitor (one layer-shell surface per
// screen via Variants) so it is visible wherever you are looking.
// Driven by siva-daemon over /tmp/siva.sock (same socket as Siva.qml):
//   agent_start {monitors:[{id,label,w,h,x}]}  -> show
//   frame {seq, cursor:[ax,ay]|null, action}   -> reload both images + marker
//   agent_stop                                 -> hide
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    // ── palette ───────────────────────────────────────────────────────
    readonly property color cYellow: "#fcba03"
    readonly property color cBlue:   "#3a5cff"
    readonly property color cRed:    "#ff2020"
    readonly property color cText:   "#dddddd"
    readonly property color cDim:    "#888888"

    // ── daemon-driven state (shared by every per-screen surface) ───────
    property bool   active: false
    property int    seq: 0
    property var    cursor: null      // [ax, ay] absolute desktop pixels, or null
    property string action: ""
    property string thought: ""
    property bool   linkUp: false

    function bust(mid) {
        return root.active ? ("file://" + "/tmp/siva-stream/" + mid + ".png?" + root.seq) : ""
    }

    // ── daemon link (same Loader-bounce reconnect pattern as Siva.qml) ─
    Component {
        id: sockComp
        Socket {
            path: "/tmp/siva.sock"
            connected: true
            parser: SplitParser {
                onRead: line => {
                    root.linkUp = true
                    watchdog.restart()
                    let m
                    try { m = JSON.parse(line) } catch (e) { return }
                    switch (m.type) {
                    case "agent_start":
                        root.cursor = null
                        root.active = true
                        break
                    case "frame":
                        root.action = m.action || root.action
                        root.cursor = m.cursor || null
                        root.seq = m.seq          // last: triggers image reload
                        break
                    case "agent_stop":
                        root.active = false
                        break
                    case "tool":   root.action = m.text; break
                    case "cot":    root.thought = (root.thought + m.text).slice(-240); break
                    case "cot_clear": root.thought = ""; break
                    case "hide":   root.active = false; break
                    }
                }
            }
        }
    }
    Loader { id: sockLoader; active: true; sourceComponent: sockComp }
    Timer { id: watchdog; interval: 8000; onTriggered: root.linkUp = false }
    Timer {
        interval: 2000; running: !root.linkUp; repeat: true
        onTriggered: { sockLoader.active = false; sockLoader.active = true }
    }

    // ── one overlay surface per monitor ────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            visible: root.active
            color: "transparent"
            exclusiveZone: 0
            anchors { top: true; bottom: true; left: true; right: true }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "siva-stream"
            // never steal keyboard focus — SIVA types into the real apps below
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // dim the whole desktop behind the feed so it reads as a "takeover"
            Rectangle {
                anchors.fill: parent
                color: "#cc000000"

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    // ── header ────────────────────────────────────────
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14

                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: root.cRed
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                running: root.active; loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 600 }
                                NumberAnimation { to: 1.0;  duration: 600 }
                            }
                        }
                        Text {
                            text: "󱚥  SIVA is operating your computer"
                            color: root.cYellow
                            anchors.verticalCenter: parent.verticalCenter
                            font { family: "JetBrains Mono Nerd Font"; pixelSize: 22; bold: true }
                        }
                    }

                    // current action chip
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: actionText.width + 28; height: 30; radius: 15
                        color: "#14ffffff"
                        border.color: root.cBlue; border.width: 1
                        visible: root.action !== ""
                        Text {
                            id: actionText
                            anchors.centerIn: parent
                            text: "⚙  " + root.action
                            color: root.cText
                            font { family: "JetBrains Mono Nerd Font"; pixelSize: 13 }
                        }
                    }

                    // ── dual-monitor feed ─────────────────────────────
                    Row {
                        id: feed
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 20
                        // each pane is a 3440x1440 monitor; scale both to fit width
                        readonly property int paneW: Math.min(760, (win.width - 120) / 2)
                        readonly property int paneH: paneW * 1440 / 3440

                        // DP-1 — Alienware (left, absolute x 0..3439)
                        Column {
                            spacing: 6
                            Text {
                                text: "󰍹  Alienware · DP-1"
                                color: root.cDim
                                font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                            }
                            Rectangle {
                                width: feed.paneW; height: feed.paneH
                                color: "#000000"; radius: 8
                                border.color: root.cBlue; border.width: 2
                                clip: true
                                Image {
                                    id: dp1
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: root.bust("DP-1")
                                    cache: false; asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                Rectangle {
                                    visible: root.cursor !== null && root.cursor[0] < 3440
                                    width: 18; height: 18; radius: 9
                                    color: "transparent"
                                    border.color: root.cRed; border.width: 3
                                    x: root.cursor ? (root.cursor[0] / 3440) * parent.width - 9 : 0
                                    y: root.cursor ? (root.cursor[1] / 1440) * parent.height - 9 : 0
                                    Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: root.cRed }
                                }
                            }
                        }

                        // DP-2 — ASUS (right, absolute x 3440..6879)
                        Column {
                            spacing: 6
                            Text {
                                text: "󰍹  ASUS · DP-2"
                                color: root.cDim
                                font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                            }
                            Rectangle {
                                width: feed.paneW; height: feed.paneH
                                color: "#000000"; radius: 8
                                border.color: root.cBlue; border.width: 2
                                clip: true
                                Image {
                                    id: dp2
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: root.bust("DP-2")
                                    cache: false; asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                Rectangle {
                                    visible: root.cursor !== null && root.cursor[0] >= 3440
                                    width: 18; height: 18; radius: 9
                                    color: "transparent"
                                    border.color: root.cRed; border.width: 3
                                    x: root.cursor ? ((root.cursor[0] - 3440) / 3440) * parent.width - 9 : 0
                                    y: root.cursor ? (root.cursor[1] / 1440) * parent.height - 9 : 0
                                    Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: root.cRed }
                                }
                            }
                        }
                    }

                    // ── live reasoning ticker ─────────────────────────
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: feed.width
                        text: root.thought
                        color: root.cDim
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideLeft
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 12 }
                    }
                }
            }
        }
    }
}
