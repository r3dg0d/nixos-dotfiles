{ lib
, stdenvNoCC
, writeShellApplication
, writeTextFile
, symlinkJoin
, python3Packages
, coreutils
, gnugrep
, gnused
, jq
, procps
, alacritty
, niri
}:

# A screensaver for the niri session, animated with
# terminaltexteffects (https://github.com/ChrisBuilds/terminaltexteffects)
# over the NixOS logo.
#
# Three pieces, because they run in three different places:
#
#   nixos-screensaver-loop  the animation itself. Runs *inside* a terminal and
#                           does nothing but draw until it is killed.
#   nixos-screensaver       the control surface: start/stop/toggle/status.
#                           Opens one terminal per connected monitor.
#   the logo                trimmed of its blank border and installed to the
#                           store, so the screensaver does not depend on the
#                           dotfiles checkout being present.
#
# Idle handling is *not* here — that is swayidle, wired up in
# modules/nixos/desktop/screensaver.nix. This package only knows how to put
# the thing on screen and take it away again.

let
  logo = writeTextFile {
    name = "nixos-logo-ascii";
    destination = "/share/nixos-screensaver/logo.txt";
    text = builtins.readFile ./logo.txt;
  };

  tte = "${python3Packages.terminaltexteffects}/bin/tte";

  # The app-id is the contract between the three pieces: the control script
  # matches on it to clean up, and config/niri/config.kdl has a window-rule
  # keyed to it that makes the terminal fullscreen and undecorated. An app-id
  # rather than a title because a title belongs to whatever is running in the
  # terminal and can change under you; the app-id is set once at map time.
  appId = "nixos-screensaver";

  # alacritty, not the ghostty used everywhere else in this rice, for one
  # specific reason: ghostty defaults to `gtk-single-instance = detect`, so a
  # second `ghostty` while one is already running hands the request to the
  # existing process instead of starting a new one — and the screensaver needs
  # one independent window per monitor. alacritty forks a fresh process every
  # time, which is the property that matters here.
  term = "${alacritty}/bin/alacritty";

  # ---- the animation ------------------------------------------------------
  loop = writeShellApplication {
    name = "nixos-screensaver-loop";
    runtimeInputs = [ python3Packages.terminaltexteffects coreutils ];
    text = ''
      set -uo pipefail

      LOGO="''${NIXOS_SCREENSAVER_LOGO:-${logo}/share/nixos-screensaver/logo.txt}"

      # Effects that suit a logo held in the middle of a black screen: they
      # either assemble it, dissolve it, or wash over it. Excluded are the
      # ones that scroll the canvas, depend on reading the text as prose, or
      # finish so fast there is nothing to look at.
      #
      # `synthgrid` is left out for a duller reason: it is the one effect that
      # does not take --final-gradient-stops, so it cannot be held to the
      # palette.
      EFFECTS=(
        beams binarypath blackhole bouncyballs bubbles burn crumble decrypt
        errorcorrect expand fireworks laseretch matrix middleout
        orbittingvolley pour rain randomsequence rings scattered slice slide
        spotlights spray swarm sweep unstable vhstape waves wipe
      )

      # The rice palette: neon green through to the brighter green the waybar
      # accents use. Every effect above honours these as its resolved colour,
      # so the animation stays on-theme no matter which one comes up.
      STOPS=(00ff41 39ff14 00ff41)

      # Terminals do not always come up at their final size — a fullscreen
      # window is mapped small and then resized. Starting mid-resize gets the
      # canvas centred against the wrong dimensions, so wait one beat.
      sleep 0.4

      printf '\033[?25l'                      # hide the cursor
      trap 'printf "\033[?25h\033[0m\n"' EXIT # ...and put it back

      while :; do
        effect=''${EFFECTS[RANDOM % ''${#EFFECTS[@]}]}

        clear
        # --canvas-{width,height} 0 tracks the terminal rather than the text,
        # and anchoring both canvas and text to 'c' is what keeps the logo in
        # the middle of whatever monitor this instance landed on.
        ${tte} \
          --input-file "$LOGO" \
          --canvas-width 0 --canvas-height 0 \
          --anchor-canvas c --anchor-text c \
          --terminal-background-color 000000 \
          --frame-rate 60 \
          --no-eol \
          "$effect" --final-gradient-stops "''${STOPS[@]}" \
          || true

        # Hold the assembled logo before dissolving it into the next effect.
        sleep 3
      done
    '';
  };

  # ---- the control surface ------------------------------------------------
  control = writeShellApplication {
    name = "nixos-screensaver";
    runtimeInputs = [ coreutils gnugrep gnused jq procps alacritty niri loop ];
    text = ''
      set -uo pipefail

      APPID=${lib.escapeShellArg appId}
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/nixos-screensaver"

      # Is a screensaver terminal currently mapped? niri is the authority
      # here rather than a pidfile: a terminal that was closed by hand, or
      # that died, must not leave the screensaver looking "on" forever.
      running() {
        niri msg --json windows 2>/dev/null \
          | jq -e --arg a "$APPID" 'any(.[]; .app_id == $a)' >/dev/null 2>&1
      }

      start() {
        if running; then
          exit 0
        fi

        # One terminal per connected monitor, otherwise the screensaver comes
        # up on one ultrawide and leaves the desktop sitting there on the
        # other. niri opens a new window on the focused monitor, so focus is
        # walked across the outputs and put back where it started.
        local outputs origin
        mapfile -t outputs < <(niri msg --json outputs 2>/dev/null | jq -r 'keys[]')
        origin=$(niri msg --json focused-output 2>/dev/null | jq -r '.name // empty')

        # Remember where focus was so `stop` can restore it. Written before
        # the first window opens, since opening one moves focus.
        mkdir -p "$STATE"
        printf '%s' "''${origin:-}" > "$STATE/origin"

        if [ ''${#outputs[@]} -eq 0 ]; then
          # No niri (or no outputs): still better to show something than to
          # silently do nothing.
          spawn_on ""
          return
        fi

        local out
        for out in "''${outputs[@]}"; do
          niri msg action focus-monitor "$out" >/dev/null 2>&1 || true
          spawn_on "$out"
        done

        [ -n "''${origin:-}" ] && niri msg action focus-monitor "$origin" >/dev/null 2>&1 || true
      }

      # A fullscreen terminal running nothing but the animation. The niri
      # window-rule keyed on the app-id does the fullscreening.
      #
      # Font size is the only thing that decides how much of the monitor the
      # logo covers, because the logo is a fixed 99x47 block of characters and
      # nothing scales it. That also makes it the one setting that can break
      # the screensaver: too large and the terminal has fewer than 47 rows, at
      # which point tte quietly crops the logo instead of complaining. On the
      # 1440px panels here, 18 yields exactly 49 rows — it fits, but with a
      # single row of margin, and anything shorter would clip. 16 gives about
      # 55 rows, so the logo still covers ~85% of the height with room to
      # spare. services.screensaver.fontSize overrides it for other panels.
      spawn_on() {
        ${term} \
          --class "$APPID,$APPID" \
          -o font.size="''${NIXOS_SCREENSAVER_FONT_SIZE:-16}" \
          -o 'colors.primary.background="#000000"' \
          -o 'colors.primary.foreground="#00ff41"' \
          -o window.padding.x=0 \
          -o window.padding.y=0 \
          -o 'window.decorations="None"' \
          -e nixos-screensaver-loop \
          >/dev/null 2>&1 &
        disown 2>/dev/null || true

        # Give niri time to map and fullscreen it before focus moves on to the
        # next monitor, or the rule lands on the wrong output.
        sleep 0.6
      }

      stop() {
        # Close the windows through the compositor first: alacritty exits when
        # its window goes, which takes the animation with it.
        local ids id
        mapfile -t ids < <(niri msg --json windows 2>/dev/null \
          | jq -r --arg a "$APPID" '.[] | select(.app_id == $a) | .id')
        for id in "''${ids[@]}"; do
          [ -n "$id" ] && niri msg action close-window --id "$id" >/dev/null 2>&1 || true
        done

        # Belt and braces. If niri could not be reached, or a terminal somehow
        # outlived its window, the animation must still not be left running —
        # a screensaver nobody can see is worse than one nobody asked for.
        pkill -f 'nixos-screensaver-loop' >/dev/null 2>&1 || true

        # Put focus back on the monitor the user was actually using.
        local origin
        origin=$(cat "$STATE/origin" 2>/dev/null || true)
        [ -n "$origin" ] && niri msg action focus-monitor "$origin" >/dev/null 2>&1 || true
        rm -f "$STATE/origin"
      }

      case "''${1:-}" in
        start)  start ;;
        stop)   stop ;;
        toggle) if running; then stop; else start; fi ;;
        status)
          if running; then echo "screensaver: on"; else echo "screensaver: off"; fi
          ;;
        *)
          echo "usage: nixos-screensaver {start|stop|toggle|status}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
symlinkJoin {
  name = "nixos-screensaver";
  paths = [ control loop logo ];

  meta = with lib; {
    description = "Idle screensaver for niri: the NixOS logo animated with terminaltexteffects";
    homepage = "https://github.com/ChrisBuilds/terminaltexteffects";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "nixos-screensaver";
  };
}
