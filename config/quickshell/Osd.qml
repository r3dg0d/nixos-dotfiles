// Quickshell on-screen display — the visual behind every Fn + F1…F12 key.
//
//   qs ipc call osd notify '{"kind":"bar","icon":"󰕾","label":"Volume","value":63}'
//   qs ipc call osd notify '{"kind":"toast","icon":"󰐊","label":"Playing","sub":"…"}'
//
// The payload comes from `fnkey` (pkgs/fnkeys), which performs the action and
// then reports the state the system actually landed in. Nothing here drives
// hardware: the OSD is a display, so a missed IPC call costs a notification,
// never a keypress.
//
// Two shapes:
//   bar   — brightness / volume: a segmented meter with a live percentage
//   toast — mute switches, transport, webcam: icon + label + one detail line
//
// Rendering notes: 75% black over the desktop with a neon-green (#00ff41)
// glow, built out of stacked translucent rectangles rather than a blur shader
// so it costs nothing and needs no QtQuick.Effects import. Corner brackets and
// scanlines are the hacker-terminal half of the look.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ── palette (matches Power.qml / Clipboard.qml / Wifi.qml) ────────
    readonly property color cAccent: "#00ff41"
    readonly property color cText:   "#ffffff"
    readonly property color cDim:    "#555555"

    // The panel is only 75% opaque, so whatever is behind it competes with the
    // text. #555 disappears against a busy wallpaper; the detail line uses
    // this instead.
    readonly property color cHint:   "#8a8a8a"
    readonly property color cDanger: "#ff2b2b"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // The panel background is 75% black — the desktop stays legible behind it.
    // Applied as the backdrop layer's opacity rather than an alpha colour;
    // see the note on `backdrop` below for why that distinction matters.
    readonly property real glassOpacity: 0.75

    // ── state ─────────────────────────────────────────────────────────
    property bool   shown:  false
    property string kind:   "bar"      // "bar" | "toast"
    property string icon:   ""
    property string label:  ""
    property string sub:    ""
    property int    value:  0
    property bool   muted:  false

    // A muted channel greys out: the meter is still the truth, but the accent
    // colour is what the eye reads first, so it has to stop being green.
    readonly property color tint: muted ? cDanger : cAccent

    readonly property int segments: 32
    readonly property int litSegments: Math.round(value / 100 * segments)

    // ── IPC ───────────────────────────────────────────────────────────
    // One entry point. `payload` is the JSON object described at the top.
    //
    // Deliberately *not* called `show`: `qs ipc show` is itself a subcommand,
    // so `qs ipc call osd show <json>` gets parsed as that subcommand and the
    // payload is rejected as an unexpected argument. The action still happened
    // — only the OSD went missing — which makes it a quiet failure worth
    // naming around rather than rediscovering.
    IpcHandler {
        target: "osd"

        function notify(payload: string): void { root.present(payload); }
        function hide(): void { root.shown = false; }
    }

    function present(payload) {
        var d;
        try {
            d = JSON.parse(payload);
        } catch (e) {
            console.warn("osd: bad payload:", payload);
            return;
        }

        kind  = d.kind  || "bar";
        icon  = d.icon  || "";
        label = d.label || "";
        sub   = d.sub   || "";
        muted = d.muted === true;
        value = Math.max(0, Math.min(100, d.value || 0));

        shown = true;
        // Restart rather than extend: holding volume-up should keep the panel
        // up for as long as the key is down, then dismiss once.
        dismiss.restart();
    }

    Timer {
        id: dismiss
        interval: 1800
        onTriggered: root.shown = false
    }

    // ── UI ────────────────────────────────────────────────────────────
    // One panel per monitor. Volume and brightness are global to the machine,
    // and on a two-ultrawide desk the eye is as likely to be on one as on the
    // other, so the feedback goes to both rather than gambling on a "primary".
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            // Kept mapped through the fade so the exit animation can actually
            // run; `shown` only drives opacity and the slide.
            visible: root.shown || panel.opacity > 0.01
            color: "transparent"
            exclusiveZone: 0
            anchors { left: true; right: true; bottom: true }
            implicitHeight: 220

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-osd"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Click-through: an OSD that eats a click on whatever is under it
            // is worse than no OSD. An empty mask means "no input region".
            mask: Region {}

            Item {
                id: panel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                width: 460
                height: root.kind === "bar" ? 132 : 108

                opacity: root.shown ? 1 : 0
                // Rises into place and sinks on the way out.
                anchors.bottomMargin: root.shown ? 64 : 46

                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on height  { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on anchors.bottomMargin {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                // ── the gradient edge ─────────────────────────────────
                // The same white → neon-green sweep niri now draws around
                // focused windows, so the OSD reads as part of the same
                // system rather than a widget with its own halo.
                //
                // Rectangle has no gradient *border*, so the frame is a
                // gradient-filled rounded rect with the panel fill laid 2px
                // inside it, leaving the sweep showing as the edge.
                //
                // `layer.enabled` is what makes that work over a translucent
                // panel. Composite the two rects into one texture *first* and
                // fade that: the opaque inner fill then hides the gradient
                // behind it, and the 75% applies to the finished frame. Drop
                // the layer and the gradient shows straight through the fill,
                // washing the whole panel green.
                Item {
                    id: backdrop
                    anchors.fill: parent
                    layer.enabled: true
                    opacity: root.glassOpacity

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.muted ? "#ffd6d6" : "#ffffff" }
                            GradientStop { position: 1.0; color: root.tint }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 12
                        color: "#000000"
                    }
                }

                // ── panel contents ────────────────────────────────────
                // Full opacity, on top of the faded backdrop: the 75% is the
                // background, not the readout.
                Item {
                    id: glass
                    anchors.fill: parent
                    anchors.margins: 2

                    // Scanlines: 2px on, 2px off, barely there. Clipped to the
                    // panel's rounding so they do not spill past the corners.
                    Item {
                        anchors.fill: parent
                        clip: true
                        opacity: 0.05

                        Column {
                            width: parent.width
                            spacing: 2
                            Repeater {
                                model: Math.ceil(glass.height / 4)
                                delegate: Rectangle {
                                    width: glass.width
                                    height: 2
                                    color: root.tint
                                }
                            }
                        }
                    }

                    // Corner brackets — the terminal-HUD detail.
                    Repeater {
                        model: [
                            { hx: "left",  hy: "top" },
                            { hx: "right", hy: "top" },
                            { hx: "left",  hy: "bottom" },
                            { hx: "right", hy: "bottom" }
                        ]
                        delegate: Item {
                            id: bracket
                            required property var modelData

                            readonly property bool atLeft: modelData.hx === "left"
                            readonly property bool atTop:  modelData.hy === "top"

                            width: 14
                            height: 14
                            anchors.left:   atLeft  ? parent.left   : undefined
                            anchors.right:  atLeft  ? undefined     : parent.right
                            anchors.top:    atTop   ? parent.top    : undefined
                            anchors.bottom: atTop   ? undefined     : parent.bottom
                            anchors.margins: 7

                            Rectangle {   // horizontal arm
                                width: parent.width; height: 2
                                color: root.tint
                                anchors.left:   bracket.atLeft ? parent.left : undefined
                                anchors.right:  bracket.atLeft ? undefined   : parent.right
                                anchors.top:    bracket.atTop  ? parent.top  : undefined
                                anchors.bottom: bracket.atTop  ? undefined   : parent.bottom
                            }
                            Rectangle {   // vertical arm
                                width: 2; height: parent.height
                                color: root.tint
                                anchors.left:   bracket.atLeft ? parent.left : undefined
                                anchors.right:  bracket.atLeft ? undefined   : parent.right
                                anchors.top:    bracket.atTop  ? parent.top  : undefined
                                anchors.bottom: bracket.atTop  ? undefined   : parent.bottom
                            }
                        }
                    }

                    // ── content ───────────────────────────────────────
                    Row {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 18

                        // Icon, with its own halo: the same glyph drawn
                        // oversized and nearly transparent behind the crisp one.
                        Item {
                            width: 56
                            height: parent.height
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: root.icon
                                color: root.tint
                                opacity: 0.28
                                font.family: root.mono
                                font.pixelSize: 46
                                scale: 1.25
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.icon
                                color: root.tint
                                font.family: root.mono
                                font.pixelSize: 38
                            }
                        }

                        Column {
                            width: parent.width - 56 - 18
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // Header: label on the left, reading on the right.
                            Item {
                                width: parent.width
                                height: 20

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.label.toUpperCase()
                                    color: root.cText
                                    font.family: root.mono
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.letterSpacing: 2.5
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.kind === "bar"
                                    text: root.muted ? "MUTED" : root.value + "%"
                                    color: root.tint
                                    font.family: root.mono
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }

                            // ── bar: a segmented meter ────────────────
                            // Discrete cells rather than a smooth fill — it
                            // reads as an instrument, and every press visibly
                            // moves it.
                            Row {
                                id: meter
                                visible: root.kind === "bar"
                                width: parent.width
                                spacing: 3

                                Repeater {
                                    model: root.segments
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property bool lit: index < root.litSegments

                                        width: (meter.width - (root.segments - 1) * 3) / root.segments
                                        height: 16
                                        radius: 1
                                        color: lit ? root.tint : "#141414"
                                        // Only the lit cells glow, and the
                                        // leading one brightest, so the eye
                                        // tracks the edge.
                                        opacity: !lit ? 1
                                                      : (index === root.litSegments - 1 ? 1 : 0.72)

                                        border.width: lit ? 0 : 1
                                        border.color: "#1f1f1f"

                                        Behavior on color   { ColorAnimation { duration: 90 } }
                                        Behavior on opacity { NumberAnimation { duration: 90 } }
                                    }
                                }
                            }

                            // ── toast: one detail line ────────────────
                            Text {
                                visible: root.kind === "toast"
                                width: parent.width
                                text: root.sub
                                color: root.muted ? root.cDanger : root.cHint
                                font.family: root.mono
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
