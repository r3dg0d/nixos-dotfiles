// Quickshell system-update panel — OLED black / white / neon-green (#00ff41).
// Toggle via IPC:
//   qs ipc call updater toggle
// Wired to the Waybar `custom/nixupdate` module's on-click.
//
// Two files drive this, both written by the nixos-updater commands:
//   ~/.cache/nixos-updater/status.json    what is out of date (nixos-update-check)
//   ~/.cache/nixos-updater/progress.json  how far along a run is (nixos-update)
//
// The panel never runs the update itself. `nixos-update` ends in
// `sudo nixos-rebuild switch`, and a layer-shell panel is nowhere to type a
// password — so the button opens it in a terminal and this window follows the
// progress file. The bar therefore tracks a run started from anywhere: this
// panel, a shell, or a script.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    // ── palette ───────────────────────────────────────────────────────
    readonly property color cBg:     "#000000"
    readonly property color cPanel:  "#0a0a0a"
    readonly property color cAccent: "#00ff41"
    readonly property color cText:   "#ffffff"
    readonly property color cDim:    "#555555"
    readonly property color cDanger: "#ff2b2b"
    readonly property color cWarn:   "#ffaa00"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    readonly property string cacheDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/nixos-updater"

    // ── state ─────────────────────────────────────────────────────────
    property bool shown: false
    property var  status: null      // parsed status.json
    property var  progress: null    // parsed progress.json
    property bool checking: false

    // A SIGKILLed run never cleared its own flag, so the pid has to still be
    // alive for "running" to be believed. procCheck flips this back off.
    property bool pidAlive: true
    readonly property bool running:
        progress !== null && progress.running === true && pidAlive
    readonly property int  total:   status !== null ? (status.total || 0) : 0
    readonly property bool rebootRequired:
        status !== null && status.info !== undefined && status.info.reboot_required === true

    // Section order and labels mirror nixos_updater.py so the panel and the
    // terminal report never disagree about naming.
    readonly property var sectionOrder: ["flake", "kernel", "flatpak", "profile", "firmware"]
    readonly property var sectionMeta: ({
        "flake":    { icon: "", label: "Flake inputs" },
        "kernel":   { icon: "", label: "Mainline kernel" },
        "flatpak":  { icon: "", label: "Flatpaks" },
        "profile":  { icon: "", label: "Nix profile" },
        "firmware": { icon: "", label: "Firmware" }
    })

    // Flatten status.json into rows the ListView can take directly.
    function sectionRows() {
        if (status === null || status.sections === undefined)
            return [];
        var out = [];
        for (var i = 0; i < sectionOrder.length; i++) {
            var key = sectionOrder[i];
            var sec = status.sections[key];
            if (sec === undefined || sec === null)
                continue;
            var meta = sectionMeta[key];
            out.push({
                key:     key,
                icon:    meta.icon,
                label:   meta.label,
                count:   sec.count || 0,
                items:   sec.items || [],
                error:   sec.error || "",
                skipped: sec.skipped || ""
            });
        }
        return out;
    }

    function ageString(stamp) {
        if (!stamp) return "never";
        var d = Math.floor(Date.now() / 1000) - stamp;
        if (d < 90)    return "just now";
        if (d < 3600)  return Math.floor(d / 60) + "m ago";
        if (d < 86400) return Math.floor(d / 3600) + "h ago";
        return Math.floor(d / 86400) + "d ago";
    }

    // ── open / close ──────────────────────────────────────────────────
    function open()   { statusFile.reload(); progressFile.reload(); shown = true; }
    function close()  { shown = false; }
    function toggle() { shown ? close() : open(); }

    // ── actions ───────────────────────────────────────────────────────
    function checkNow() {
        checking = true;
        checkProc.running = true;
    }

    // Opens a terminal so sudo has somewhere to prompt; the progress file is
    // what brings the result back here.
    function runUpdate(extraArgs) {
        updateProc.command = ["ghostty", "--title=nixos-update", "-e", "sh", "-c",
            "nixos-update " + extraArgs + "; printf '\\n[enter to close] '; read _"];
        updateProc.running = true;
    }

    IpcHandler {
        target: "updater"
        function toggle(): void { root.toggle(); }
        function open():   void { root.open(); }
        function close():  void { root.close(); }
    }

    // ── data ──────────────────────────────────────────────────────────
    // watchChanges means a run started in a terminal still drives this panel.
    FileView {
        id: statusFile
        path: root.cacheDir + "/status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.status = JSON.parse(text()); }
            catch (e) { root.status = null; }
        }
        onLoadFailed: root.status = null
    }

    FileView {
        id: progressFile
        path: root.cacheDir + "/progress.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.progress = JSON.parse(text()); }
            catch (e) { root.progress = null; }
            root.pidAlive = true;   // re-tested below on every update
            if (root.progress && root.progress.running && root.progress.pid)
                procCheck.running = true;
        }
        onLoadFailed: root.progress = null
    }

    // `kill -0` is the cheapest liveness test there is, and unlike a staleness
    // timeout it does not go wrong when one step legitimately runs for an hour.
    Process {
        id: procCheck
        command: ["sh", "-c", "kill -0 \"$1\" 2>/dev/null",
                  "pidcheck", root.progress && root.progress.pid ? String(root.progress.pid) : "0"]
        onExited: function (code) { root.pidAlive = (code === 0); }
    }

    Process {
        id: checkProc
        command: ["nixos-update-check", "--quiet"]
        onExited: { root.checking = false; statusFile.reload(); }
    }

    Process { id: updateProc }

    // ── UI ────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.shown
        color: "transparent"
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            anchors.centerIn: parent
            width: 760
            height: 640
            color: root.cBg
            radius: 12
            border.color: root.cAccent
            border.width: 2

            MouseArea {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── header ────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 30

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "  System Updates"
                        color: root.cAccent
                        font.family: root.mono
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.checking ? "checking…"
                             : "checked " + root.ageString(root.status ? root.status.checked_at : 0)
                        color: root.cDim
                        font.family: root.mono
                        font.pixelSize: 12
                    }
                }

                // ── headline ──────────────────────────────────────────
                Rectangle {
                    width: parent.width
                    height: 58
                    radius: 8
                    color: root.cPanel
                    border.width: 1
                    border.color: root.total > 0 ? root.cAccent : root.cDim

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.total > 0 ? String(root.total) : ""
                            color: root.total > 0 ? root.cAccent : root.cDim
                            font.family: root.mono
                            font.pixelSize: 26
                            font.bold: true
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: root.total > 0
                                      ? "update" + (root.total === 1 ? "" : "s") + " available"
                                      : "everything is up to date"
                                color: root.cText
                                font.family: root.mono
                                font.pixelSize: 14
                            }
                            Text {
                                visible: root.status !== null && root.status.info !== undefined
                                text: root.status && root.status.info
                                      ? "kernel " + (root.status.info.running_kernel || "?")
                                        + (root.status.info.generations
                                           ? "   ·   " + root.status.info.generations + " generations" : "")
                                      : ""
                                color: root.cDim
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.rebootRequired
                        text: "  reboot required"
                        color: root.cWarn
                        font.family: root.mono
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                // ── progress ──────────────────────────────────────────
                // Only present while a run is in flight; the space collapses
                // when it is not, rather than sitting there empty.
                Column {
                    width: parent.width
                    height: root.running ? 46 : 0
                    visible: root.running
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 16
                        Text {
                            anchors.left: parent.left
                            text: root.progress ? root.progress.label : ""
                            color: root.cAccent
                            font.family: root.mono
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.progress
                                  ? root.progress.step + " / " + root.progress.total : ""
                            color: root.cDim
                            font.family: root.mono
                            font.pixelSize: 12
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 10
                        radius: 5
                        color: root.cPanel
                        border.color: root.cDim
                        border.width: 1

                        Rectangle {
                            height: parent.height - 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: 1
                            radius: 5
                            width: {
                                if (!root.progress || !root.progress.total)
                                    return 0;
                                var f = root.progress.step / root.progress.total;
                                if (f < 0) f = 0;
                                if (f > 1) f = 1;
                                return f * (parent.width - 2);
                            }
                            color: root.cAccent
                            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                // ── per-source breakdown ──────────────────────────────
                ListView {
                    id: sections
                    width: parent.width
                    height: parent.height - (root.running ? 250 : 204)
                    clip: true
                    spacing: 6
                    model: root.sectionRows()

                    delegate: Rectangle {
                        required property var modelData
                        width: sections.width
                        height: col.implicitHeight + 16
                        radius: 8
                        color: root.cPanel
                        border.width: 1
                        border.color: modelData.error !== "" ? root.cDanger
                                    : modelData.count > 0   ? root.cAccent
                                                            : "#1a1a1a"

                        Column {
                            id: col
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 4

                            Row {
                                spacing: 10
                                Text {
                                    text: modelData.icon
                                    color: modelData.count > 0 ? root.cAccent : root.cDim
                                    font.family: root.mono
                                    font.pixelSize: 14
                                }
                                Text {
                                    text: modelData.label
                                    color: root.cText
                                    font.family: root.mono
                                    font.pixelSize: 13
                                    font.bold: modelData.count > 0
                                }
                                Text {
                                    text: modelData.error !== ""   ? modelData.error
                                        : modelData.skipped !== "" ? "skipped — " + modelData.skipped
                                        : modelData.count === 0    ? "up to date"
                                        : modelData.count + " waiting"
                                    color: modelData.error !== "" ? root.cDanger : root.cDim
                                    font.family: root.mono
                                    font.pixelSize: 12
                                }
                            }

                            // The first few specifics, then a count. A panel
                            // that lists 40 flatpaks is not a summary.
                            Repeater {
                                model: modelData.items.slice(0, 5)
                                Text {
                                    required property string modelData
                                    text: "      · " + modelData
                                    color: root.cDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: col.width - 20
                                }
                            }
                            Text {
                                visible: modelData.items.length > 5
                                text: "      … and " + (modelData.items.length - 5) + " more"
                                color: root.cDim
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // ── buttons ───────────────────────────────────────────
                Row {
                    width: parent.width
                    spacing: 10

                    // { label, danger, primary, enabled, action }
                    Repeater {
                        model: [
                            { label: "  Check now",  primary: false },
                            { label: "  Update all", primary: true  },
                            { label: "  Terminal",   primary: false }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property bool isEnabled: !root.running && !(index === 0 && root.checking)

                            width: (sections.width - 20) / 3
                            height: 38
                            radius: 8
                            color: !isEnabled ? "#0a0a0a"
                                 : btnHover.containsMouse ? root.cAccent
                                 : modelData.primary ? "#04240f" : root.cPanel
                            border.width: 1
                            border.color: isEnabled ? root.cAccent : "#1a1a1a"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: !parent.isEnabled ? root.cDim
                                     : btnHover.containsMouse ? "#000000" : root.cAccent
                                font.family: root.mono
                                font.pixelSize: 13
                                font.bold: modelData.primary
                            }

                            MouseArea {
                                id: btnHover
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: parent.isEnabled
                                onClicked: {
                                    if (index === 0)      root.checkNow();
                                    else if (index === 1) root.runUpdate("");
                                    else                  root.runUpdate("--dry");
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.running
                          ? "a run is in progress — the terminal has the details"
                          : "“Update all” opens a terminal, because the rebuild needs your sudo password"
                    color: root.cDim
                    font.family: root.mono
                    font.pixelSize: 11
                }
            }
        }
    }
}
