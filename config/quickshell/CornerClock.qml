// Desktop clock — bottom-left, sits above wallpaper but beneath all windows
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    anchors { bottom: true; left: true }
    margins { bottom: 30; left: 30 }

    width:  240
    height: 88

    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom

    property var now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat:  true
        onTriggered: root.now = new Date()
    }

    readonly property var _days:   ["Sunday","Monday","Tuesday","Wednesday",
                                    "Thursday","Friday","Saturday"]
    readonly property var _months: ["January","February","March","April","May","June",
                                    "July","August","September","October","November","December"]

    Column {
        anchors { left: parent.left; bottom: parent.bottom }
        spacing: 0

        // Day + date
        Text {
            text: root._days[root.now.getDay()] + "  ·  "
                + root._months[root.now.getMonth()] + " " + root.now.getDate()
            color: "#404040"
            font { family: "JetBrains Mono Nerd Font"; pixelSize: 13; weight: Font.Light }
        }

        // Time
        Text {
            property string hh: root.now.getHours().toString().padStart(2, "0")
            property string mm: root.now.getMinutes().toString().padStart(2, "0")
            text:  hh + ":" + mm
            color: "#fcba03"
            font { family: "JetBrains Mono Nerd Font"; pixelSize: 52; bold: true }

            // Subtle opacity pulse on the minute tick
            SequentialAnimation on opacity {
                running: true
                loops:   1
                id: tickAnim
                NumberAnimation { to: 0.6; duration: 80 }
                NumberAnimation { to: 1.0; duration: 200 }
            }

            Connections {
                target: root
                function onNowChanged() {
                    if (root.now.getSeconds() === 0) tickAnim.restart()
                }
            }
        }
    }
}
