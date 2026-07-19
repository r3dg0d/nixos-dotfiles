import QtQuick 2.15

// ascii-city: black & white animated ASCII rain over a procedural ASCII city.
Rectangle {
    id: root
    color: "#000000"

    readonly property color cRain:  "#d8d8d8"
    readonly property color cFar:   "#3a3a3a"
    readonly property color cNear:  "#8c8c8c"
    readonly property color cPanel: "#f2f2f2"
    readonly property color cDim:   "#5f5f5f"

    readonly property string monoFont: "JetBrainsMono Nerd Font Mono"

    property int rainPx: Math.max(13, Math.round(height / 90))
    property int uiPx:   Math.max(16, Math.round(height / 60))

    FontMetrics { id: fm;   font.family: root.monoFont; font.pixelSize: root.rainPx }
    FontMetrics { id: fmUi; font.family: root.monoFont; font.pixelSize: root.uiPx }

    property real cellW: fm.advanceWidth("M")
    property int  gcols: Math.max(8, Math.floor(width / cellW))
    property int  grows: Math.max(8, Math.floor(height / fm.lineSpacing))

    property bool blinkOn: true
    property bool denied: false
    property bool capsOn: typeof keyboard !== "undefined" && keyboard.capsLock

    // ---- rain/city engine state (plain JS data, not bindings) ----
    property var drops: []
    property var splashes: []
    property var skyH: []
    property var winList: []
    property var litWins: []
    property int lastCols: -1
    property int lastRows: -1

    function ri(n) { return Math.floor(Math.random() * n) }

    function mkGrid() {
        var g = []
        for (var r = 0; r < grows; r++) {
            var row = new Array(gcols)
            for (var c = 0; c < gcols; c++) row[c] = " "
            g.push(row)
        }
        return g
    }

    function drawBuilding(g, farGrid, x0, w, h, isFar) {
        var top = grows - 1 - h
        if (top < 1) { h = grows - 2; top = 1 }
        var x1 = Math.min(x0 + w - 1, gcols - 1)
        for (var c = x0; c <= x1; c++) {
            g[top][c] = "_"
            for (var r = top + 1; r < grows; r++) {
                if (farGrid) farGrid[r][c] = " "   // near buildings occlude the far layer
                if (c === x0 || c === x1) { g[r][c] = "|"; continue }
                var lc = c - x0, lr = r - top - 1
                if (isFar) {
                    g[r][c] = (lr % 2 === 0 && lc % 3 === 1) ? ":" : " "
                } else if (lr % 2 === 0 && lc % 3 === 1) {
                    g[r][c] = "."
                    winList.push({ r: r, c: c })
                }
            }
            if (!isFar) skyH[c] = Math.max(skyH[c], h)
        }
        if (!isFar && w >= 9 && Math.random() < 0.5) {   // rooftop antenna
            var mc = x0 + Math.floor(w / 2)
            if (mc < gcols) {
                for (var a = 1; a <= 2; a++) if (top - a >= 1) g[top - a][mc] = "|"
                if (top - 3 >= 1) g[top - 3][mc] = "!"
                skyH[mc] = Math.max(skyH[mc], h + 3)
            }
        }
    }

    function gridToText(g) {
        var out = []
        for (var r = 0; r < grows; r++) out.push(g[r].join(""))
        return out.join("\n")
    }

    function respawn(d) {
        d.c = ri(gcols)
        d.r = -1 - ri(10)
        d.v = Math.random() < 0.3 ? 2 : 1
        var p = Math.random()
        d.ch = d.v === 2 ? "|" : (p < 0.55 ? "|" : (p < 0.85 ? "'" : "."))
    }

    function initScene() {
        lastCols = gcols; lastRows = grows
        skyH = new Array(gcols)
        for (var i = 0; i < gcols; i++) skyH[i] = 0
        winList = []; litWins = []; splashes = []

        var far = mkGrid(), near = mkGrid()
        var x = ri(4)
        while (x < gcols - 4) {                       // far skyline: tall, dim
            if (Math.random() < 0.8) {
                var w = 9 + ri(15)
                drawBuilding(far, null, x, w, Math.min(grows - 6, 12 + ri(18)), true)
                x += w + 1 + ri(5)
            } else x += 4 + ri(8)
        }
        x = 0
        while (x < gcols - 3) {                       // near skyline: short, brighter
            if (Math.random() < 0.72) {
                var w2 = 7 + ri(11)
                drawBuilding(near, far, x, w2, 5 + ri(10), false)
                x += w2 + 2 + ri(7)
            } else x += 3 + ri(7)
        }
        for (var c = 0; c < gcols; c++)               // street
            if (near[grows - 1][c] === " ") near[grows - 1][c] = "_"

        for (i = 0; i < winList.length; i++)          // some windows start lit
            if (Math.random() < 0.12) litWins.push(winList[i])

        drops = []
        var n = Math.floor(gcols * 0.55)
        for (i = 0; i < n; i++) {
            var d = {}; respawn(d)
            d.r = ri(grows * 2) - grows
            drops.push(d)
        }
        cityFar.text = gridToText(far)
        cityNear.text = gridToText(near)
    }

    function tick() {
        if (gcols !== lastCols || grows !== lastRows) initScene()

        var rowsMap = {}
        function put(r, c, ch) {
            if (r < 0 || r >= grows || c < 0 || c >= gcols) return
            var row = rowsMap[r]
            if (!row) row = rowsMap[r] = new Array(gcols)
            row[c] = ch
        }

        for (var i = 0; i < litWins.length; i++) put(litWins[i].r, litWins[i].c, "#")

        var keep = []
        for (i = 0; i < splashes.length; i++) {
            var s = splashes[i]
            put(s.r, s.c, s.ttl === 2 ? "*" : ".")
            if (s.ttl === 1) { put(s.r, s.c - 1, ","); put(s.r, s.c + 1, ",") }
            if (--s.ttl > 0) keep.push(s)
        }
        splashes = keep

        for (i = 0; i < drops.length; i++) {
            var d = drops[i]
            d.r += d.v
            var land = grows - 1 - skyH[d.c]
            if (d.r >= land) {
                splashes.push({ r: land, c: d.c, ttl: 2 })
                respawn(d)
            } else {
                put(d.r, d.c, d.ch)
                if (d.v === 2) put(d.r - 1, d.c, "'")
            }
        }

        if (winList.length > 0 && Math.random() < 0.25) {   // window flicker
            var wI = winList[ri(winList.length)]
            var at = -1
            for (i = 0; i < litWins.length; i++)
                if (litWins[i].r === wI.r && litWins[i].c === wI.c) { at = i; break }
            if (at >= 0) litWins.splice(at, 1); else litWins.push(wI)
        }

        var out = new Array(grows)
        for (var r = 0; r < grows; r++) {
            var row = rowsMap[r]
            if (!row) { out[r] = ""; continue }
            var str = ""
            for (var c = 0; c < gcols; c++) str += row[c] || " "
            out[r] = str
        }
        rainText.text = out.join("\n")
    }

    Timer { interval: 80;  running: true; repeat: true; onTriggered: root.tick() }
    Timer { interval: 530; running: true; repeat: true; onTriggered: root.blinkOn = !root.blinkOn }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.timeStr = Qt.formatTime(new Date(), "HH:mm:ss")
    }
    property string timeStr: ""

    // ---- city + rain layers ----
    Text {
        id: cityFar
        anchors.left: parent.left; anchors.bottom: parent.bottom
        color: root.cFar; textFormat: Text.PlainText
        font.family: root.monoFont; font.pixelSize: root.rainPx
    }
    Text {
        id: cityNear
        anchors.left: parent.left; anchors.bottom: parent.bottom
        color: root.cNear; textFormat: Text.PlainText
        font.family: root.monoFont; font.pixelSize: root.rainPx
    }
    Text {
        id: rainText
        anchors.left: parent.left; anchors.bottom: parent.bottom
        color: root.cRain; textFormat: Text.PlainText
        font.family: root.monoFont; font.pixelSize: root.rainPx
    }

    // ---- top-left hostname / clock ----
    Text {
        x: Math.round(root.cellW * 2); y: Math.round(fm.lineSpacing)
        color: root.cDim
        font.family: root.monoFont; font.pixelSize: root.rainPx
        text: "+--[ " + ((typeof sddm !== "undefined" && sddm.hostName) ? sddm.hostName : "nixos-btw")
              + " ]--[ " + root.timeStr + " ]--"
    }

    // ---- login panel ----
    property int pCols: 1
    property int pRowsN: 1
    property int imgRow: 0
    property int imgCol: 0
    property int imgRowsN: 7
    property int imgColsN: 20
    property int inCol: 0
    property int inColsN: 10
    property int rowUser: 0
    property int rowPass: 0
    property int rowStatus: 0
    property real pChW: pCols > 0 ? panelText.width / pCols : 8
    property real pLnH: pRowsN > 0 ? panelText.height / pRowsN : 16

    function buildPanel() {
        var W = 46
        var L = []
        function row(s) { while (s.length < W) s += " "; L.push("|" + s + "|") }
        var hr = "+"
        for (var i = 0; i < W; i++) hr += "="
        hr += "+"
        L.push(hr)
        row("")
        var fw = 20
        var fl = Math.floor((W - fw - 2) / 2)
        var sp = " ".repeat(fl)
        row(sp + "." + "-".repeat(fw) + ".")
        for (i = 0; i < 7; i++) row(sp + "|" + " ".repeat(fw) + "|")
        row(sp + "'" + "-".repeat(fw) + "'")
        row("")
        row("   user > [" + " ".repeat(26) + "]")
        row("   pass > [" + " ".repeat(26) + "]")
        row("")
        row("")
        L.push(hr)

        pCols = W + 2
        pRowsN = L.length
        imgRow = 3; imgCol = fl + 2; imgRowsN = 7; imgColsN = fw
        rowUser = 12; rowPass = 13; rowStatus = L.length - 3
        inCol = L[rowUser].indexOf("[") + 2
        inColsN = L[rowUser].indexOf("]") - inCol - 1
        panelText.text = L.join("\n")
    }

    function doLogin() {
        if (typeof sddm === "undefined") return
        var idx = (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0)
                  ? sessionModel.lastIndex : 0
        sddm.login(userInput.text, passInput.text, idx)
    }

    Item {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Math.round(root.height * 0.06)
        width: panelText.width
        height: panelText.height

        Rectangle { anchors.fill: parent; anchors.margins: -14; color: "#000000"; opacity: 0.93 }

        Text {
            id: panelText
            color: root.cPanel; textFormat: Text.PlainText
            font.family: root.monoFont; font.pixelSize: root.uiPx
        }

        Image {
            x: root.pChW * root.imgCol
            y: root.pLnH * root.imgRow
            width: root.pChW * root.imgColsN
            height: root.pLnH * root.imgRowsN
            source: "pfp.png"
            fillMode: Image.PreserveAspectCrop
            clip: true
            smooth: true
        }

        TextInput {
            id: userInput
            x: root.pChW * root.inCol; y: root.pLnH * root.rowUser
            width: root.pChW * root.inColsN; height: root.pLnH
            color: root.cPanel; selectionColor: root.cPanel; selectedTextColor: "#000000"
            font.family: root.monoFont; font.pixelSize: root.uiPx
            verticalAlignment: TextInput.AlignVCenter
            maximumLength: root.inColsN
            clip: true
            selectByMouse: true
            cursorDelegate: cursorComp
            text: (typeof userModel !== "undefined" && userModel.lastUser) ? userModel.lastUser : "r3dg0d"
            Keys.onReturnPressed: passInput.forceActiveFocus()
            Keys.onTabPressed: passInput.forceActiveFocus()
        }

        TextInput {
            id: passInput
            x: root.pChW * root.inCol; y: root.pLnH * root.rowPass
            width: root.pChW * root.inColsN; height: root.pLnH
            color: root.cPanel; selectionColor: root.cPanel; selectedTextColor: "#000000"
            font.family: root.monoFont; font.pixelSize: root.uiPx
            verticalAlignment: TextInput.AlignVCenter
            maximumLength: root.inColsN
            clip: true
            selectByMouse: true
            cursorDelegate: cursorComp
            echoMode: TextInput.Password
            passwordCharacter: "*"
            focus: true
            onTextChanged: root.denied = false
            Keys.onReturnPressed: root.doLogin()
            Keys.onEnterPressed: root.doLogin()
            Keys.onTabPressed: userInput.forceActiveFocus()
            Keys.onEscapePressed: text = ""
        }

        Text {
            x: 0; y: root.pLnH * root.rowStatus
            width: panel.width
            horizontalAlignment: Text.AlignHCenter
            color: root.denied ? root.cPanel : root.cDim
            opacity: root.denied ? (root.blinkOn ? 1 : 0) : 1
            font.family: root.monoFont; font.pixelSize: root.uiPx
            text: root.denied ? "!!  ACCESS DENIED  !!"
                 : (root.capsOn ? "[  CAPS LOCK ON  ]" : ">>  ENTER to log in  <<")
        }
    }

    Component {
        id: cursorComp
        Rectangle {
            width: Math.max(2, root.pChW)
            height: fmUi.height
            color: root.cPanel
            visible: root.blinkOn
        }
    }

    // ---- power controls ----
    Rectangle {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: Math.round(fm.lineSpacing / 2)
        width: powerHint.width + 16; height: powerHint.height + 8
        color: "#000000"
        Text {
            id: powerHint
            anchors.centerIn: parent
            color: root.cDim
            font.family: root.monoFont; font.pixelSize: root.rainPx
            text: "[F1] SLEEP   [F2] REBOOT   [F3] POWEROFF"
        }
    }
    Shortcut { sequence: "F1"; onActivated: if (typeof sddm !== "undefined") sddm.suspend() }
    Shortcut { sequence: "F2"; onActivated: if (typeof sddm !== "undefined") sddm.reboot() }
    Shortcut { sequence: "F3"; onActivated: if (typeof sddm !== "undefined") sddm.powerOff() }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null
        function onLoginFailed() {
            root.denied = true
            passInput.text = ""
            passInput.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        buildPanel()
        initScene()
        passInput.forceActiveFocus()
    }
}
