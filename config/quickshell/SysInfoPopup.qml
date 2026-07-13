// System info popup — toggled by writing "1"/"0" to /tmp/qs-sysinfo-show
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    // ── state ─────────────────────────────────────────────────────────
    property bool popupVisible: false
    property var stats: ({
        cpu_usage: "--", cpu_temp: "--",
        ram_used:  "--", ram_total: "--", ram_pct: "--",
        disk_used: "--", disk_total: "--", disk_pct: "--",
        gpu_util:  "--", gpu_temp: "--",
        gpu_mem_used: "--", gpu_mem_total: "--"
    })

    // ── window props ───────────────────────────────────────────────────
    visible: popupVisible
    exclusiveZone: 0
    width:  290
    height: 240
    color:  "transparent"

    anchors {
        top:   true
        right: true
    }
    margins {
        top:   58
        right: 178    // align under the sysinfo button in the bar
    }

    // ── IPC: poll /tmp/qs-sysinfo-show every 150 ms ───────────────────
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: ipcFile.reload()
    }

    FileView {
        id: ipcFile
        path: "/tmp/qs-sysinfo-show"
        onDataChanged: {
            var show = ipcFile.text().trim() === "1"
            root.popupVisible = show
            if (show) { statsProc.running = true; refreshTimer.start() }
            else       { refreshTimer.stop() }
        }
    }

    // ── refresh stats every 2 s while visible ─────────────────────────
    Timer {
        id: refreshTimer
        interval: 2000; repeat: true
        onTriggered: statsProc.running = true
    }

    Process {
        id: statsProc
        command: ["/home/r3dg0d/.local/bin/qs-sysinfo"]
        property string _buf: ""

        stdout: SplitParser {
            onRead: function(line) { statsProc._buf += line }
        }

        onRunningChanged: {
            if (!running && _buf.length > 0) {
                try { root.stats = JSON.parse(_buf) } catch(e) {}
                _buf = ""
            }
        }
    }

    // ── UI ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:        "#f0000000"
        border.color: "#fcba03"
        border.width: 1
        radius:       12

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 8

            // Header
            Text {
                text: "  System Info"
                color: "#fcba03"
                font { family: "JetBrains Mono Nerd Font"; pixelSize: 13; bold: true }
            }

            Rectangle { height: 1; color: "#1ffcba03"; Layout.fillWidth: true }

            // Row helper component inlined via Repeater
            Repeater {
                model: [
                    { icon: " CPU ", val: root.stats.cpu_usage + "%",    warn: parseInt(root.stats.cpu_usage),  suffix: "  " + root.stats.cpu_temp + "°C" },
                    { icon: "󰍛 GPU ", val: root.stats.gpu_util + "%",    warn: parseInt(root.stats.gpu_util),   suffix: "  " + root.stats.gpu_temp + "°C" },
                    { icon: " RAM ", val: root.stats.ram_used,            warn: parseInt(root.stats.ram_pct),    suffix: " / " + root.stats.ram_total + "  (" + root.stats.ram_pct + "%)" },
                    { icon: "󰾲 VRAM", val: root.stats.gpu_mem_used,      warn: 0,                               suffix: " / " + root.stats.gpu_mem_total },
                    { icon: "󰋊 Disk", val: root.stats.disk_used,         warn: parseInt(root.stats.disk_pct),   suffix: " / " + root.stats.disk_total + " (" + root.stats.disk_pct + "%)" }
                ]

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: modelData.icon
                        color: "#666666"
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 12 }
                        Layout.preferredWidth: 58
                    }
                    Text {
                        text: modelData.val
                        color: modelData.warn > 85 ? "#ff2020" : modelData.warn > 65 ? "#fcba03" : "#ffffff"
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 12 }
                        Layout.preferredWidth: 56
                    }
                    Text {
                        text: modelData.suffix
                        color: "#555555"
                        font { family: "JetBrains Mono Nerd Font"; pixelSize: 12 }
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
