// Power / session menu — triggered by Mod+Shift+E → echo 1 > /tmp/qs-power-show
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    property bool menuVisible: false

    visible:      menuVisible
    exclusiveZone: 0
    color:        "transparent"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors { top: true; bottom: true; left: true; right: true }

    // ── IPC ────────────────────────────────────────────────────────────
    Timer { interval: 100; running: true; repeat: true; onTriggered: ipcFile.reload() }
    FileView {
        id: ipcFile
        path: "/tmp/qs-power-show"
        onDataChanged: root.menuVisible = (ipcFile.text().trim() === "1")
    }

    Process { id: closeWriter; command: ["bash", "-c", "echo 0 > /tmp/qs-power-show"] }
    Process { id: actionProc;  command: ["bash", "-c", "true"] }

    function close() { root.menuVisible = false; closeWriter.running = true }

    function run(cmd) {
        close()
        actionProc.command = ["bash", "-c", cmd]
        actionProc.running = true
    }

    // ── backdrop ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#cc000000"

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        // ── card ───────────────────────────────────────────────────────
        Rectangle {
            id: card
            width:  400
            height: 170
            anchors.centerIn: parent
            color:        "#f0000000"
            border.color: "#fcba03"
            border.width: 1
            radius:       16
            z: 1

            MouseArea { anchors.fill: parent; onClicked: {} } // swallow backdrop

            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 18

                Text {
                    text: "  Session"
                    color: "#fcba03"
                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 13; bold: true }
                    Layout.alignment: Qt.AlignHCenter
                }

                // ── buttons ────────────────────────────────────────────
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14

                    Repeater {
                        model: [
                            { icon: "󰌾", label: "Lock",     cmd: "swaylock"             },
                            { icon: "󰍃", label: "Logout",   cmd: "niri msg action quit"  },
                            { icon: "󰜉", label: "Reboot",   cmd: "systemctl reboot"      },
                            { icon: "󰤆", label: "Shutdown", cmd: "systemctl poweroff"    }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            width:  76
                            height: 76
                            radius: 12
                            color:  "#00000000"

                            border.width: 1
                            border.color: hov.containsMouse ? "#fcba03" : "#252525"

                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text:  modelData.icon
                                    color: hov.containsMouse ? "#fcba03" : "#aaaaaa"
                                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 24 }
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                Text {
                                    text:  modelData.label
                                    color: hov.containsMouse ? "#ffffff" : "#555555"
                                    font { family: "JetBrains Mono Nerd Font"; pixelSize: 10 }
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                            }

                            MouseArea {
                                id: hov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: root.run(modelData.cmd)
                            }
                        }
                    }
                }
            }
        }
    }
}
