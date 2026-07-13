// Workspace overview popup — toggled by writing "1"/"0" to /tmp/qs-ws-show.
// Triggered by clicking the 󰋸 ws-info module in Waybar.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property bool previewVisible: false
    property var  workspaces: []
    property var  windows:    []

    // Full-screen transparent layer — content centred inside
    visible:      previewVisible
    exclusiveZone: 0
    color:        "transparent"

    anchors { top: true; bottom: true; left: true; right: true }

    // ── IPC ────────────────────────────────────────────────────────────
    Timer { interval: 150; running: true; repeat: true; onTriggered: wsIpcFile.reload() }
    FileView {
        id: wsIpcFile
        path: "/tmp/qs-ws-show"
        onDataChanged: {
            var show = wsIpcFile.text().trim() === "1"
            root.previewVisible = show
            if (show) dataProc.running = true
        }
    }

    // Fetch workspaces + windows in one bash call
    Process {
        id: dataProc
        command: ["bash", "-c",
            "printf '{\"workspaces\":' && niri msg -j workspaces 2>/dev/null && " +
            "printf ',\"windows\":' && niri msg -j windows 2>/dev/null && printf '}'"]
        property string _buf: ""

        stdout: SplitParser { onRead: function(l) { dataProc._buf += l } }

        onRunningChanged: {
            if (!running && _buf.length > 0) {
                try {
                    var d = JSON.parse(_buf)
                    root.workspaces = d.workspaces || []
                    root.windows    = d.windows    || []
                } catch(e) {}
                _buf = ""
            }
        }
    }

    // Helper process re-used for switch + close
    Process { id: switchProc;  property string arg: "1"; command: ["niri", "msg", "action", "focus-workspace", arg] }
    Process { id: closeWriter; command: ["bash", "-c", "echo 0 > /tmp/qs-ws-show"] }

    function closePreview() { root.previewVisible = false; closeWriter.running = true }

    // ── UI ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#aa000000"

        // Click backdrop to dismiss
        MouseArea { anchors.fill: parent; onClicked: root.closePreview() }

        // Centred card
        Rectangle {
            id:     card
            width:  Math.min(root.width  * 0.68, 820)
            height: Math.min(root.height * 0.58, 480)
            anchors.centerIn: parent
            color:        "#f0000000"
            border.color: "#fcba03"
            border.width: 1
            radius:       14
            z: 1

            MouseArea { anchors.fill: parent; onClicked: {} } // absorb backdrop clicks

            ColumnLayout {
                anchors { fill: parent; margins: 20 }
                spacing: 14

                // Header
                RowLayout {
                    Text {
                        text: "  Workspace Overview"
                        color: "#fcba03"
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 14; bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "click to switch · esc/backdrop to close"
                        color: "#444444"
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 10 }
                    }
                }

                Rectangle { height: 1; color: "#1ffcba03"; Layout.fillWidth: true }

                // Workspace grid (up to 9 tiles, 3 columns)
                Grid {
                    columns: 3
                    spacing: 10
                    Layout.fillWidth: true

                    Repeater {
                        model: root.workspaces

                        delegate: Rectangle {
                            required property var modelData
                            property var ws: modelData
                            property var wsWins: {
                                var out = []
                                for (var i = 0; i < root.windows.length; i++) {
                                    if (root.windows[i].workspace_id === ws.id) out.push(root.windows[i])
                                }
                                return out
                            }

                            width:  (card.width - 60) / 3
                            height: 110
                            color:  ws.is_focused ? "#1afcba03" : "#0dffffff"
                            border.color: ws.is_focused ? "#fcba03" : "#333333"
                            border.width: ws.is_focused ? 1 : 1
                            radius: 8

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    switchProc.arg = ws.idx.toString()
                                    switchProc.running = true
                                    root.closePreview()
                                }
                                cursorShape: Qt.PointingHandCursor
                            }

                            Column {
                                anchors { fill: parent; margins: 10 }
                                spacing: 4

                                Text {
                                    text: (ws.is_focused ? "● " : "○ ") + "WS " + ws.idx
                                    color: ws.is_focused ? "#fcba03" : "#777777"
                                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 11; bold: ws.is_focused }
                                }

                                Repeater {
                                    model: wsWins.slice(0, 4)
                                    Text {
                                        required property var modelData
                                        text: "  " + (modelData.app_id || modelData.title || "?")
                                        color: "#cccccc"
                                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 10 }
                                        elide: Text.ElideRight
                                        width: parent.width - 10
                                    }
                                }

                                Text {
                                    visible: wsWins.length > 4
                                    text: "  +" + (wsWins.length - 4) + " more"
                                    color: "#555555"
                                    font { pixelSize: 10 }
                                }

                                Text {
                                    visible: wsWins.length === 0
                                    text: "empty"
                                    color: "#333333"
                                    font { pixelSize: 10; italic: true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
