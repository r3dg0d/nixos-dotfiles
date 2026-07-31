// Quickshell power menu — OLED black / white / neon-green (#00ff41).
// Logout / Restart / Shutdown / Sleep. Toggle via IPC:
//   qs ipc call power toggle
// Wired to the Waybar `custom/power` module's on-click.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ── palette (matches shell.qml / Wifi.qml) ────────────────────────
    readonly property color cBg:     "#000000"
    readonly property color cPanel:  "#0a0a0a"
    readonly property color cAccent: "#00ff41"
    readonly property color cText:   "#ffffff"
    readonly property color cDim:    "#555555"
    readonly property color cDanger: "#ff2b2b"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // ── state ─────────────────────────────────────────────────────────
    property bool shown: false

    // ── open / close ──────────────────────────────────────────────────
    function open()   { shown = true; }
    function close()  { shown = false; }
    function toggle() { shown ? close() : open(); }

    // run a power action, then dismiss the menu
    function act(cmd) {
        actionProc.command = cmd;
        actionProc.running = true;
        close();
    }

    // ── power actions ─────────────────────────────────────────────────
    // { icon, label, danger, command }
    readonly property var actions: [
        { icon: "󰗽", label: "Logout",   danger: false, cmd: ["niri", "msg", "action", "quit", "-s"] },
        { icon: "󰜉", label: "Restart",  danger: false, cmd: ["systemctl", "reboot"] },
        { icon: "󰐥", label: "Shutdown", danger: true,  cmd: ["systemctl", "poweroff"] },
        { icon: "󰤄", label: "Sleep",    danger: false, cmd: ["systemctl", "suspend"] }
    ]

    // Called from the command line: `qs ipc call power <fn>`
    IpcHandler {
        target: "power"
        function toggle(): void { root.toggle(); }
        function open():   void { root.open(); }
        function close():  void { root.close(); }
    }

    Process {
        id: actionProc
    }

    // ── UI ────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.shown
        focusable: true
        color: "transparent"
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-power"

        // click outside the box to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: 420
            height: 260
            color: root.cBg
            radius: 12
            border.color: root.cAccent
            border.width: 2

            MouseArea { anchors.fill: parent }   // swallow clicks

            // catch Escape anywhere in the box
            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Text {
                    text: "󰐥  Power"
                    color: root.cAccent
                    font.family: root.mono
                    font.pixelSize: 18
                    font.bold: true
                }

                // 2×2 grid of power actions
                Grid {
                    width: parent.width
                    height: parent.height - 34
                    columns: 2
                    rows: 2
                    columnSpacing: 12
                    rowSpacing: 12

                    Repeater {
                        model: root.actions

                        delegate: Rectangle {
                            width: (box.width - 32 - 12) / 2
                            height: (box.height - 32 - 34 - 12) / 2
                            radius: 8
                            color: hover.containsMouse
                                 ? (modelData.danger ? root.cDanger : root.cAccent)
                                 : root.cPanel
                            border.color: modelData.danger ? root.cDanger : root.cAccent
                            border.width: 1

                            Column {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    color: hover.containsMouse ? root.cBg
                                         : (modelData.danger ? root.cDanger : root.cAccent)
                                    font.family: root.mono
                                    font.pixelSize: 30
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    color: hover.containsMouse ? root.cBg : root.cText
                                    font.family: root.mono
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.act(modelData.cmd)
                            }
                        }
                    }
                }
            }
        }

        onVisibleChanged: if (visible)
            box.forceActiveFocus()
    }
}
