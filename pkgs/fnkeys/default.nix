{ writeShellApplication
, coreutils
, gnugrep
, gawk
, gnused
, wireplumber
, playerctl
, monitor-brightness
, quickshell-mirror
, niri
}:

# `fnkey <action>` — the single entry point behind every Fn + F1…F12 binding in
# config/niri/config.kdl.
#
# Why a dispatcher instead of binding wpctl/playerctl straight to the keys:
# each press has to do the thing *and* say what it did. Doing both here means
# the OSD always reflects the state the system actually ended up in (read back
# after the change, not guessed before it), and the keys keep working when
# quickshell is not running — the `qs ipc call` is best-effort, the action is
# not.
#
# The OSD payload is one JSON object handed to config/quickshell/Osd.qml's
# `notify` IPC function:
#   { kind: "bar"|"toast", icon, label, value: 0-100, muted: bool, sub: str }
#
# Actions (the F-key each is bound to on a keyboard with a standard Fn layer):
#   F1  brightness-down   F5  mic-mute     F9   next
#   F2  brightness-up     F6  webcam       F10  mute
#   F3  overview          F7  previous     F11  volume-down
#   F4  search            F8  play-pause   F12  volume-up

writeShellApplication {
  name = "fnkey";
  runtimeInputs = [ coreutils gnugrep gnused gawk wireplumber playerctl monitor-brightness quickshell-mirror niri ];
  text = ''
    set -euo pipefail

    VOL_STEP=5
    BRI_STEP=5
    SINK="@DEFAULT_AUDIO_SINK@"
    SOURCE="@DEFAULT_AUDIO_SOURCE@"

    # ---- OSD --------------------------------------------------------------
    # Best-effort by design: if quickshell is not up, the key still worked.
    # `qs ipc call` takes the JSON as one argv element, so no shell quoting
    # games are involved.
    #
    # The handler is `notify`, not `show`: `qs ipc show` is a subcommand in its
    # own right, so `... call osd show <json>` is parsed as that and the
    # payload is rejected. See config/quickshell/Osd.qml.
    osd() { qs ipc call osd notify "$1" >/dev/null 2>&1 || true; }

    # JSON-escape a string for the payload (titles carry quotes and backslashes
    # more often than you would like).
    esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g'; }

    bar()   { osd "{\"kind\":\"bar\",\"icon\":\"$1\",\"label\":\"$(esc "$2")\",\"value\":$3,\"muted\":''${4:-false}}"; }
    toast() { osd "{\"kind\":\"toast\",\"icon\":\"$1\",\"label\":\"$(esc "$2")\",\"sub\":\"$(esc "''${3:-}")\",\"muted\":''${4:-false}}"; }

    # ---- audio ------------------------------------------------------------
    # wpctl get-volume prints e.g. "Volume: 0.63 [MUTED]".
    vol_of()   { wpctl get-volume "$1" 2>/dev/null | awk '{ printf "%d", $2 * 100 + 0.5 }'; }
    muted_of() { wpctl get-volume "$1" 2>/dev/null | grep -q MUTED && echo true || echo false; }

    # Icon ramp so the glyph carries the level at a glance.
    sink_icon() {
      local v=$1 m=$2
      [ "$m" = true ] && { printf '󰝟'; return; }
      if   [ "$v" -lt 34 ]; then printf '󰕿'
      elif [ "$v" -lt 67 ]; then printf '󰖀'
      else                       printf '󰕾'
      fi
    }

    show_sink() {
      local v m
      v=$(vol_of "$SINK"); m=$(muted_of "$SINK")
      bar "$(sink_icon "$v" "$m")" "Volume" "''${v:-0}" "$m"
    }

    show_source() {
      local m
      m=$(muted_of "$SOURCE")
      if [ "$m" = true ]; then
        toast "󰍭" "Microphone" "muted" true
      else
        toast "󰍬" "Microphone" "live" false
      fi
    }

    # ---- media ------------------------------------------------------------
    # playerctl exits non-zero with no player; that is a normal state here, not
    # an error, so every call is guarded.
    now_playing() {
      local artist title
      title=$(playerctl metadata --format '{{title}}' 2>/dev/null || echo "")
      artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null || echo "")
      if [ -n "$artist" ] && [ -n "$title" ]; then printf '%s — %s' "$artist" "$title"
      elif [ -n "$title" ];                   then printf '%s' "$title"
      else                                         printf 'no player'
      fi
    }

    # The new track only lands in the player's metadata a moment after the
    # skip, so give it one short beat before reading it back.
    media_toast() {
      sleep 0.25
      toast "$1" "$2" "$(now_playing)"
    }

    case "''${1:-}" in
      # ---- F1 / F2 — display brightness over DDC/CI ----------------------
      brightness-down)
        v=$(monitor-brightness down "$BRI_STEP")
        bar "󰃞" "Brightness" "$v"
        ;;
      brightness-up)
        v=$(monitor-brightness up "$BRI_STEP")
        bar "󰃠" "Brightness" "$v"
        ;;

      # ---- F3 — the niri overview ----------------------------------------
      overview)
        niri msg action toggle-overview >/dev/null 2>&1 || true
        ;;

      # ---- F4 — SearXNG search widget ------------------------------------
      search)
        # No OSD: the widget *is* the feedback.
        qs ipc call websearch toggle >/dev/null 2>&1 || true
        ;;

      # ---- F5 — microphone mute switch -----------------------------------
      mic-mute)
        wpctl set-mute "$SOURCE" toggle >/dev/null 2>&1 || true
        show_source
        ;;

      # ---- F6 — webcam mirror --------------------------------------------
      webcam)
        qs ipc call mirror toggle >/dev/null 2>&1 || true
        toast "󰄀" "Webcam" "mirror toggled"
        ;;

      # ---- F7 / F8 / F9 — transport --------------------------------------
      previous)
        playerctl previous >/dev/null 2>&1 || true
        media_toast "󰒮" "Previous"
        ;;
      play-pause)
        playerctl play-pause >/dev/null 2>&1 || true
        sleep 0.15
        status=$(playerctl status 2>/dev/null || echo "Stopped")
        if [ "$status" = "Playing" ]; then
          toast "󰐊" "Playing" "$(now_playing)"
        else
          toast "󰏤" "Paused" "$(now_playing)"
        fi
        ;;
      next)
        playerctl next >/dev/null 2>&1 || true
        media_toast "󰒭" "Next"
        ;;

      # ---- F10 / F11 / F12 — output volume -------------------------------
      mute)
        wpctl set-mute "$SINK" toggle >/dev/null 2>&1 || true
        show_sink
        ;;
      volume-down)
        wpctl set-volume "$SINK" "''${VOL_STEP}%-" >/dev/null 2>&1 || true
        show_sink
        ;;
      volume-up)
        # -l caps at 100% so a held key cannot push the sink past unity into
        # software gain (which clips).
        wpctl set-volume -l 1.0 "$SINK" "''${VOL_STEP}%+" >/dev/null 2>&1 || true
        show_sink
        ;;

      *)
        {
          echo "usage: fnkey <action>"
          echo
          echo "  brightness-down  brightness-up     display brightness (DDC/CI)"
          echo "  overview                           toggle the niri overview"
          echo "  search                             SearXNG search widget"
          echo "  mic-mute                           microphone mute switch"
          echo "  webcam                             webcam mirror"
          echo "  previous  play-pause  next         media transport"
          echo "  mute  volume-down  volume-up       output volume"
        } >&2
        exit 2
        ;;
    esac
  '';
}
