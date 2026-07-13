import Quickshell
import Quickshell.Io
import QtQuick

PanelWindow {
    id: root

    property string voiceState: "idle"
    property string deviceName: ""

    // Individual bar heights — each driven by its own staggered timer
    property real b0: 4; property real b1: 4; property real b2: 4
    property real b3: 4; property real b4: 4; property real b5: 4
    property real b6: 4; property real b7: 4

    function rh() { return 4 + Math.random() * 26; }

    visible:       voiceState !== "idle"
    exclusiveZone: 0
    width:         300
    height:        68
    color:         "transparent"
    anchors { bottom: true; right: true }
    margins { bottom: 72; right: 22 }

    // State file watcher
    Timer { interval: 100; running: true; repeat: true; onTriggered: stateFile.reload() }
    FileView {
        id: stateFile
        path: "/tmp/qs-voice-state"
        onDataChanged: {
            root.voiceState = stateFile.text().trim()
            if (root.voiceState === "recording" && root.deviceName === "")
                deviceQuery.running = true
        }
    }

    // Fetch default mic name once per session
    Process {
        id: deviceQuery
        running: false
        command: ["sh", "-c",
            "wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep 'node.nick' | head -1 | sed 's/.*= \"\\(.*\\)\"/\\1/'"]
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim()
                if (t) root.deviceName = t
            }
        }
    }

    // Staggered waveform timers — only fire when recording
    Timer { interval: 80;  running: root.voiceState === "recording"; repeat: true; onTriggered: root.b0 = root.rh() }
    Timer { interval: 100; running: root.voiceState === "recording"; repeat: true; onTriggered: root.b1 = root.rh() }
    Timer { interval: 130; running: root.voiceState === "recording"; repeat: true; onTriggered: root.b2 = root.rh() }
    Timer { interval: 90;  running: root.voiceState === "recording"; repeat: true; onTriggered: root.b3 = root.rh() }
    Timer { interval: 120; running: root.voiceState === "recording"; repeat: true; onTriggered: root.b4 = root.rh() }
    Timer { interval: 95;  running: root.voiceState === "recording"; repeat: true; onTriggered: root.b5 = root.rh() }
    Timer { interval: 110; running: root.voiceState === "recording"; repeat: true; onTriggered: root.b6 = root.rh() }
    Timer { interval: 85;  running: root.voiceState === "recording"; repeat: true; onTriggered: root.b7 = root.rh() }

    Rectangle {
        anchors.fill: parent
        color:        "#e8000000"
        border.color: root.voiceState === "recording" ? "#ff2020" : "#fcba03"
        border.width: 1
        radius:       18

        Column {
            anchors.centerIn: parent
            spacing: 5

            // Main row
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                // Mic icon (recording) / transcribe spinner
                Text {
                    text:  root.voiceState === "transcribing" ? "󰔡" : ""
                    color: root.voiceState === "recording" ? "#ff2020" : "#fcba03"
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 18 }
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on opacity {
                        running: root.voiceState === "recording"
                        loops:   Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                // Waveform bars (recording only)
                Row {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.voiceState === "recording"

                    Repeater {
                        model: [root.b0, root.b1, root.b2, root.b3, root.b4, root.b5, root.b6, root.b7]
                        Rectangle {
                            width:  3
                            radius: 2
                            color:  "#ff3030"
                            height: modelData
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on height {
                                NumberAnimation { duration: 110; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }

                // Status label
                Text {
                    text:  root.voiceState === "transcribing" ? "Transcribing…" : "Recording"
                    color: "#dddddd"
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Device name (only while recording and known)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:    root.deviceName
                color:   "#666666"
                font { family: "JetBrains Mono Nerd Font"; pixelSize: 9 }
                visible: root.voiceState === "recording" && root.deviceName !== ""
            }
        }
    }
}
