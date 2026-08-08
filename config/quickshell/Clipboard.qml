// Quickshell clipboard manager — OLED black / white / neon-green (#00ff41).
// Backend: cliphist (history) + wl-clipboard (wl-copy). Toggle via IPC:
//   qs ipc call clipboard toggle
// Bound to Mod+C in niri.
//
// cliphist stores images as well as text. `cliphist list` renders those as a
// placeholder line — "[[ binary data 12 KiB png 497x361 ]]" — so an image
// entry is recognised by that shape and decoded to a file under the runtime
// dir for the thumbnail. Decoding is lazy: only rows the ListView actually
// creates get written out, so opening the panel does not dump 750 clipboard
// images to disk.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ── palette (matches Power.qml / Wifi.qml) ────────────────────────
    readonly property color cBg:     "#000000"
    readonly property color cPanel:  "#0a0a0a"
    readonly property color cAccent: "#00ff41"
    readonly property color cText:   "#ffffff"
    readonly property color cDim:    "#555555"
    readonly property color cDanger: "#ff2b2b"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // ── state ─────────────────────────────────────────────────────────
    property bool   shown:   false
    property var    entries: []       // raw "<id>\t<preview>" lines from cliphist
    property string query:   ""
    property bool   confirmWipe: false   // second click arms the wipe

    // Where decoded thumbnails go. Runtime dir, so they never outlive the boot.
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cliphist-thumbs"

    // ── entry helpers ─────────────────────────────────────────────────
    function entryId(line) {
        var i = line.indexOf("\t");
        return i >= 0 ? line.substring(0, i) : "";
    }
    function entryText(line) {
        var i = line.indexOf("\t");
        return i >= 0 ? line.substring(i + 1) : line;
    }
    // "[[ binary data 12 KiB png 497x361 ]]" → the placeholder cliphist prints
    // for anything that is not text. Only the image types get a thumbnail.
    function isImage(line) {
        return /\[\[ binary data .*\b(png|jpe?g|gif|bmp|webp|tiff?)\b/i.test(entryText(line));
    }
    function imageMeta(line) {
        var m = entryText(line).match(/binary data\s+([\d.]+\s*\w+)\s+(\w+)\s+(\d+x\d+)/i);
        return m ? { size: m[1], kind: m[2], dims: m[3] } : null;
    }

    function filtered() {
        if (query.length === 0)
            return entries;
        var q = query.toLowerCase();
        return entries.filter(function (e) {
            return e.toLowerCase().indexOf(q) !== -1;
        });
    }

    // ── open / close ──────────────────────────────────────────────────
    function open() {
        query = "";
        confirmWipe = false;
        refresh();
        shown = true;
    }
    function close() {
        shown = false;
        confirmWipe = false;
    }
    function toggle() { shown ? close() : open(); }

    function refresh() { listProc.running = true; }

    // ── actions ───────────────────────────────────────────────────────
    function copyEntry(line) {
        copyProc.command = ["sh", "-c",
            "printf '%s' \"$1\" | cliphist decode | wl-copy", "cliphist-copy", line];
        copyProc.running = true;
        close();
    }

    // cliphist deletes by the whole list line on stdin, not by bare id.
    function deleteEntry(line) {
        // Drop it locally first so the row disappears immediately; the reload
        // below is what makes it authoritative.
        entries = entries.filter(function (e) { return e !== line; });
        deleteProc.command = ["sh", "-c",
            "printf '%s' \"$1\" | cliphist delete", "cliphist-delete", line];
        deleteProc.running = true;
    }

    function wipeAll() {
        entries = [];
        confirmWipe = false;
        wipeProc.running = true;
    }

    // Called from the command line: `qs ipc call clipboard <fn>`
    IpcHandler {
        target: "clipboard"
        function toggle():  void { root.toggle(); }
        function open():    void { root.open(); }
        function close():   void { root.close(); }
        function refresh(): void { root.refresh(); }
    }

    // ── processes ─────────────────────────────────────────────────────
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

    Process { id: copyProc }

    Process {
        id: deleteProc
        // Re-read rather than trust the optimistic local removal above.
        onExited: root.refresh()
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: root.refresh()
    }

    // Decodes one entry to thumbDir/<id>. Rows queue themselves here as they
    // scroll into existence; `mkdir -p` every time is cheaper than tracking
    // whether the directory already exists.
    Process {
        id: thumbProc
        property var queue: []
        property string current: ""

        function want(id) {
            if (id.length === 0 || queue.indexOf(id) !== -1 || current === id)
                return;
            queue.push(id);
            pump();
        }
        function pump() {
            if (running || queue.length === 0)
                return;
            current = queue.shift();
            command = ["sh", "-c",
                "mkdir -p \"$1\" && cliphist decode \"$2\" > \"$1/$2\"",
                "cliphist-thumb", root.thumbDir, current];
            running = true;
        }
        onExited: {
            // Bump the tick so every delegate re-evaluates its source binding;
            // the one that was waiting for this id picks the file up.
            root.thumbTick++;
            current = "";
            pump();
        }
    }
    property int thumbTick: 0

    // ── UI ────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.shown
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { top: true; bottom: true; left: true; right: true }

        // click anywhere outside the box to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: 820
            height: 620
            color: root.cBg
            radius: 12
            border.color: root.cAccent
            border.width: 2

            // swallow clicks so they don't reach the dismiss handler
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ── header: title + count + wipe ──────────────────────
                Item {
                    width: parent.width
                    height: 26

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰅍  Clipboard"
                        color: root.cAccent
                        font.family: root.mono
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 150
                        text: root.entries.length + " item" + (root.entries.length === 1 ? "" : "s")
                        color: root.cDim
                        font.family: root.mono
                        font.pixelSize: 12
                    }

                    // Two-stage: the first click arms, the second wipes. No
                    // modal — this is a history, not a document.
                    Rectangle {
                        id: wipeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: wipeLabel.implicitWidth + 22
                        height: 26
                        radius: 6
                        color: root.confirmWipe ? root.cDanger
                                                : (wipeHover.containsMouse ? "#2a0d0d" : root.cPanel)
                        border.color: root.cDanger
                        border.width: 1

                        Text {
                            id: wipeLabel
                            anchors.centerIn: parent
                            text: root.confirmWipe ? "  really clear all?" : "  clear history"
                            color: root.confirmWipe ? "#000000" : root.cDanger
                            font.family: root.mono
                            font.pixelSize: 12
                            font.bold: root.confirmWipe
                        }

                        MouseArea {
                            id: wipeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.entries.length > 0
                            onClicked: root.confirmWipe ? root.wipeAll() : root.confirmWipe = true
                            // Moving away disarms, so it cannot stay hot.
                            onExited: root.confirmWipe = false
                        }
                    }
                }

                // ── search ────────────────────────────────────────────
                Rectangle {
                    width: parent.width
                    height: 40
                    color: root.cPanel
                    radius: 8
                    border.color: root.cAccent
                    border.width: 1

                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.margins: 10
                        color: root.cText
                        clip: true
                        font.family: root.mono
                        font.pixelSize: 14
                        focus: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.close()
                        Keys.onReturnPressed: {
                            var f = root.filtered();
                            if (f.length > 0)
                                root.copyEntry(f[0]);
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search…"
                            color: root.cDim
                            visible: search.text.length === 0
                            font: search.font
                        }
                    }
                }

                // ── history ───────────────────────────────────────────
                ListView {
                    id: listView
                    width: parent.width
                    height: parent.height - 120
                    clip: true
                    spacing: 4
                    model: root.filtered()

                    Text {
                        anchors.centerIn: parent
                        visible: listView.count === 0
                        text: root.entries.length === 0 ? "clipboard history is empty"
                                                        : "nothing matches “" + root.query + "”"
                        color: root.cDim
                        font.family: root.mono
                        font.pixelSize: 13
                    }

                    delegate: Rectangle {
                        id: row
                        required property string modelData

                        readonly property bool   isImg: root.isImage(modelData)
                        readonly property string entId: root.entryId(modelData)
                        readonly property var    meta:  root.imageMeta(modelData)

                        width: listView.width
                        // Image rows are taller so the thumbnail is legible.
                        height: isImg ? 72 : 38
                        radius: 6
                        color: rowHover.containsMouse ? root.cAccent : root.cPanel

                        // Ask for the decode once the row exists, not before.
                        Component.onCompleted: if (isImg) thumbProc.want(entId)

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.copyEntry(row.modelData)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 8
                            anchors.rightMargin: 40   // leave the trash button clear
                            spacing: 10

                            // thumbnail (image rows only)
                            Rectangle {
                                visible: row.isImg
                                width: visible ? 82 : 0
                                height: 56
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#000000"
                                radius: 4
                                border.color: rowHover.containsMouse ? "#000000" : root.cDim
                                border.width: 1
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    // thumbTick forces a re-evaluation when a
                                    // decode finishes, so the file that did not
                                    // exist a moment ago gets picked up.
                                    source: row.isImg && root.thumbTick >= 0
                                            ? "file://" + root.thumbDir + "/" + row.entId
                                            : ""
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (row.isImg ? 92 : 0)
                                spacing: 2

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.isImg
                                          ? (row.meta ? row.meta.kind.toUpperCase() + " image" : "image")
                                          : root.entryText(row.modelData)
                                    color: rowHover.containsMouse ? "#000000" : root.cText
                                    font.family: root.mono
                                    font.pixelSize: 13
                                }

                                Text {
                                    visible: row.isImg && row.meta !== null
                                    text: row.meta ? row.meta.dims + "  ·  " + row.meta.size : ""
                                    color: rowHover.containsMouse ? "#003311" : root.cDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // ── per-entry delete ──────────────────────────
                        Rectangle {
                            id: trash
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            radius: 6
                            color: trashHover.containsMouse ? root.cDanger : "transparent"
                            // Only drawn for the row under the pointer — a
                            // column of red icons would fight the list for
                            // attention.
                            opacity: rowHover.containsMouse || trashHover.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 90 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰩹"
                                color: trashHover.containsMouse ? "#000000" : root.cDanger
                                font.family: root.mono
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: trashHover
                                anchors.fill: parent
                                hoverEnabled: true
                                // Above the row's own MouseArea, so deleting
                                // never also copies.
                                onClicked: root.deleteEntry(row.modelData)
                            }
                        }
                    }
                }

                Text {
                    text: "enter copies the top match  ·  click a row to copy  ·  󰩹 deletes  ·  esc closes"
                    color: root.cDim
                    font.family: root.mono
                    font.pixelSize: 11
                }
            }
        }

        // focus the search box each time the picker opens
        onVisibleChanged: if (visible) search.forceActiveFocus()
    }
}
