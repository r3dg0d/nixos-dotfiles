// SIVA-Type — AI-enhanced voice typing overlay (Invincible theme)
// Talks to siva-type-daemon over /tmp/siva-type.sock (newline-delimited JSON).
//
// This surface takes NO keyboard focus, ever: the whole point is that the
// text field the user was typing in stays focused so wtype lands the
// rewritten text there. Style chips are mouse-only.
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
    property string typeState: "idle"     // idle listening thinking typing error
    property string styleSel: "professional"
    property string micDevice: ""
    property string transcript: ""
    property string cotText: ""
    property string replyText: ""

    readonly property color stateColor:
        typeState === "listening" ? cRed :
        typeState === "thinking"  ? cYellow :
        typeState === "typing"    ? cGreen : cDim
    readonly property string stateLabel:
        typeState === "listening" ? "Listening" :
        typeState === "thinking"  ? "Rewriting" :
        typeState === "typing"    ? "Typing" : "Idle"

    // waveform bars
    property real b0: 4; property real b1: 4; property real b2: 4; property real b3: 4
    property real b4: 4; property real b5: 4; property real b6: 4; property real b7: 4
    function rh() { return 4 + Math.random() * 22 }

    visible: shown
    implicitWidth: 640
    implicitHeight: 380
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true }
    margins { top: 120 }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "siva-type"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function send(obj) {
        const s = sockLoader.item
        if (s && s.connected)
            s.write(JSON.stringify(obj) + "\n")
    }

    // ── daemon link ───────────────────────────────────────────────────
    // Socket.connected is the *desired* state and a Socket never re-dials
    // once its connection dies — reconnect by Loader bounce, liveness from
    // daemon pings (no ping for 8s => link is down).
    property bool linkUp: false

    Component {
        id: sockComp
        Socket {
            path: "/tmp/siva-type.sock"
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
                        root.typeState = m.value
                        if (m.value !== "idle") root.shown = true
                        break
                    case "style":       root.styleSel = m.value; break
                    case "mic":         root.micDevice = m.device; break
                    case "transcript":  root.transcript = m.text; break
                    case "cot":         root.cotText += m.text; break
                    case "cot_clear":   root.cotText = ""; break
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
    Timer {
        interval: 2000; running: !root.linkUp; repeat: true
        onTriggered: { sockLoader.active = false; sockLoader.active = true }
    }

    // waveform animation timers (only while listening)
    Timer { interval: 80;  running: root.typeState === "listening"; repeat: true; onTriggered: root.b0 = root.rh() }
    Timer { interval: 100; running: root.typeState === "listening"; repeat: true; onTriggered: root.b1 = root.rh() }
    Timer { interval: 130; running: root.typeState === "listening"; repeat: true; onTriggered: root.b2 = root.rh() }
    Timer { interval: 90;  running: root.typeState === "listening"; repeat: true; onTriggered: root.b3 = root.rh() }
    Timer { interval: 120; running: root.typeState === "listening"; repeat: true; onTriggered: root.b4 = root.rh() }
    Timer { interval: 95;  running: root.typeState === "listening"; repeat: true; onTriggered: root.b5 = root.rh() }
    Timer { interval: 110; running: root.typeState === "listening"; repeat: true; onTriggered: root.b6 = root.rh() }
    Timer { interval: 85;  running: root.typeState === "listening"; repeat: true; onTriggered: root.b7 = root.rh() }

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
                        text: "󰌌  SIVA-Type"
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
                                    running: root.typeState !== "idle"
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
                    Text {
                        text: root.micDevice
                        color: root.cDim
                        visible: root.typeState === "listening" && root.micDevice !== ""
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 9 }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // waveform, right-aligned
                Row {
                    spacing: 3
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: root.typeState === "listening"
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

            // ── personality chips (mouse-only, no keyboard focus) ─────
            Row {
                spacing: 8
                Repeater {
                    model: ["professional", "nerdy", "intelligent"]
                    Rectangle {
                        width: chipLabel.width + 24; height: 26; radius: 13
                        color: root.styleSel === modelData ? "#26fcba03" : "transparent"
                        border.color: root.styleSel === modelData ? root.cYellow : "#33ffffff"
                        border.width: 1

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: root.styleSel === modelData ? root.cYellow : root.cDim
                            font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.send({ type: "set_style", style: modelData })
                        }
                    }
                }
            }

            // raw dictation
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
                height: parent.height - y - replyBox.height - hintRow.height - 30
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

            // ── rewritten text (what gets typed) ──────────────────────
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

            // hint row
            Item {
                id: hintRow
                width: parent.width; height: 16
                Text {
                    anchors.left: parent.left
                    text: "click a style to switch personality"
                    color: root.cDim
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 10 }
                }
                Text {
                    anchors.right: parent.right
                    text: "F10 󰍬 stop / cancel"
                    color: root.cDim
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 10 }
                }
            }
        }
    }
}
