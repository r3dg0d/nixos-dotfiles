#!/usr/bin/env bash
# Headless smoke test for the ascii-city greeter.
#
# SDDM injects `sddm`, `sessionModel`, `userModel` and `keyboard` into the
# theme's root context, and the real greeter swallows QML errors — so loading
# the theme under sddm-greeter-qt6 proves nothing. Instead this builds a copy
# of Main.qml with those four stubbed out by QML objects of the same id, loads
# it in the plain `qml` runtime on the offscreen platform, and asserts on what
# the session selector actually resolved to.
#
# Requires: qt6.qtbase + qt6.qtdeclarative (nix develop, or `nix shell
# nixpkgs#qt6.qtbase nixpkgs#qt6.qtdeclarative`).
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
theme=$(dirname "$here")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

qml_bin=${QML_BIN:-$(command -v qml || true)}
if [ -z "$qml_bin" ]; then
  echo "error: no 'qml' runtime on PATH. Try:" >&2
  echo "  nix shell nixpkgs#qt6.qtbase nixpkgs#qt6.qtdeclarative -c $0" >&2
  exit 127
fi

cp "$theme/pfp.png" "$work/"

# ---- build the instrumented copy -------------------------------------------
{
  # Everything up to and including `id: root`
  sed '/^    id: root$/q' "$theme/Main.qml"
  cat <<'STUB'

    // ==== TEST HARNESS — injected by test/run-harness.sh, not shipped ====
    width: 2560
    height: 1440

    ListModel {
        id: sessionModel
        property int lastIndex: 1
        ListElement { name: "COSMIC"; file: "/nix/store/aaaa-desktops/share/wayland-sessions/cosmic.desktop" }
        ListElement { name: "Niri";   file: "/nix/store/aaaa-desktops/share/wayland-sessions/niri.desktop" }
        ListElement { name: "GNOME";  file: "/nix/store/aaaa-desktops/share/wayland-sessions/gnome.desktop" }
    }
    QtObject { id: userModel;  property string lastUser: "tester" }
    QtObject { id: keyboard;   property bool capsLock: false }
    QtObject {
        id: sddm
        property string hostName: "testbox"
        function login(u, p, i) { console.warn("PROBE login user=" + u + " index=" + i) }
        function suspend() {}
        function reboot() {}
        function powerOff() {}
    }
    Timer {
        interval: 400; running: true; repeat: false
        onTriggered: {
            console.warn("PROBE sessCount=" + root.sessCount)
            console.warn("PROBE initialName=" + root.sessName)
            root.cycleSession(1)
            console.warn("PROBE afterRight=" + root.sessName)
            root.cycleSession(-1)
            root.cycleSession(-1)
            console.warn("PROBE afterTwoLeft=" + root.sessName)
            console.warn("PROBE wrapIndex=" + root.sessIndex)
            root.doLogin()
            console.warn("PROBE layout rowUser=" + root.rowUser
                         + " rowPass=" + root.rowPass
                         + " rowDesk=" + root.rowDesk
                         + " rowStatus=" + root.rowStatus
                         + " inCol=" + root.inCol
                         + " inColsN=" + root.inColsN)
            Qt.quit()
        }
    }
    // ==== END TEST HARNESS ====
STUB
  # Everything after `id: root`
  sed '1,/^    id: root$/d' "$theme/Main.qml"
} > "$work/Main.qml"

# ---- run --------------------------------------------------------------------
out=$work/out.log
set +e
env -C "$work" \
  QT_QPA_PLATFORM=offscreen \
  QT_FORCE_STDERR_LOGGING=1 \
  QT_LOGGING_RULES='qt.*=false' \
  QML_XHR_ALLOW_FILE_READ=1 \
  timeout 60 "$qml_bin" Main.qml >"$out" 2>&1
rc=$?
set -e

grep -v '^qt\.' "$out" || true

fail=0
check() { # check <description> <expected-substring>
  if grep -qF "$2" "$out"; then
    printf '  ok   %s\n' "$1"
  else
    printf '  FAIL %s (expected %q)\n' "$1" "$2"
    fail=1
  fi
}

echo
echo "assertions:"
# No QML error should ever reach the log.
if grep -qiE '(^| )(Error|TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign)' "$out"; then
  echo "  FAIL no QML runtime errors"
  fail=1
else
  echo "  ok   no QML runtime errors"
fi
check "sees all three stub sessions"      "PROBE sessCount=3"
check "honours sessionModel.lastIndex"    "PROBE initialName=Niri"
check "right steps forward"               "PROBE afterRight=GNOME"
check "left steps back (with wraparound)" "PROBE afterTwoLeft=COSMIC"
check "index wraps into range"            "PROBE wrapIndex=0"
check "login passes the chosen index"     "PROBE login user=tester index=0"
check "three input rows are consecutive"  "rowUser=12 rowPass=13 rowDesk=14"

if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
  echo "  FAIL qml exited $rc"
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAILED — full log:"
  cat "$out"
  exit 1
fi
