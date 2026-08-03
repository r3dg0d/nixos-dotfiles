import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property int defaultDiameter: 320
    readonly property int minDiameter: 160
    readonly property int maxDiameter: 1360
    property int diameter: defaultDiameter
    property bool mirrored: true
    property bool shown: false
    property string state: "hidden"
    property string lastCameraStatus: "No camera started"
    property string lastDevice: ""
    property string lastFormat: ""

    function clampDiameter(value: int): int {
        if (!Number.isFinite(value))
            return defaultDiameter;
        return Math.max(minDiameter, Math.min(maxDiameter, Math.round(value)));
    }

    function setDiameter(value: int): void {
        const next = clampDiameter(value);
        if (diameter === next)
            return;
        diameter = next;
        saveTimer.restart();
    }

    function show(): void {
        shown = true;
        state = "starting";
        mirrorWindow.showMirror();
    }

    function hide(): void {
        shown = false;
        mirrorWindow.hideMirror();
        state = "hidden";
    }

    function toggle(): void {
        if (shown)
            hide();
        else
            show();
    }

    function restartCamera(): void {
        cameraController.restart();
    }

    Component.onCompleted: {
        stateDirProc.running = true;
        loadState();
    }

    Process {
        id: stateDirProc
        command: ["mkdir", "-p", Quickshell.statePath("Mirror")]
    }

    IpcHandler {
        target: "mirror"

        function toggle(): void { root.toggle(); }
        function show(): void { root.show(); }
        function hide(): void { root.hide(); }
        function status(): string { return root.state; }
        function restartCamera(): void { root.restartCamera(); }
        function setDiameter(diameter: int): void { root.setDiameter(diameter); }
        function getDiameter(): int { return root.diameter; }
        function setMirrored(mirrored: bool): void { root.mirrored = mirrored; }
        function getDevice(): string { return root.lastDevice; }
        function getFormat(): string { return root.lastFormat; }
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("Mirror/state.json")
        atomicWrites: true
        blockLoading: true
        printErrors: false

        onLoadFailed: function(error) {
            if (error !== FileViewError.FileNotFound)
                console.warn("Mirror: failed to load state:", FileViewError.toString(error));
        }

        onSaveFailed: function(error) {
            console.warn("Mirror: failed to save state:", FileViewError.toString(error));
        }
    }

    Timer {
        id: saveTimer
        interval: 450
        repeat: false
        onTriggered: stateFile.setText(JSON.stringify({ diameter: root.diameter }) + "\n")
    }

    function loadState(): void {
        try {
            const text = stateFile.text();
            if (!text || text.length === 0)
                return;
            const parsed = JSON.parse(text);
            diameter = clampDiameter(Number(parsed.diameter));
        } catch (e) {
            console.warn("Mirror: ignoring invalid saved state:", e);
            diameter = defaultDiameter;
        }
    }

    CameraController {
        id: cameraController
        active: root.shown

        onStatusChanged: {
            root.lastCameraStatus = statusText;
            root.lastDevice = deviceDescription;
            root.lastFormat = formatDescription;
            if (root.shown)
                root.state = errorText.length > 0 ? "error" : (cameraActive ? "visible" : "starting");
        }
    }

    MirrorWindow {
        id: mirrorWindow
        diameter: root.diameter
        minDiameter: root.minDiameter
        maxDiameter: root.maxDiameter
        mirrored: root.mirrored
        camera: cameraController.camera
        cameraActive: cameraController.cameraActive
        statusText: cameraController.statusText
        errorText: cameraController.errorText

        onDiameterChanged: root.setDiameter(diameter)
        onVisibleChanged: {
            if (!root.shown)
                root.state = "hidden";
            else if (cameraController.errorText.length > 0)
                root.state = "error";
            else
                root.state = cameraController.cameraActive ? "visible" : "starting";
        }
    }
}
