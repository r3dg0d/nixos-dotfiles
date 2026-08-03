pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import QtQuick.Effects
import Quickshell

FloatingWindow {
    id: win

    property int diameter: 320
    property int minDiameter: 160
    property int maxDiameter: 1360
    property bool mirrored: true
    property var camera
    property bool cameraActive: false
    property string statusText: ""
    property string errorText: ""

    title: "Mirror"
    visible: false
    color: "transparent"
    surfaceFormat.opaque: false
    minimumSize: Qt.size(minDiameter, minDiameter)
    maximumSize: Qt.size(maxDiameter, maxDiameter)
    implicitWidth: diameter
    implicitHeight: diameter

    function showMirror(): void {
        visible = true;
    }

    function hideMirror(): void {
        video.clearOutput();
        visible = false;
    }

    function snapSquare(): void {
        const next = Math.max(minDiameter, Math.min(maxDiameter, Math.round(Math.max(width, height))));
        if (diameter !== next)
            diameter = next;
    }

    onWidthChanged: if (visible) snapTimer.restart()
    onHeightChanged: if (visible) snapTimer.restart()

    Timer {
        id: snapTimer
        interval: 80
        repeat: false
        onTriggered: win.snapSquare()
    }

    Item {
        id: rootItem
        anchors.fill: parent
        visible: win.visible

        readonly property real contentMargin: 0
        readonly property real handleSize: Math.max(10, Math.min(16, win.diameter * 0.045))

        Item {
            id: videoShell
            anchors.fill: parent
            anchors.margins: rootItem.contentMargin

            Rectangle {
                id: startupGuard
                anchors.fill: parent
                radius: width / 2
                color: "#000000"
                visible: !win.cameraActive || win.errorText.length > 0
                antialiasing: true
            }

            CaptureSession {
                camera: win.camera
                videoOutput: video
            }

            Rectangle {
                id: circleMask
                anchors.fill: parent
                radius: width / 2
                color: "white"
                visible: false
                antialiasing: true
                layer.enabled: true
                layer.smooth: true
                layer.samples: 8
            }

            Item {
                id: maskedVideoLayer
                anchors.fill: parent
                visible: win.cameraActive && win.errorText.length === 0
                clip: true
                layer.enabled: visible
                layer.smooth: true
                layer.samples: 8
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: circleMask
                    maskThresholdMin: 0.0
                    maskSpreadAtMin: 0.04
                }

                VideoOutput {
                    id: video
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    mirrored: win.mirrored
                    endOfStreamPolicy: VideoOutput.ClearOutput
                    visible: true
                }
            }

            Item {
                anchors.fill: parent
                visible: win.errorText.length > 0

                Text {
                    anchors.centerIn: parent
                    width: parent.width * 0.74
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "󰄀\n" + (win.errorText.length > 0 ? win.errorText : "Camera unavailable")
                    color: "#ff2b2b"
                    wrapMode: Text.WordWrap
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.max(13, Math.min(20, win.diameter * 0.055))
                    font.bold: true
                }
            }

            Item {
                anchors.fill: parent
                visible: !win.cameraActive && win.errorText.length === 0

                Text {
                    anchors.centerIn: parent
                    width: parent.width * 0.76
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "󰄀\n" + (win.statusText.length > 0 ? win.statusText : "Starting camera")
                    color: "#00ff41"
                    wrapMode: Text.WordWrap
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.max(12, Math.min(18, win.diameter * 0.045))
                    font.bold: true
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.OpenHandCursor
                onPressed: function(mouse) {
                    cursorShape = Qt.ClosedHandCursor;
                    win.startSystemMove();
                    mouse.accepted = true;
                }
                onReleased: cursorShape = Qt.OpenHandCursor
                onCanceled: cursorShape = Qt.OpenHandCursor
            }
        }

        ResizeHandle {
            edge: Qt.LeftEdge
            window: win
            thickness: rootItem.handleSize
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }

        ResizeHandle {
            edge: Qt.RightEdge
            window: win
            thickness: rootItem.handleSize
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }

        ResizeHandle {
            edge: Qt.TopEdge
            window: win
            thickness: rootItem.handleSize
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
        }

        ResizeHandle {
            edge: Qt.BottomEdge
            window: win
            thickness: rootItem.handleSize
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }
    }
}
