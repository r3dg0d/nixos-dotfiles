// Quickshell clipboard manager — OLED black / white / neon-green (#00ff41)
// Backend: cliphist (history) + wl-clipboard (wl-copy). Toggle via IPC:
//   qs ipc call clipboard toggle
// Bound to Super+C in niri.

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // SIVA voice assistant overlays (F8 assistant, F7 voicefetch, F9 dictation)
    Siva {}
    SivaVoicefetch {}
    SivaType {}
    SivaEnroll {}
    Stream {}   // live dual-monitor feed shown while SIVA operates agentically
    Wifi {}     // nmcli wifi picker; toggle via `qs ipc call wifi toggle` (waybar network click)
    Power {}    // power menu (logout/restart/shutdown/sleep); `qs ipc call power toggle` (waybar power click)
    Feathershot {}  // screenshot annotation overlay; opened by the `feathershot` CLI after slurp/grim

    property bool shown: false
    property var entries: []
    property string query: ""

    function filtered() {
        if (query.length === 0)
            return entries;
        var q = query.toLowerCase();
        return entries.filter(function (e) {
            return e.toLowerCase().indexOf(q) !== -1;
        });
    }

    function open() {
        query = "";
        listProc.running = true; // refresh history
        shown = true;
    }
    function close() {
        shown = false;
    }
    function toggle() {
        if (shown)
            close();
        else
            open();
    }

    function copyEntry(entry) {
        copyProc.entry = entry;
        copyProc.running = true;
        close();
    }

    // Called from the command line: `qs ipc call clipboard <fn>`
    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
    }

    // Read clipboard history
    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = this.text.split("\n").filter(function (l) {
                    return l.length > 0;
                });
            }
        }
    }

    // Decode the chosen entry back onto the clipboard
    Process {
        id: copyProc
        property string entry: ""
        command: ["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "cliphist-copy", entry]
    }

    PanelWindow {
        id: win
        visible: root.shown
        focusable: true
        color: "transparent"
        exclusiveZone: 0
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // click anywhere outside the box to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: 760
            height: 560
            color: "#000000"
            radius: 12
            border.color: "#00ff41"
            border.width: 2

            // swallow clicks so they don't reach the dismiss handler
            MouseArea {
                anchors.fill: parent
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Text {
                    text: "󰅍  Clipboard"
                    color: "#00ff41"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: 40
                    color: "#0a0a0a"
                    radius: 8
                    border.color: "#00ff41"
                    border.width: 1

                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.margins: 10
                        color: "#ffffff"
                        clip: true
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        focus: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.close()
                        // Enter copies the top match
                        Keys.onReturnPressed: {
                            var f = root.filtered();
                            if (f.length > 0)
                                root.copyEntry(f[0]);
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search…"
                            color: "#555555"
                            visible: search.text.length === 0
                            font: search.font
                        }
                    }
                }

                ListView {
                    id: listView
                    width: parent.width
                    height: parent.height - 100
                    clip: true
                    spacing: 4
                    model: root.filtered()

                    delegate: Rectangle {
                        width: listView.width
                        height: 38
                        radius: 6
                        color: hover.containsMouse ? "#00ff41" : "#0a0a0a"

                        Text {
                            anchors.fill: parent
                            anchors.margins: 8
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            // drop the leading "<id>\t" that cliphist prints
                            text: {
                                var i = modelData.indexOf("\t");
                                return i >= 0 ? modelData.substring(i + 1) : modelData;
                            }
                            color: hover.containsMouse ? "#000000" : "#ffffff"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.copyEntry(modelData)
                        }
                    }
                }
            }
        }

        // focus the search box each time the picker opens
        onVisibleChanged: if (visible)
            search.forceActiveFocus()
    }
}
