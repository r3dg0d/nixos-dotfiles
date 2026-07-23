// SIVA Voicefetch — RVC v2 voice-model downloader overlay (Invincible theme)
// Talks to siva-voicefetch-daemon over /tmp/siva-voicefetch.sock
// (newline-delimited JSON). F7 toggles.
//
// Search voice-models.com, queue Google Drive / Hugging Face downloads,
// manage the voice library, and pick which character voice SIVA's TTS
// gets converted into.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root

    // ── palette ───────────────────────────────────────────────────────
    readonly property color cYellow: "#fcba03"
    readonly property color cBlue:   "#3a5cff"
    readonly property color cRed:    "#ff2020"
    readonly property color cGreen:  "#2ecc71"
    readonly property color cDim:    "#666666"
    readonly property color cText:   "#dddddd"
    readonly property string fnt: "JetBrains Mono Nerd Font"

    // ── daemon-driven state ───────────────────────────────────────────
    property bool shown: false
    property bool busy: false
    property bool rvcReady: false
    property string tab: "search"          // search | queue | library
    property string selectedSlug: ""
    property string toastText: ""
    property var results: []
    property var queue: []
    property var library: []
    property int page: 1
    property int pages: 1
    property string lastQuery: ""

    visible: shown
    implicitWidth: 900
    implicitHeight: 660
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true }
    margins { top: 120 }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "siva-voicefetch"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand
                                       : WlrKeyboardFocus.None

    function send(obj) {
        const s = sockLoader.item
        if (s && s.connected)
            s.write(JSON.stringify(obj) + "\n")
    }
    function stateColor(st) {
        return st === "downloading" ? cBlue :
               st === "extracting"  ? cYellow :
               st === "done"        ? cGreen :
               st === "error"       ? cRed : cDim
    }
    function kindIcon(k) {
        return k === "huggingface"   ? "󰗃" :
               k.startsWith("gdrive") ? "󰊶" :
               k === "mega"           ? "󰅟" : "󰇚"
    }

    // ── daemon link (Socket never re-dials: reconnect = Loader bounce) ─
    property bool linkUp: false

    Component {
        id: sockComp
        Socket {
            path: "/tmp/siva-voicefetch.sock"
            connected: true

            parser: SplitParser {
                onRead: line => {
                    root.linkUp = true
                    watchdog.restart()
                    let m
                    try { m = JSON.parse(line) } catch (e) { return }
                    switch (m.type) {
                    case "show":     root.shown = true; break
                    case "hide":     root.shown = false; break
                    case "busy":     root.busy = m.value; break
                    case "rvc":      root.rvcReady = m.ready; break
                    case "results":
                        root.results = m.items
                        root.page = m.page
                        root.pages = m.pages
                        root.lastQuery = m.query
                        break
                    case "queue":    root.queue = m.items; break
                    case "library":  root.library = m.items; break
                    case "selected": root.selectedSlug = m.slug; break
                    case "toast":
                        root.toastText = m.text
                        toastTimer.restart()
                        break
                    }
                }
            }
        }
    }
    Loader { id: sockLoader; active: true; sourceComponent: sockComp }

    Timer { id: watchdog; interval: 8000; onTriggered: root.linkUp = false }
    Timer {
        interval: 2000; running: !root.linkUp; repeat: true
        onTriggered: { sockLoader.active = false; sockLoader.active = true }
    }
    Timer { id: toastTimer; interval: 4000; onTriggered: root.toastText = "" }
    Timer {
        id: debounce; interval: 400
        onTriggered: root.send({ type: "search", query: searchBox.text, page: 1 })
    }

    // ── card ──────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#f2000000"
        border.color: root.cYellow
        border.width: 1
        radius: 18

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            // header
            Item {
                width: parent.width; height: 30

                Row {
                    spacing: 10
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "󰍬󰔊  SIVA Voicefetch"
                        color: root.cYellow
                        font { family: root.fnt; pixelSize: 18; bold: true }
                    }
                    Text {
                        text: "rvc v2 voice models · voice-models.com"
                        color: root.cDim
                        anchors.verticalCenter: parent.verticalCenter
                        font { family: root.fnt; pixelSize: 10 }
                    }
                }
                Row {
                    spacing: 6
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: root.rvcReady ? root.cGreen : root.cRed
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.rvcReady ? "rvc engine" : "rvc engine missing"
                        color: root.cDim
                        font { family: root.fnt; pixelSize: 10 }
                    }
                }
            }

            // tab chips
            Row {
                spacing: 8
                Repeater {
                    model: [
                        { key: "search",  label: "󰍉 search" },
                        { key: "queue",   label: "󰇚 queue" },
                        { key: "library", label: "󰲸 library" }
                    ]
                    Rectangle {
                        required property var modelData
                        width: tabLabel.width + 24; height: 26; radius: 13
                        color: root.tab === modelData.key ? "#26fcba03" : "transparent"
                        border.color: root.tab === modelData.key ? root.cYellow : "#33ffffff"
                        border.width: 1
                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData.label
                                  + (modelData.key === "queue" && root.queue.length
                                     ? " " + root.queue.length : "")
                                  + (modelData.key === "library" && root.library.length
                                     ? " " + root.library.length : "")
                            color: root.tab === modelData.key ? root.cYellow : root.cDim
                            font { family: root.fnt; pixelSize: 11 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tab = modelData.key
                        }
                    }
                }
            }

            // ── global download bar (any tab, while models download) ──
            Rectangle {
                id: dlBar
                readonly property var dl: root.queue.filter(q => q.state === "downloading")
                readonly property var cur: dl.length > 0 ? dl[0] : null
                visible: cur !== null
                width: parent.width
                height: visible ? 30 : 0
                radius: 8
                color: "#0d3a5cff"
                border.color: "#443a5cff"
                border.width: 1

                Row {
                    anchors { left: parent.left; leftMargin: 10;
                              right: pct.left; rightMargin: 10;
                              verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        text: "󰇚"
                        color: root.cBlue
                        anchors.verticalCenter: parent.verticalCenter
                        font { family: root.fnt; pixelSize: 12 }
                    }
                    Text {
                        width: dlBar.width * 0.42
                        text: dlBar.cur ? dlBar.cur.name : ""
                        color: root.cText
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        font { family: root.fnt; pixelSize: 10 }
                    }
                    Rectangle {
                        width: dlBar.width - dlBar.width * 0.42 - 130
                        height: 6; radius: 3
                        color: "#22ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * (dlBar.cur ? dlBar.cur.progress : 0) / 100
                            height: parent.height; radius: 3
                            color: root.cBlue
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
                }
                Text {
                    id: pct
                    anchors { right: parent.right; rightMargin: 10;
                              verticalCenter: parent.verticalCenter }
                    text: dlBar.cur
                          ? (dlBar.cur.total_mb > 0
                             ? dlBar.cur.progress + "%  " + dlBar.cur.done_mb + " MB"
                             : dlBar.cur.done_mb + " MB")
                          : ""
                    color: root.cBlue
                    font { family: root.fnt; pixelSize: 10 }
                }
            }

            // ── search tab ────────────────────────────────────────────
            Column {
                width: parent.width
                height: parent.height - y - footer.height - 12
                spacing: 8
                visible: root.tab === "search"

                Rectangle {
                    width: parent.width; height: 34; radius: 10
                    color: "#0dffffff"
                    border.color: searchBox.activeFocus ? root.cYellow : "#22ffffff"
                    border.width: 1

                    Text {
                        anchors { left: parent.left; leftMargin: 10;
                                  verticalCenter: parent.verticalCenter }
                        text: "󰍉"
                        color: root.cDim
                        font { family: root.fnt; pixelSize: 14 }
                    }
                    TextInput {
                        id: searchBox
                        anchors { fill: parent; leftMargin: 32; rightMargin: 60 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.cText
                        clip: true
                        focus: root.shown
                        font { family: root.fnt; pixelSize: 13 }
                        onTextChanged: debounce.restart()
                        Keys.onEscapePressed: root.send({ type: "hide" })
                        Text {
                            visible: searchBox.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search character voices… (empty = latest uploads)"
                            color: root.cDim
                            font { family: root.fnt; pixelSize: 12 }
                        }
                    }
                    Text {
                        visible: root.busy
                        anchors { right: parent.right; rightMargin: 12;
                                  verticalCenter: parent.verticalCenter }
                        text: "󰑮"
                        color: root.cYellow
                        font { family: root.fnt; pixelSize: 13 }
                        RotationAnimation on rotation {
                            running: root.busy; loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - 34 - 30 - 16
                    color: "#0dffffff"; radius: 10
                    border.color: "#22ffffff"; border.width: 1

                    ListView {
                        id: resultsView
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        model: root.results
                        spacing: 2

                        Text {
                            visible: root.results.length === 0
                            anchors.centerIn: parent
                            text: root.busy ? "searching…" : "no results"
                            color: root.cDim
                            font { family: root.fnt; pixelSize: 12 }
                        }

                        delegate: Rectangle {
                            required property var modelData
                            width: resultsView.width; height: 44; radius: 8
                            color: hov.hovered ? "#14fcba03" : "transparent"
                            HoverHandler { id: hov }

                            Column {
                                anchors { left: parent.left; leftMargin: 8;
                                          right: dlBtn.left; rightMargin: 8;
                                          verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    color: root.cText
                                    elide: Text.ElideRight
                                    font { family: root.fnt; pixelSize: 12 }
                                }
                                Text {
                                    text: root.kindIcon(modelData.kind) + " "
                                          + modelData.kind
                                          + (modelData.size ? "  ·  " + modelData.size : "")
                                          + (modelData.creator ? "  ·  " + modelData.creator : "")
                                    color: root.cDim
                                    font { family: root.fnt; pixelSize: 10 }
                                }
                            }
                            Rectangle {
                                id: dlBtn
                                width: 30; height: 30; radius: 8
                                anchors { right: parent.right; rightMargin: 6;
                                          verticalCenter: parent.verticalCenter }
                                color: dlHov.hovered ? "#26fcba03" : "transparent"
                                border.color: modelData.kind === "mega" ? root.cDim : root.cYellow
                                border.width: 1
                                HoverHandler { id: dlHov }
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰇚"
                                    color: modelData.kind === "mega" ? root.cDim : root.cYellow
                                    font { family: root.fnt; pixelSize: 14 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData.kind !== "mega"
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.send({ type: "download", item: modelData })
                                        root.tab = "queue"
                                    }
                                }
                            }
                        }
                    }
                }

                // pagination
                Row {
                    spacing: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    Text {
                        text: "󰅁 prev"
                        color: root.page > 1 ? root.cYellow : root.cDim
                        font { family: root.fnt; pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.page > 1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.send({ type: "search",
                                query: root.lastQuery, page: root.page - 1 })
                        }
                    }
                    Text {
                        text: "page " + root.page + " / " + root.pages
                        color: root.cDim
                        font { family: root.fnt; pixelSize: 11 }
                    }
                    Text {
                        text: "next 󰅂"
                        color: root.page < root.pages ? root.cYellow : root.cDim
                        font { family: root.fnt; pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.page < root.pages
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.send({ type: "search",
                                query: root.lastQuery, page: root.page + 1 })
                        }
                    }
                }
            }

            // ── queue tab ─────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: parent.height - y - footer.height - 12
                visible: root.tab === "queue"
                color: "#0dffffff"; radius: 10
                border.color: "#22ffffff"; border.width: 1

                ListView {
                    id: queueView
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    model: root.queue
                    spacing: 4

                    Text {
                        visible: root.queue.length === 0
                        anchors.centerIn: parent
                        text: "download queue is empty"
                        color: root.cDim
                        font { family: root.fnt; pixelSize: 12 }
                    }

                    delegate: Rectangle {
                        required property var modelData
                        width: queueView.width; height: 52; radius: 8
                        color: "transparent"
                        border.color: "#1affffff"; border.width: 1

                        Column {
                            anchors { fill: parent; margins: 8 }
                            spacing: 4
                            Item {
                                width: parent.width; height: 16
                                Text {
                                    anchors.left: parent.left
                                    width: parent.width - 120
                                    text: modelData.name
                                    color: root.cText
                                    elide: Text.ElideRight
                                    font { family: root.fnt; pixelSize: 11 }
                                }
                                Row {
                                    anchors.right: parent.right
                                    spacing: 8
                                    Text {
                                        text: modelData.state === "error"
                                              ? "✖ " + modelData.error
                                              : modelData.state
                                                + (modelData.total_mb > 0
                                                   ? "  " + modelData.done_mb + "/"
                                                     + modelData.total_mb + " MB" : "")
                                        color: root.stateColor(modelData.state)
                                        font { family: root.fnt; pixelSize: 10 }
                                    }
                                    Text {
                                        visible: modelData.state === "queued"
                                                 || modelData.state === "downloading"
                                        text: "󰜺"
                                        color: root.cRed
                                        font { family: root.fnt; pixelSize: 12 }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.send({ type: "cancel",
                                                                   qid: modelData.qid })
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width; height: 6; radius: 3
                                color: "#22ffffff"
                                Rectangle {
                                    width: parent.width * modelData.progress / 100
                                    height: parent.height; radius: 3
                                    color: root.stateColor(modelData.state)
                                    Behavior on width { NumberAnimation { duration: 300 } }
                                }
                            }
                        }
                    }
                }
            }

            // ── library tab ───────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: parent.height - y - footer.height - 12
                visible: root.tab === "library"
                color: "#0dffffff"; radius: 10
                border.color: "#22ffffff"; border.width: 1

                ListView {
                    id: libView
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    spacing: 4
                    // synthetic first row = piper default voice
                    model: [{ slug: "", name: "piper default (lessac)",
                              creator: "no conversion", size_mb: 0,
                              has_index: false, updated: "" }].concat(root.library)

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isSel: root.selectedSlug === modelData.slug
                        width: libView.width; height: 46; radius: 8
                        color: isSel ? "#14fcba03" : "transparent"
                        border.color: isSel ? "#44fcba03" : "#1affffff"
                        border.width: 1

                        Row {
                            anchors { left: parent.left; leftMargin: 8;
                                      verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Text {
                                text: isSel ? "󰗋" : "󰔊"
                                color: isSel ? root.cYellow : root.cDim
                                anchors.verticalCenter: parent.verticalCenter
                                font { family: root.fnt; pixelSize: 16 }
                            }
                            Column {
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    width: libView.width - 160
                                    text: modelData.name
                                    color: isSel ? root.cYellow : root.cText
                                    elide: Text.ElideRight
                                    font { family: root.fnt; pixelSize: 12 }
                                }
                                Text {
                                    text: (modelData.slug === "" ? "built-in TTS voice"
                                           : modelData.size_mb + " MB"
                                             + (modelData.has_index ? "  ·  index" : "")
                                             + (modelData.creator ? "  ·  " + modelData.creator : "")
                                             + (modelData.updated ? "  ·  " + modelData.updated : ""))
                                    color: root.cDim
                                    font { family: root.fnt; pixelSize: 9 }
                                }
                            }
                        }
                        Row {
                            spacing: 6
                            anchors { right: parent.right; rightMargin: 6;
                                      verticalCenter: parent.verticalCenter }
                            // preview
                            Rectangle {
                                visible: modelData.slug !== ""
                                width: 28; height: 28; radius: 8
                                color: "transparent"
                                border.color: root.cBlue; border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: "󰐊"
                                    color: root.cBlue
                                    font { family: root.fnt; pixelSize: 13 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.send({ type: "preview",
                                                           slug: modelData.slug })
                                }
                            }
                            // select for SIVA
                            Rectangle {
                                width: selLabel.width + 16; height: 28; radius: 8
                                color: isSel ? "#26fcba03" : "transparent"
                                border.color: root.cYellow; border.width: 1
                                Text {
                                    id: selLabel
                                    anchors.centerIn: parent
                                    text: isSel ? "SIVA 󰍬" : "use"
                                    color: root.cYellow
                                    font { family: root.fnt; pixelSize: 11 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.send({ type: "select",
                                                           slug: modelData.slug })
                                }
                            }
                            // delete
                            Rectangle {
                                visible: modelData.slug !== ""
                                width: 28; height: 28; radius: 8
                                color: "transparent"
                                border.color: root.cRed; border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: "󰩺"
                                    color: root.cRed
                                    font { family: root.fnt; pixelSize: 13 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.send({ type: "remove",
                                                           slug: modelData.slug })
                                }
                            }
                        }
                    }
                }
            }

            // ── footer ────────────────────────────────────────────────
            Item {
                id: footer
                width: parent.width; height: 18

                Text {
                    anchors.left: parent.left
                    text: root.toastText !== "" ? "󰋼 " + root.toastText
                        : root.selectedSlug !== ""
                          ? "SIVA speaks as: " + root.selectedSlug
                          : "SIVA speaks with the piper default voice"
                    color: root.toastText !== "" ? root.cYellow : root.cDim
                    font { family: root.fnt; pixelSize: 10 }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 12
                    Text {
                        text: "󰚰 check updates"
                        color: root.cBlue
                        font { family: root.fnt; pixelSize: 10 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.send({ type: "check_updates" })
                        }
                    }
                    Text {
                        text: "F7 close"
                        color: root.cDim
                        font { family: root.fnt; pixelSize: 10 }
                    }
                }
            }
        }
    }
}
