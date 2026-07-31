// Feathershot MKII — screenshot annotation overlay.
// OLED black / white / neon-green (#00ff41), chrome at ~68% opacity.
//
// Upstream: https://github.com/r3dg0d/feathershot (qml/Feathershot.qml).
// This is a working copy — changes worth keeping belong upstream too, or the
// two drift apart.
//
// The `feathershot` CLI captures with slurp/grim, then hands the PNG over:
//   qs ipc call feathershot open '{"image":"/tmp/…","width":…,"height":…}'
// Because this lives in the always-running `qs`, the editor appears the
// instant the selection is released — nothing is spawned.
//
// Shapes are tracked in *image* coordinates, never display coordinates, so the
// preview can be scaled down while the saved PNG stays native resolution:
// on save/copy the shape list goes back to `feathershot --render`, which
// replays it onto the original capture with cairo.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ── palette (matches shell.qml / Power.qml / Wifi.qml) ────────────
    readonly property color cAccent: "#00ff41"
    readonly property color cText:   "#ffffff"
    readonly property color cDim:    "#555555"
    readonly property color cDanger: "#ff2b2b"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // How opaque the widget chrome is. The screenshot itself stays fully
    // opaque — this is an alpha on the panel *colours*, not an `opacity` on
    // the item tree, precisely so the thing you're annotating stays crisp.
    readonly property real chromeAlpha: 0.68
    readonly property color cBg:    Qt.rgba(0, 0, 0, chromeAlpha)
    readonly property color cPanel: Qt.rgba(0.04, 0.04, 0.04, chromeAlpha)

    // ── capture state ─────────────────────────────────────────────────
    property bool shown: false
    property string imagePath: ""
    property int imgW: 0
    property int imgH: 0
    property string title: ""
    property string outDir: ""
    property bool isTemp: false

    // ── drawing state ─────────────────────────────────────────────────
    property string tool: "arrow"
    property color drawColor: "#ff2b2b"
    property int strokeWidth: 4

    // Text size in *image* pixels, independent of stroke width. Change the
    // default here; the toolbar picks from `fontSizes` at runtime.
    property int fontSize: 28
    property var shapes: []      // committed, image coords
    property var current: null   // in-flight drag
    property bool textActive: false
    property real textX: 0
    property real textY: 0

    readonly property var tools: [
        { id: "arrow",  glyph: "↗", label: "Arrow"  },
        { id: "box",    glyph: "▭", label: "Box"    },
        { id: "circle", glyph: "◯", label: "Circle" },
        { id: "line",   glyph: "／", label: "Line"   },
        { id: "pen",    glyph: "✎", label: "Pen"    },
        { id: "text",   glyph: "T", label: "Text"   }
    ]
    readonly property var palette: [
        "#ff2b2b", "#00ff41", "#ffd400", "#00d0ff", "#ff00d0", "#ffffff", "#000000"
    ]
    readonly property var widths: [2, 4, 6, 10, 16]
    readonly property var fontSizes: [14, 20, 28, 40, 56]

    // ── preview geometry ──────────────────────────────────────────────
    // Fit the capture inside a sane fraction of the screen; never upscale.
    readonly property real availW: win.screen ? win.screen.width * 0.70 : 1280
    readonly property real availH: win.screen ? win.screen.height * 0.62 : 720
    readonly property real fit: (imgW > 0 && imgH > 0)
        ? Math.min(1, Math.min(availW / imgW, availH / imgH)) : 1
    readonly property real stageW: imgW * fit
    readonly property real stageH: imgH * fit
    readonly property real contentW: Math.max(stageW, 660)

    // ── open / close ──────────────────────────────────────────────────
    function openSpec(raw) {
        var s = JSON.parse(raw);
        imagePath = s.image;
        imgW = s.width;
        imgH = s.height;
        title = s.title || "";
        outDir = s.out_dir || "";
        isTemp = !!s.temp;
        shapes = [];
        current = null;
        textActive = false;
        tool = "arrow";
        shown = true;
        canvas.requestPaint();
    }

    // discardShot: throw the capture away (Esc / Discard), as opposed to
    // handing ownership of the temp file to the renderer.
    function dismiss(discardShot) {
        if (discardShot && isTemp && imagePath !== "") {
            discardProc.command = ["feathershot", "--discard", imagePath];
            discardProc.running = true;
        }
        shown = false;
        textActive = false;
        current = null;
        shapes = [];
        imagePath = "";
    }

    // Called from the command line: `qs ipc call feathershot <fn>`
    IpcHandler {
        target: "feathershot"
        function open(spec: string): void { root.openSpec(spec); }
        function close(): void { root.dismiss(true); }
    }

    Process { id: renderProc }
    Process { id: discardProc }

    // ── editing ───────────────────────────────────────────────────────
    function beginShape(x, y) {
        if (tool === "text") {
            textX = x;
            textY = y;
            textActive = true;
            textField.text = "";
            textField.forceActiveFocus();
            return;
        }
        current = {
            tool: tool,
            color: [drawColor.r, drawColor.g, drawColor.b, drawColor.a],
            width: strokeWidth,
            points: [[x, y]],
            text: ""
        };
    }

    function extendShape(x, y) {
        if (!current)
            return;
        if (current.tool === "pen") {
            // decimate: a 4k drag would otherwise be tens of thousands of points
            var last = current.points[current.points.length - 1];
            if (Math.abs(x - last[0]) + Math.abs(y - last[1]) < 1.5)
                return;
            current.points.push([x, y]);
        } else if (current.points.length < 2) {
            current.points.push([x, y]);
        } else {
            current.points[1] = [x, y];
        }
        canvas.requestPaint();
    }

    function commitShape() {
        if (!current)
            return;
        if (current.points.length >= 2)
            shapes = shapes.concat([current]);
        current = null;
        canvas.requestPaint();
    }

    function commitText() {
        var t = textField.text;
        textActive = false;
        if (t.length > 0) {
            shapes = shapes.concat([{
                tool: "text",
                color: [drawColor.r, drawColor.g, drawColor.b, drawColor.a],
                width: strokeWidth,
                fontSize: fontSize,
                points: [[textX, textY]],
                text: t
            }]);
        }
        canvas.requestPaint();
    }

    function undo() {
        if (shapes.length > 0) {
            shapes = shapes.slice(0, shapes.length - 1);
            canvas.requestPaint();
        }
    }

    function clearAll() {
        shapes = [];
        current = null;
        canvas.requestPaint();
    }

    // ── save / copy ───────────────────────────────────────────────────
    function submit(action) {
        if (imagePath === "")
            return;
        renderProc.environment = {
            "FEATHERSHOT_SPEC": JSON.stringify({
                image: imagePath,
                out_dir: outDir,
                title: title,
                temp: isTemp,
                action: action,
                shapes: shapes
            })
        };
        renderProc.command = ["feathershot", "--render"];
        renderProc.running = true;
        dismiss(false);   // the renderer owns the temp file now
    }

    // ── canvas painting ───────────────────────────────────────────────
    // Mirrors Annotation.draw() in feathershot.py so the preview and the
    // rendered PNG agree. Canvas2D fillText and cairo show_text share the
    // alphabetic baseline, and both use round caps/joins.
    function paintShape(ctx, s) {
        var c = Qt.rgba(s.color[0], s.color[1], s.color[2], s.color[3]);
        ctx.strokeStyle = c;
        ctx.fillStyle = c;
        ctx.lineWidth = s.width;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        var p = s.points;
        if (s.tool === "pen") {
            if (p.length < 2)
                return;
            ctx.beginPath();
            ctx.moveTo(p[0][0], p[0][1]);
            for (var i = 1; i < p.length; i++)
                ctx.lineTo(p[i][0], p[i][1]);
            ctx.stroke();
            return;
        }

        if (s.tool === "text") {
            if (s.text === "" || p.length === 0)
                return;
            // pre-fontSize shapes fell back to stroke width; keep that path
            var px = s.fontSize > 0 ? s.fontSize : Math.max(14, s.width * 6);
            ctx.font = "bold " + px + "px sans-serif";
            ctx.fillText(s.text, p[0][0], p[0][1]);
            return;
        }

        if (p.length < 2)
            return;
        var x0 = p[0][0], y0 = p[0][1];
        var x1 = p[p.length - 1][0], y1 = p[p.length - 1][1];

        ctx.beginPath();
        if (s.tool === "box") {
            ctx.rect(Math.min(x0, x1), Math.min(y0, y1),
                     Math.abs(x1 - x0), Math.abs(y1 - y0));
            ctx.stroke();
        } else if (s.tool === "circle") {
            if (Math.abs(x1 - x0) < 2 || Math.abs(y1 - y0) < 2)
                return;
            ctx.ellipse(Math.min(x0, x1), Math.min(y0, y1),
                        Math.abs(x1 - x0), Math.abs(y1 - y0));
            ctx.stroke();
        } else if (s.tool === "line") {
            ctx.moveTo(x0, y0);
            ctx.lineTo(x1, y1);
            ctx.stroke();
        } else if (s.tool === "arrow") {
            ctx.moveTo(x0, y0);
            ctx.lineTo(x1, y1);
            ctx.stroke();
            var ang = Math.atan2(y1 - y0, x1 - x0);
            var head = 12 + s.width * 2.5;
            var spread = 28 * Math.PI / 180;
            ctx.beginPath();
            for (var k = -1; k <= 1; k += 2) {
                ctx.moveTo(x1, y1);
                ctx.lineTo(x1 - head * Math.cos(ang - k * spread),
                           y1 - head * Math.sin(ang - k * spread));
            }
            ctx.stroke();
        }
    }

    // ── keyboard ──────────────────────────────────────────────────────
    readonly property var keyTools: {
        var m = {};
        m[Qt.Key_A] = "arrow";
        m[Qt.Key_B] = "box";
        m[Qt.Key_C] = "circle";
        m[Qt.Key_L] = "line";
        m[Qt.Key_P] = "pen";
        m[Qt.Key_T] = "text";
        return m;
    }

    function handleKey(e) {
        if (textActive)
            return;
        if (e.key === Qt.Key_Escape) {
            dismiss(true);
            e.accepted = true;
            return;
        }
        if (e.modifiers & Qt.ControlModifier) {
            if (e.key === Qt.Key_Z) {
                undo();
                e.accepted = true;
            } else if (e.key === Qt.Key_S) {
                submit("save");
                e.accepted = true;
            } else if (e.key === Qt.Key_C) {
                submit("copy");
                e.accepted = true;
            }
            return;
        }
        var t = keyTools[e.key];
        if (t !== undefined) {
            tool = t;
            e.accepted = true;
        }
    }

    // ── reusable chrome ───────────────────────────────────────────────
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property string glyph: ""
        property bool active: false
        property color tint: root.cAccent
        signal activated

        implicitWidth: pillRow.implicitWidth + 22
        implicitHeight: 30
        radius: 6
        color: active ? tint : (pillArea.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, 0.22)
                                                       : root.cPanel)
        border.color: active || pillArea.containsMouse ? tint : root.cDim
        border.width: 1

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.glyph !== ""
                text: pill.glyph
                color: pill.active ? "#000000" : pill.tint
                font.family: root.mono
                font.pixelSize: 14
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.label !== ""
                text: pill.label
                color: pill.active ? "#000000" : root.cText
                font.family: root.mono
                font.pixelSize: 12
                font.bold: true
            }
        }

        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.activated()
        }
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
        WlrLayershell.namespace: "quickshell-feathershot"

        // Deliberately no click-outside-to-dismiss: fat-fingering the desktop
        // and losing the capture would be worse than having to press Esc.
        MouseArea { anchors.fill: parent }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => root.handleKey(e)

            Rectangle {
                id: box
                anchors.centerIn: parent
                width: root.contentW + 28
                height: header.height + root.stageH + toolbar.height
                        + actions.height + 3 * 12 + 28
                color: root.cBg
                radius: 14
                border.color: root.cAccent
                border.width: 2

                opacity: root.shown ? 1 : 0
                scale: root.shown ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // ── header ────────────────────────────────────────
                    Item {
                        id: header
                        width: parent.width
                        height: 24

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰄀  Feathershot MKII"
                            color: root.cAccent
                            font.family: root.mono
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.imgW + "×" + root.imgH
                                  + (root.fit < 1 ? "   ·   " + Math.round(root.fit * 100) + "%" : "")
                                  + "   ·   " + root.shapes.length
                                  + (root.shapes.length === 1 ? " mark" : " marks")
                            color: root.cDim
                            font.family: root.mono
                            font.pixelSize: 12
                        }
                    }

                    // ── the display box ───────────────────────────────
                    Rectangle {
                        width: parent.width
                        height: root.stageH + 2
                        color: "#000000"
                        radius: 6
                        border.color: root.cDim
                        border.width: 1

                        Item {
                            id: stage
                            anchors.centerIn: parent
                            width: root.stageW
                            height: root.stageH
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: root.imagePath === "" ? "" : "file://" + root.imagePath
                                cache: false
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }

                            Canvas {
                                id: canvas
                                anchors.fill: parent
                                renderStrategy: Canvas.Cooperative
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.save();
                                    // draw in image coords; the scale also
                                    // scales stroke widths, which is what we
                                    // want the preview to show
                                    ctx.scale(root.fit, root.fit);
                                    for (var i = 0; i < root.shapes.length; i++)
                                        root.paintShape(ctx, root.shapes[i]);
                                    if (root.current)
                                        root.paintShape(ctx, root.current);
                                    ctx.restore();
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.CrossCursor
                                onPressed: m => root.beginShape(m.x / root.fit, m.y / root.fit)
                                onPositionChanged: m => {
                                    if (pressed)
                                        root.extendShape(m.x / root.fit, m.y / root.fit);
                                }
                                onReleased: root.commitShape()
                            }

                            // inline text entry for the text tool
                            Rectangle {
                                visible: root.textActive
                                x: Math.min(root.textX * root.fit,
                                            stage.width - width)
                                y: Math.max(0, root.textY * root.fit - height)
                                width: 240
                                height: textField.font.pixelSize + 16
                                color: Qt.rgba(0, 0, 0, 0.85)
                                border.color: root.cAccent
                                border.width: 1
                                radius: 4

                                TextInput {
                                    id: textField
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    color: root.cText
                                    clip: true
                                    font.family: root.mono
                                    // roughly what the annotation will look
                                    // like once placed, clamped to stay usable
                                    font.pixelSize: Math.max(11, Math.min(22, root.fontSize * root.fit))
                                    onAccepted: root.commitText()
                                    Keys.onEscapePressed: root.textActive = false

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: textField.text.length === 0
                                        text: "type, then Enter…"
                                        color: root.cDim
                                        font: textField.font
                                    }
                                }
                            }
                        }
                    }

                    // ── toolbar: tools · colours · widths · text size ─
                    // A Flow, not a Row: on a narrow capture the box is only
                    // as wide as the preview, and these controls wrap onto a
                    // second line instead of running off the edge.
                    Flow {
                        id: toolbar
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.tools
                            delegate: Pill {
                                glyph: modelData.glyph
                                label: modelData.label
                                active: root.tool === modelData.id
                                onActivated: root.tool = modelData.id
                            }
                        }

                        Rectangle { width: 1; height: 30; color: root.cDim }

                        Repeater {
                            model: root.palette
                            delegate: Item {
                                width: 26
                                height: 30

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: modelData
                                    border.color: root.drawColor === modelData ? root.cAccent : root.cDim
                                    border.width: root.drawColor === modelData ? 3 : 1
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.drawColor = modelData
                                }
                            }
                        }

                        Rectangle { width: 1; height: 30; color: root.cDim }

                        Repeater {
                            model: root.widths
                            delegate: Rectangle {
                                width: 26
                                height: 30
                                radius: 6
                                color: root.strokeWidth === modelData
                                     ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.22)
                                     : "transparent"
                                border.color: root.strokeWidth === modelData ? root.cAccent : "transparent"
                                border.width: 1

                                // a dot the size of the stroke it selects
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Math.min(16, 3 + modelData)
                                    height: width
                                    radius: width / 2
                                    color: root.strokeWidth === modelData ? root.cAccent : root.cText
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.strokeWidth = modelData
                                }
                            }
                        }

                        Rectangle { width: 1; height: 30; color: root.cDim }

                        // text size, in image pixels — independent of stroke
                        Repeater {
                            model: root.fontSizes
                            delegate: Pill {
                                glyph: index === 0 ? "T" : ""
                                label: String(modelData)
                                active: root.fontSize === modelData
                                onActivated: root.fontSize = modelData
                            }
                        }
                    }

                    // ── actions ───────────────────────────────────────
                    Item {
                        id: actions
                        width: parent.width
                        height: 30

                        Row {
                            id: leftActions
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Pill {
                                label: "Undo"
                                glyph: "󰕌"
                                enabled: root.shapes.length > 0
                                opacity: enabled ? 1 : 0.4
                                onActivated: root.undo()
                            }
                            Pill {
                                label: "Clear"
                                glyph: "󰩹"
                                enabled: root.shapes.length > 0
                                opacity: enabled ? 1 : 0.4
                                onActivated: root.clearAll()
                            }
                        }

                        Row {
                            id: rightActions
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Pill {
                                label: "Discard"
                                glyph: "󰅖"
                                tint: root.cDanger
                                onActivated: root.dismiss(true)
                            }
                            Pill {
                                label: "Copy"
                                glyph: "󰅍"
                                onActivated: root.submit("copy")
                            }
                            Pill {
                                label: "Save"
                                glyph: "󰆓"
                                active: true
                                onActivated: root.submit("save")
                            }
                        }

                        // fills whatever gap is left between the two groups,
                        // and elides rather than colliding with them
                        Text {
                            anchors.left: leftActions.right
                            anchors.right: rightActions.left
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "a b c l p t · ⌃Z undo · ⌃S save · ⌃C copy · Esc discard"
                            color: root.cDim
                            font.family: root.mono
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        onVisibleChanged: if (visible) {
            keys.forceActiveFocus();
            canvas.requestPaint();
        }
    }
}
