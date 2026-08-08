{ writeShellApplication
, ddcutil
, coreutils
, gnused
, gnugrep
, gawk
, util-linux
, brightnessctl
}:

# Brightness control for *external* monitors — the two 3440×1440 ultrawides.
#
# Desktop monitors have no /sys/class/backlight: their panel brightness lives
# behind DDC/CI, a small command protocol the GPU speaks to the display over
# the I²C lines of the DP/HDMI cable. `ddcutil` is the client for that; VCP
# feature code 0x10 is "Brightness". So this is a thin, *fast* wrapper around
# ddcutil rather than a reimplementation — talking raw I²C from a shell script
# would be strictly worse.
#
# Two things make ddcutil unpleasant to bind straight to a key, and both are
# what this script exists to fix:
#
#   1. `ddcutil detect` costs ~1s (it probes every I²C bus). So the bus numbers
#      are discovered once and cached in $XDG_RUNTIME_DIR; every later call is
#      a direct `--bus N setvcp`.
#   2. A held-down key produces far more events than the monitors can answer
#      (each setvcp is 50-200ms of I²C). So the *level* is updated instantly in
#      a state file — which is what the OSD reads — and a single background
#      applier drains it towards the hardware, coalescing a burst of presses
#      into the few writes the panel can actually take.
#
# If no DDC-capable display is found (a laptop panel, a KVM that eats I²C, or
# missing i2c-dev permissions) it falls back to brightnessctl on the internal
# backlight, so the keys still do something sensible.
#
# Usage:
#   monitor-brightness get            → current level, 0-100
#   monitor-brightness set 60
#   monitor-brightness up   [step]    → prints the new level
#   monitor-brightness down [step]
#   monitor-brightness detect         → re-probe the buses (after replugging)
#   monitor-brightness status         → what it thinks it is driving

