// SIVA wake-word enrollment overlay (Invincible theme)
// Driven by siva-enroll over /tmp/siva-enroll.sock (newline JSON).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    readonly property color cYellow: "#fcba03"
    readonly property color cBlue:   "#3a5cff"
    readonly property color cRed:    "#ff2020"
    readonly property color cGreen:  "#2ecc71"
    readonly property color cDim:    "#666666"
    readonly property color cText:   "#dddddd"

    property bool shown: false
    property string phase: "welcome"   // welcome prompt countdown recording saved training done error
    property int step: 0
    property int total: 9
    property string promptText: ""
    property string detailText: ""
    property int count: 0

    readonly property color accent:
        phase === "recording" ? cRed :
        phase === "training"  ? cYellow :
        phase === "done"      ? cGreen :
        phase === "error"     ? cRed : cBlue

    // waveform bars while recording
    property real b0: 4; property real b1: 4; property real b2: 4; property real b3: 4
    property real b4: 4; property real b5: 4; property real b6: 4; property real b7: 4
    function rh() { return 4 + Math.random() * 22 }

    visible: shown
    implicitWidth: 640
    implicitHeight: 320
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true }
    margins { top: 200 }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "siva-enroll"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function send(obj) {
        const s = sockLoader.item
        if (s && s.connected)
            s.write(JSON.stringify(obj) + "\n")
    }

    // daemon link — same Loader-bounce reconnect pattern as Siva.qml
    property bool linkUp: false

    Component {
        id: sockComp
        Socket {
            path: "/tmp/siva-enroll.sock"
            connected: true
            parser: SplitParser {
                onRead: line => {
                    root.linkUp = true
                    watchdog.restart()
                    let m
                    try { m = JSON.parse(line) } catch (e) { return }
                    switch (m.type) {
                    case "show": root.shown = true; break
                    case "hide": root.shown = false; break
                    case "enroll":
                        root.phase = m.phase
                        root.step = m.step
                        root.total = m.total
                        root.promptText = m.text
                        root.detailText = m.detail
                        root.count = m.count
                        root.shown = true
                        break
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

    Timer { interval: 80;  running: root.phase === "recording"; repeat: true; onTriggered: root.b0 = root.rh() }
    Timer { interval: 100; running: root.phase === "recording"; repeat: true; onTriggered: root.b1 = root.rh() }
    Timer { interval: 130; running: root.phase === "recording"; repeat: true; onTriggered: root.b2 = root.rh() }
    Timer { interval: 90;  running: root.phase === "recording"; repeat: true; onTriggered: root.b3 = root.rh() }
    Timer { interval: 120; running: root.phase === "recording"; repeat: true; onTriggered: root.b4 = root.rh() }
    Timer { interval: 95;  running: root.phase === "recording"; repeat: true; onTriggered: root.b5 = root.rh() }
    Timer { interval: 110; running: root.phase === "recording"; repeat: true; onTriggered: root.b6 = root.rh() }
    Timer { interval: 85;  running: root.phase === "recording"; repeat: true; onTriggered: root.b7 = root.rh() }

    Rectangle {
        anchors.fill: parent
        color: "#f2000000"
        border.color: root.accent
        border.width: 1
        radius: 18

        Column {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 12

            // header
            Item {
                width: parent.width; height: 26
                Row {
                    spacing: 10
                    Text {
                        text: "󱚥  SIVA setup"
                        color: root.cYellow
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 16; bold: true }
                    }
                    Text {
                        text: root.step > 0 ? "step " + root.step + " / " + root.total : ""
                        color: root.cDim
                        anchors.verticalCenter: parent.verticalCenter
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 11 }
                    }
                }
                // step progress dots
                Row {
                    spacing: 6
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: root.total
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: index < root.step ? root.cYellow :
                                   index === root.step - 1 ? root.accent : "#333333"
                        }
                    }
                }
            }

            // main prompt
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.count > 0 ? root.count : root.promptText
                color: root.count > 0 ? root.cYellow : root.cText
                wrapMode: Text.Wrap
                font { family: "JetBrains Mono Nerd Font"
                       pixelSize: root.count > 0 ? 64 : 24
                       bold: true }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.detailText
                color: root.cDim
                wrapMode: Text.Wrap
                font { family: "JetBrains Mono Nerd Font"; pixelSize: 12 }
            }

            // recording waveform
            Row {
                spacing: 4
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.phase === "recording"
                height: 30
                Repeater {
                    model: [root.b0, root.b1, root.b2, root.b3,
                            root.b4, root.b5, root.b6, root.b7]
                    Rectangle {
                        width: 4; radius: 2
                        color: root.cRed
                        height: modelData
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on height { NumberAnimation { duration: 110 } }
                    }
                }
            }

            // spinner while training
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.phase === "training"
                text: "󰔟"
                color: root.cYellow
                font { family: "JetBrains Mono Nerd Font"; pixelSize: 28 }
                RotationAnimation on rotation {
                    running: root.phase === "training"
                    loops: Animation.Infinite; from: 0; to: 360; duration: 1500
                }
            }
        }

        // invisible key handler: Enter starts, Esc cancels/closes
        TextInput {
            id: keys
            anchors.bottom: parent.bottom
            width: 1; height: 1
            opacity: 0
            focus: root.shown
            onAccepted: if (root.phase === "welcome") root.send({ type: "start" })
            Keys.onEscapePressed: {
                root.send({ type: "hide" })
                root.shown = false
            }
        }
    }
}
