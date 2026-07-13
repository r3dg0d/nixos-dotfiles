// SIVA — Super Intelligent Voice Assistant overlay (Invincible theme)
// Talks to siva-daemon over /tmp/siva.sock (newline-delimited JSON).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    // ── palette ───────────────────────────────────────────────────────
    readonly property color cYellow: "#fcba03"
    readonly property color cBlue:   "#3a5cff"
    readonly property color cRed:    "#ff2020"
    readonly property color cGreen:  "#2ecc71"
    readonly property color cDim:    "#666666"
    readonly property color cText:   "#dddddd"

    // ── daemon-driven state ───────────────────────────────────────────
    property bool  shown: false
    property string sivaState: "idle"     // idle listening thinking executing speaking error
    property string micDevice: ""
    property string transcript: ""
    property string cotText: ""
    property string replyText: ""

    readonly property color stateColor:
        sivaState === "listening" ? cRed :
        sivaState === "thinking"  ? cYellow :
        sivaState === "executing" ? cBlue :
        sivaState === "speaking"  ? cGreen : cDim
    readonly property string stateLabel:
        sivaState === "listening" ? "Listening" :
        sivaState === "thinking"  ? "Thinking" :
        sivaState === "executing" ? "Executing" :
        sivaState === "speaking"  ? "Speaking" : "Idle"

    // waveform bars
    property real b0: 4; property real b1: 4; property real b2: 4; property real b3: 4
    property real b4: 4; property real b5: 4; property real b6: 4; property real b7: 4
    function rh() { return 4 + Math.random() * 22 }

    visible: shown
    implicitWidth: 760
    implicitHeight: 520
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true }
    margins { top: 120 }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "siva"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function send(obj) {
        const s = sockLoader.item
        if (s && s.connected)
            s.write(JSON.stringify(obj) + "\n")
    }

    // ── daemon link ───────────────────────────────────────────────────
    // Socket.connected is the *desired* state, not the actual link, and a
    // Socket never re-dials once its connection dies — the only reliable
    // reconnect is destroying and recreating the Socket (Loader bounce).
    // Liveness comes from daemon pings: no ping for 8s => link is down.
    property bool linkUp: false

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
                    case "show":        root.shown = true; break
                    case "hide":        root.shown = false; break
                    case "status":
                        root.sivaState = m.value
                        if (m.value !== "idle") root.shown = true
                        break
                    case "mic":         root.micDevice = m.device; break
                    case "transcript":  root.transcript = m.text; break
                    case "cot":         root.cotText += m.text; break
                    case "cot_clear":   root.cotText = ""; break
                    case "tool":        root.cotText += "\n⚙ " + m.text + "\n"; break
                    case "reply":       root.replyText += m.text; break
                    case "reply_clear": root.replyText = ""; break
                    case "error":       root.cotText += "\n✖ " + m.text + "\n"; break
                    }
                }
            }
        }
    }
    Loader { id: sockLoader; active: true; sourceComponent: sockComp }

    Timer {
        id: watchdog
        interval: 8000
        onTriggered: root.linkUp = false
    }
    // rebuild the socket while the daemon link is down
    Timer {
        interval: 2000; running: !root.linkUp; repeat: true
        onTriggered: { sockLoader.active = false; sockLoader.active = true }
    }

    // waveform animation timers (only while listening)
    Timer { interval: 80;  running: root.sivaState === "listening"; repeat: true; onTriggered: root.b0 = root.rh() }
    Timer { interval: 100; running: root.sivaState === "listening"; repeat: true; onTriggered: root.b1 = root.rh() }
    Timer { interval: 130; running: root.sivaState === "listening"; repeat: true; onTriggered: root.b2 = root.rh() }
    Timer { interval: 90;  running: root.sivaState === "listening"; repeat: true; onTriggered: root.b3 = root.rh() }
    Timer { interval: 120; running: root.sivaState === "listening"; repeat: true; onTriggered: root.b4 = root.rh() }
    Timer { interval: 95;  running: root.sivaState === "listening"; repeat: true; onTriggered: root.b5 = root.rh() }
    Timer { interval: 110; running: root.sivaState === "listening"; repeat: true; onTriggered: root.b6 = root.rh() }
    Timer { interval: 85;  running: root.sivaState === "listening"; repeat: true; onTriggered: root.b7 = root.rh() }

    // ── card ──────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#f2000000"
        border.color: root.stateColor
        border.width: 1
        radius: 18

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            // header: title + status chip + waveform
            Item {
                width: parent.width; height: 30

                Row {
                    spacing: 10
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "󱚥  SIVA"
                        color: root.cYellow
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 18; bold: true }
                    }
                    Rectangle {
                        width: chip.width + 20; height: 22; radius: 11
                        color: "transparent"
                        border.color: root.stateColor; border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: chip
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: root.stateColor
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: root.sivaState !== "idle"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 500 }
                                    NumberAnimation { to: 1.0; duration: 500 }
                                }
                            }
                            Text {
                                text: root.stateLabel
                                color: root.cText
                                font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                            }
                        }
                    }
                    // mic device
                    Text {
                        text: root.micDevice
                        color: root.cDim
                        visible: root.sivaState === "listening" && root.micDevice !== ""
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 9 }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // waveform, right-aligned
                Row {
                    spacing: 3
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: root.sivaState === "listening"
                    Repeater {
                        model: [root.b0, root.b1, root.b2, root.b3,
                                root.b4, root.b5, root.b6, root.b7]
                        Rectangle {
                            width: 3; radius: 2
                            color: root.cRed
                            height: modelData
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on height { NumberAnimation { duration: 110 } }
                        }
                    }
                }
            }

            // transcript of what SIVA heard
            Text {
                width: parent.width
                visible: root.transcript !== ""
                text: "❯ " + root.transcript
                color: root.cYellow
                wrapMode: Text.Wrap
                font { family: "JetBrains Mono Nerd Font"; pixelSize: 13 }
            }

            // ── chain-of-thought panel ────────────────────────────────
            Rectangle {
                width: parent.width
                height: parent.height - y - inputRow.height - replyBox.height - 30
                color: "#0dffffff"
                radius: 10
                border.color: "#22ffffff"; border.width: 1

                Text {
                    anchors { top: parent.top; left: parent.left; margins: 8 }
                    text: "chain of thought"
                    color: root.cDim
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 9 }
                }

                Flickable {
                    id: cotFlick
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.topMargin: 24
                    clip: true
                    contentHeight: cotBody.height
                    contentY: Math.max(0, cotBody.height - height)

                    Text {
                        id: cotBody
                        width: cotFlick.width
                        text: root.cotText === "" ? "…" : root.cotText
                        color: root.cotText === "" ? root.cDim : "#aaaaaa"
                        wrapMode: Text.Wrap
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                    }
                }
            }

            // ── final reply ───────────────────────────────────────────
            Rectangle {
                id: replyBox
                width: parent.width
                height: root.replyText === "" ? 0 : replyBody.height + 20
                visible: root.replyText !== ""
                color: "#14fcba03"
                radius: 10
                border.color: "#44fcba03"; border.width: 1
                Behavior on height { NumberAnimation { duration: 120 } }

                Text {
                    id: replyBody
                    anchors { left: parent.left; right: parent.right;
                              verticalCenter: parent.verticalCenter; margins: 10 }
                    text: root.replyText
                    color: root.cText
                    wrapMode: Text.Wrap
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 13 }
                }
            }

            // ── text fallback input ───────────────────────────────────
            Rectangle {
                id: inputRow
                width: parent.width
                height: 38
                color: "#0dffffff"
                radius: 10
                border.color: input.activeFocus ? root.cYellow : "#22ffffff"
                border.width: 1

                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: 12; rightMargin: 70 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.cText
                    clip: true
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 13 }

                    onAccepted: {
                        if (text.trim() === "") return
                        root.send({ type: "user_text", text: text.trim() })
                        text = ""
                    }
                    Keys.onEscapePressed: root.send({ type: "hide" })

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: input.text === "" && !input.activeFocus
                        text: "type instead — Enter to send, Esc to close"
                        color: root.cDim
                        font: input.font
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 12;
                              verticalCenter: parent.verticalCenter }
                    text: "F8 󰍬"
                    color: root.cDim
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                }
            }
        }
    }
}