writeShellApplication {
  name = "monitor-brightness";
  runtimeInputs = [ ddcutil coreutils gnused gnugrep gawk util-linux brightnessctl ];
  text = ''
    set -euo pipefail

    STEP_DEFAULT=5
    STATE="''${XDG_RUNTIME_DIR:-/tmp}/monitor-brightness"
    mkdir -p "$STATE"
    BUSES="$STATE/buses"      # one I²C bus number per line, "" = no DDC display
    LEVEL="$STATE/level"      # last requested level, 0-100 — the OSD's source
    LOCK="$STATE/lock"        # guards the read-modify-write of LEVEL
    APPLY="$STATE/apply.lock" # held by whichever process is draining to hardware

    # ddcutil's default inter-command sleeps are tuned for the slowest displays
    # on the market; both of these answer fine at a third of that, which is the
    # difference between a keypress feeling instant and feeling laggy.
    DDC=(ddcutil --sleep-multiplier 0.3)

    clamp() {
      local v=$1
      [ "$v" -lt 0 ] && v=0
      [ "$v" -gt 100 ] && v=100
      printf '%s' "$v"
    }

    # ---- bus discovery ----------------------------------------------------
    # Cached, because `detect` is the slow part. `monitor-brightness detect`
    # (or unplugging the cache along with the boot) is how it gets refreshed.
    discover() {
      local out bus buses=""
      # A display that answers VCP 0x10 is one we can drive. Anything else —
      # capture cards, the audio i2c on the GPU — is skipped.
      out=$(ddcutil detect --brief 2>/dev/null || true)
      while read -r bus; do
        [ -n "$bus" ] || continue
        if "''${DDC[@]}" --bus "$bus" getvcp 10 --brief >/dev/null 2>&1; then
          buses+="$bus"$'\n'
        fi
      done < <(printf '%s\n' "$out" | sed -n 's#^ *I2C bus: */dev/i2c-\([0-9]\+\) *$#\1#p')
      printf '%s' "$buses" > "$BUSES"
      printf '%s' "$buses"
    }

    buses() {
      if [ ! -f "$BUSES" ]; then
        discover
      else
        cat "$BUSES"
      fi
    }

    # ---- hardware I/O -----------------------------------------------------
    hw_read() {
      local bus
      bus=$(buses | head -n1)
      if [ -n "$bus" ]; then
        # --brief prints: VCP 10 C <current> <max>
        "''${DDC[@]}" --bus "$bus" getvcp 10 --brief 2>/dev/null \
          | awk '/^VCP 10/ { print $4; exit }'
      else
        # Internal backlight fallback: brightnessctl reports raw units.
        local cur max
        cur=$(brightnessctl get 2>/dev/null || echo "")
        max=$(brightnessctl max 2>/dev/null || echo "")
        [ -n "$cur" ] && [ -n "$max" ] && [ "$max" -gt 0 ] \
          && printf '%s' "$(( cur * 100 / max ))"
      fi
    }

    hw_write() {
      local v=$1 bus any=0
      while read -r bus; do
        [ -n "$bus" ] || continue
        any=1
        # Both panels in parallel — one ultrawide should not wait on the other.
        # --noverify skips ddcutil's read-back after the write; at 5% a press
        # there is nothing useful to do with the confirmation anyway.
        "''${DDC[@]}" --noverify --bus "$bus" setvcp 10 "$v" >/dev/null 2>&1 &
      done < <(buses)
      wait
      [ "$any" -eq 1 ] || brightnessctl set "''${v}%" >/dev/null 2>&1 || true
    }

    # Drain LEVEL towards the hardware. Only one of these runs at a time: a
    # second invocation would just be fighting for the same I²C lines, and the
    # one already running will pick up the newer value on its next pass.
    apply_async() {
      (
        exec 8>"$APPLY"
        flock -n 8 || exit 0
        local last="" want
        while :; do
          want=$(cat "$LEVEL" 2>/dev/null || echo "")
          [ -n "$want" ] || exit 0
          [ "$want" = "$last" ] && exit 0
          last=$want
          hw_write "$want"
        done
      ) >/dev/null 2>&1 &
      disown 2>/dev/null || true
    }

    # ---- level bookkeeping ------------------------------------------------
    # The cached level is authoritative once we have written one: re-reading
    # over I²C on every press is both slow and, mid-ramp, wrong.
    current() {
      local v
      v=$(cat "$LEVEL" 2>/dev/null || echo "")
      if [ -z "$v" ]; then
        v=$(hw_read || echo "")
        [ -n "$v" ] || v=50   # nothing answered; assume mid-scale so keys work
        printf '%s' "$v" > "$LEVEL"
      fi
      printf '%s' "$v"
    }

    nudge() {
      local delta=$1 cur new
      exec 9>"$LOCK"
      flock -x 9
      cur=$(current)
      new=$(clamp "$(( cur + delta ))")
      printf '%s' "$new" > "$LEVEL"
      flock -u 9
      apply_async
      printf '%s\n' "$new"
    }

    cmd=''${1:-get}
    case "$cmd" in
      get)
        current; echo
        ;;
      set)
        v=$(clamp "''${2:?usage: monitor-brightness set <0-100>}")
        printf '%s' "$v" > "$LEVEL"
        apply_async
        printf '%s\n' "$v"
        ;;
      up)
        nudge "''${2:-$STEP_DEFAULT}"
        ;;
      down)
        nudge "-''${2:-$STEP_DEFAULT}"
        ;;
      detect)
        rm -f "$LEVEL"
        found=$(discover)
        echo "DDC/CI displays: $(printf '%s' "$found" | grep -c . || true)"
        printf '%s' "$found" | sed 's#^#  /dev/i2c-#'
        ;;
      status)
        echo "state:   $STATE"
        echo "level:   $(current)"
        echo "buses:   $(buses | tr '\n' ' ')"
        echo "backend: $([ -s "$BUSES" ] && echo 'ddcutil (DDC/CI)' || echo 'brightnessctl (internal backlight)')"
        ;;
      *)
        echo "usage: monitor-brightness {get|set <0-100>|up [step]|down [step]|detect|status}" >&2
        exit 2
        ;;
    esac
  '';
}
