// Quickshell SearXNG launcher — Fn + F4.
//
//   qs ipc call websearch toggle
//
// Type a query, press Enter, and it opens in the local SearXNG instance
// (modules/nixos/services.nix binds it to 127.0.0.1:8888). Nothing leaves the
// machine until SearXNG itself goes upstream, so the query never touches a
// third-party search box on the way out.
//
// Bangs are passed through verbatim — SearXNG parses `!gh quickshell` or
// `!yt …` itself, so there is nothing to special-case here. The recent-query
// list is in-memory only: a search history that outlives the session is a
// liability, not a feature.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ── palette (matches Power.qml / Clipboard.qml / Osd.qml) ─────────
    readonly property color cBg:     "#000000"
    readonly property color cPanel:  "#0a0a0a"
    readonly property color cAccent: "#00ff41"
    readonly property color cText:   "#ffffff"
    readonly property color cDim:    "#555555"
    readonly property string mono:   "JetBrainsMono Nerd Font"
    // The panel background is 75% black. Applied as the backdrop layer's
    // opacity rather than an alpha colour — see the note below.
    readonly property real glassOpacity: 0.75

    // The panel is only 75% opaque, so whatever is behind it competes with the
    // text. #555 disappears against a busy wallpaper; secondary copy uses this
    // instead and stays readable without pulling focus off the prompt.
    readonly property color cHint:   "#8a8a8a"

    // ── configuration ─────────────────────────────────────────────────
    readonly property string endpoint: "http://localhost:8888/search?q=%s"

    // ── state ─────────────────────────────────────────────────────────
    property bool shown: false
    property var  recent: []          // last few queries, this session only

    // ── open / close ──────────────────────────────────────────────────
    function open() {
        input.text = "";
        shown = true;
    }
    function close() { shown = false; }
    function toggle() { shown ? close() : open(); }

    // ── the search itself ─────────────────────────────────────────────
    function search(q) {
        var query = q.trim();
        if (query.length === 0)
            return;

        // Drop any earlier copy so re-running a query moves it to the front
        // instead of duplicating it.
        var r = recent.filter(function (e) { return e !== query; });
        r.unshift(query);
        recent = r.slice(0, 5);

        // encodeURIComponent, not encodeURI: spaces, &, # and ? are all part
        // of the query here, not of the URL around it.
        var url = endpoint.replace("%s", encodeURIComponent(query));
        openProc.command = ["xdg-open", url];
        openProc.running = true;
        close();
    }

    // Called from the command line: `qs ipc call websearch <fn>`
    IpcHandler {
        target: "websearch"

        function toggle(): void { root.toggle(); }
        function open():   void { root.open(); }
        function close():  void { root.close(); }

        // `qs ipc call websearch query "nixos ddcutil"` — search without the UI
        function query(q: string): void { root.search(q); }
    }

    Process { id: openProc }

    // ── UI ────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.shown
        color: "transparent"
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-websearch"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // click anywhere outside the box to dismiss
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        // Sits above centre — the same place a launcher would be, so the eye
        // does not have to hunt for it.
        Item {
            id: holder
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -120
            width: 720
            height: box.height

            // The gradient edge, same construction as the OSD: a
            // gradient-filled rounded rect with the panel fill laid 2px inside
            // it, so the white → neon-green sweep shows as the border. Matches
            // what niri now draws around a focused window.
            //
            // Layered on purpose — see Osd.qml. The two rects are composited
            // into one texture before the 75% is applied, so the opaque inner
            // fill hides the gradient instead of letting it wash the panel.
            Item {
                anchors.fill: box
                layer.enabled: true
                opacity: root.glassOpacity

                Rectangle {
                    anchors.fill: parent
                    radius: box.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#ffffff" }
                        GradientStop { position: 1.0; color: root.cAccent }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: box.radius - 2
                    color: "#000000"
                }
            }

            Rectangle {
                id: box
                width: parent.width
                height: content.implicitHeight + 36
                radius: 14
                color: "transparent"

                // swallow clicks so they don't reach the dismiss handler
                MouseArea { anchors.fill: parent }

                // Scanline wash, clipped to the rounding.
                Item {
                    anchors.fill: parent
                    anchors.margins: 2
                    clip: true
                    opacity: 0.05
                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: Math.ceil(box.height / 4)
                            delegate: Rectangle {
                                width: box.width
                                height: 2
                                color: root.cAccent
                            }
                        }
                    }
                }

                // Left/right/top rather than fill: the panel is sized *from*
                // this column's natural height, so it must not inherit one.
                Column {
                    id: content
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 12

                    // ── header ────────────────────────────────────────
                    Item {
                        width: parent.width
                        height: 22

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰖟  SEARXNG"
                            color: root.cAccent
                            font.family: root.mono
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 2
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "localhost:8888"
                            color: root.cHint
                            font.family: root.mono
                            font.pixelSize: 12
                        }
                    }

                    // ── the prompt ────────────────────────────────────
                    Rectangle {
                        width: parent.width
                        height: 52
                        radius: 8
                        color: root.cPanel
                        border.color: root.cAccent
                        border.width: 1

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ">"
                                color: root.cAccent
                                font.family: root.mono
                                font.pixelSize: 20
                                font.bold: true
                            }

                            TextInput {
                                id: input
                                width: parent.width - 34
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.cText
                                clip: true
                                focus: true
                                font.family: root.mono
                                font.pixelSize: 18
                                selectionColor: root.cAccent
                                selectedTextColor: root.cBg
                                cursorVisible: true

                                Keys.onEscapePressed: root.close()
                                Keys.onReturnPressed: root.search(text)
                                Keys.onEnterPressed:  root.search(text)

                                // Block cursor, blinking — a terminal caret
                                // rather than Qt's hairline.
                                cursorDelegate: Rectangle {
                                    width: 10
                                    color: root.cAccent
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        running: input.cursorVisible
                                        NumberAnimation { to: 0; duration: 480 }
                                        NumberAnimation { to: 1; duration: 480 }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "search the web…"
                                    color: root.cHint
                                    visible: input.text.length === 0
                                    font: input.font
                                }
                            }
                        }
                    }

                    // ── recent queries ────────────────────────────────
                    // Session-scoped; click one to run it again.
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: root.recent.length > 0 && input.text.length === 0

                        Repeater {
                            model: root.recent
                            delegate: Rectangle {
                                width: content.width
                                height: 26
                                radius: 5
                                color: rowHover.containsMouse ? "#0f2a16" : "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰋚"
                                        color: root.cHint
                                        font.family: root.mono
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        color: rowHover.containsMouse ? root.cAccent : root.cText
                                        font.family: root.mono
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        width: content.width - 40
                                    }
                                }

                                MouseArea {
                                    id: rowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.search(modelData)
                                }
                            }
                        }
                    }

                    // ── footer ────────────────────────────────────────
                    Item {
                        width: parent.width
                        height: 16

                        Text {
                            anchors.left: parent.left
                            text: "⏎ search   ·   esc cancel   ·   !bangs supported"
                            color: root.cHint
                            font.family: root.mono
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        onVisibleChanged: if (visible) input.forceActiveFocus()
    }
}
