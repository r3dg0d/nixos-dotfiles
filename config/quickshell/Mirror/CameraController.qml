import QtQuick
import QtMultimedia

Item {
    id: root

    property bool active: false
    readonly property alias camera: camera
    property bool cameraActive: camera.active
    property string deviceDescription: ""
    property string formatDescription: ""
    property string statusText: "Mirror hidden"
    property string errorText: ""

    signal statusChanged()

    function restart(): void {
        camera.active = false;
        Qt.callLater(function() {
            if (root.active)
                startCamera();
        });
    }

    function startCamera(): void {
        const device = selectDevice();
        if (!device) {
            deviceDescription = "";
            formatDescription = "";
            errorText = "No camera";
            statusText = "No camera found";
            camera.active = false;
            statusChanged();
            return;
        }

        const format = selectFormat(device);
        deviceDescription = device.description || String(device.id);
        camera.cameraDevice = device;

        if (format) {
            camera.cameraFormat = format;
            formatDescription = describeFormat(format);
        } else {
            formatDescription = "driver default";
        }

        errorText = "";
        statusText = "Starting " + deviceDescription + " " + formatDescription;
        console.log("Mirror: selected camera:", deviceDescription, "id:", String(device.id), "format:", formatDescription);
        camera.active = true;
        statusChanged();
    }

    function stopCamera(): void {
        camera.active = false;
        errorText = "";
        statusText = "Mirror hidden";
        statusChanged();
    }

    function selectDevice(): var {
        const inputs = devices.videoInputs || [];
        if (inputs.length === 0)
            return null;

        const contains = function(device, needle) {
            const haystack = ((device.description || "") + " " + String(device.id || "")).toLowerCase();
            return haystack.indexOf(needle.toLowerCase()) >= 0;
        };

        for (let i = 0; i < inputs.length; i++)
            if (contains(inputs[i], "Insta360 Link 2"))
                return inputs[i];
        for (let j = 0; j < inputs.length; j++)
            if (contains(inputs[j], "Insta360"))
                return inputs[j];
        for (let k = 0; k < inputs.length; k++)
            if (inputs[k].isDefault)
                return inputs[k];
        return inputs[0];
    }

    function selectFormat(device: var): var {
        const formats = device.videoFormats || [];
        if (formats.length === 0)
            return null;

        let exact = [];
        for (let i = 0; i < formats.length; i++) {
            if (formats[i].resolution.width === 3840 && formats[i].resolution.height === 2160)
                exact.push(formats[i]);
        }

        if (exact.length > 0)
            return bestFormat(exact, true);

        const practical = [];
        for (let j = 0; j < formats.length; j++) {
            if (formats[j].maxFrameRate >= 10 || formats[j].resolution.width * formats[j].resolution.height >= 3840 * 2160)
                practical.push(formats[j]);
        }
        return bestFormat(practical.length > 0 ? practical : formats, false);
    }

    function bestFormat(formats: var, exact4k: bool): var {
        let best = null;
        let bestScore = -1;
        for (let i = 0; i < formats.length; i++) {
            const f = formats[i];
            const area = f.resolution.width * f.resolution.height;
            const maxFps = Number(f.maxFrameRate || 0);
            const minFps = Number(f.minFrameRate || 0);
            const fpsRange = Math.max(0, maxFps - minFps);
            const stillPenalty = maxFps > 0 && maxFps < 10 ? 1000000000 : 0;
            const score = (exact4k ? 0 : area * 1000) + maxFps * 100 + fpsRange + pixelFormatScore(f) - stillPenalty;
            if (score > bestScore) {
                best = f;
                bestScore = score;
            }
        }
        return best;
    }

    function pixelFormatScore(format: var): int {
        const name = String(format.pixelFormat || "").toLowerCase();
        if (name.indexOf("h264") >= 0 || name.indexOf("mjpg") >= 0 || name.indexOf("mjpeg") >= 0)
            return 30;
        if (name.indexOf("nv12") >= 0)
            return 25;
        if (name.indexOf("yuv") >= 0 || name.indexOf("yuy") >= 0)
            return 20;
        return 0;
    }

    function describeFormat(format: var): string {
        if (!format)
            return "driver default";
        return format.resolution.width + "x" + format.resolution.height
            + " pixelFormat=" + String(format.pixelFormat)
            + " fps=" + Number(format.minFrameRate).toFixed(2)
            + "-" + Number(format.maxFrameRate).toFixed(2);
    }

    onActiveChanged: {
        if (active)
            startCamera();
        else
            stopCamera();
    }

    MediaDevices {
        id: devices
        onVideoInputsChanged: {
            if (root.active)
                root.restart();
        }
    }

    Camera {
        id: camera

        onActiveChanged: {
            root.cameraActive = active;
            if (active && root.errorText.length === 0)
                root.statusText = "Streaming " + root.deviceDescription + " " + root.formatDescription;
            root.statusChanged();
        }

        onErrorChanged: {
            if (error !== Camera.NoError) {
                root.errorText = errorString.length > 0 ? errorString : "Camera error";
                root.statusText = root.errorText;
                console.warn("Mirror: camera error:", root.errorText);
                root.statusChanged();
            }
        }
    }
}
