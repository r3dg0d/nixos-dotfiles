#!/usr/bin/env bash
#
# install.sh — bootstrap this repository onto a NixOS machine.
#
# This script does NOT configure the desktop itself. Everything that makes up
# the system — packages, services, SDDM, niri, COSMIC, the SIVA stack, the
# wallpaper — is declared in the flake. All this does is the handful of things
# a declarative configuration cannot do for itself:
#
#   * check the machine can actually take it (NixOS, flakes, tooling, disk)
#   * pick which host in the flake to install
#   * make sure hosts/<host>/hardware-configuration.nix describes THIS machine
#     (never blindly overwriting one that already does)
#   * seed the one out-of-band secret (SearXNG's key)
#   * build, then switch
#   * optionally download SIVA's multi-gigabyte model assets
#   * report honestly on what is working and what is waiting for a reboot
#
# Safe to re-run: every step is idempotent and nothing is destroyed without a
# timestamped backup.
set -euo pipefail

#=============================================================================
# output
#=============================================================================

if [[ -t 1 ]] && [[ -z ${NO_COLOR:-} ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_DIM=''
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
note() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
warn() { printf '%s !! %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()  { printf '\n%serror:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }

#=============================================================================
# options
#=============================================================================

HOST=""
DO_SWITCH=1
CHECK_ONLY=0
DO_ASSETS=""          # "", 1 or 0 — empty means ask
ASSUME_YES=0
REGEN_HARDWARE=0

usage() {
    cat <<EOF
${C_BOLD}install.sh${C_RESET} — bootstrap this NixOS configuration

  ./install.sh [options]

Options:
  --host NAME            Flake host to install (default: match \$(hostname),
                         else the only one, else ask)
  --build-only           Build the configuration but do not activate it
  --check-only           Skip straight to the status report; change nothing
  --regenerate-hardware  Replace hosts/<host>/hardware-configuration.nix with a
                         freshly generated one (the old file is backed up).
                         Required the first time on a machine whose hardware
                         config in this repo came from somewhere else.
  --fetch-assets         Download SIVA's STT/TTS/wake-word models afterwards
  --no-fetch-assets      Skip that download
  -y, --yes              Do not prompt; take the safe default for every question
  -h, --help             This text

Examples:
  ./install.sh                          # interactive, full install
  ./install.sh --host nixos-btw -y      # unattended
  ./install.sh --build-only             # dry run: prove it builds, change nothing
  ./install.sh --check-only             # just re-print the status report
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)                 HOST=${2:-}; shift 2 || die "--host needs a value" ;;
        --host=*)               HOST=${1#*=}; shift ;;
        --build-only)           DO_SWITCH=0; shift ;;
        --check-only)           CHECK_ONLY=1; shift ;;
        --regenerate-hardware)  REGEN_HARDWARE=1; shift ;;
        --fetch-assets)         DO_ASSETS=1; shift ;;
        --no-fetch-assets)      DO_ASSETS=0; shift ;;
        -y|--yes)               ASSUME_YES=1; shift ;;
        -h|--help)              usage; exit 0 ;;
        *)                      usage >&2; die "unknown option: $1" ;;
    esac
done

# ask <question> <default-yes:0|1>  -> 0 if yes
ask() {
    local q=$1 default=${2:-0} reply prompt
    if (( default )); then prompt="[Y/n]"; else prompt="[y/N]"; fi
    if (( ASSUME_YES )); then
        (( default )) && return 0 || return 1
    fi
    if [[ ! -t 0 ]]; then
        note "not a terminal; assuming the default for: $q"
        (( default )) && return 0 || return 1
    fi
    read -r -p "    $q $prompt " reply || true
    case "${reply,,}" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        "")    (( default )) && return 0 || return 1 ;;
        *)     (( default )) && return 0 || return 1 ;;
    esac
}

#=============================================================================
# 1. preflight
#=============================================================================

step "Checking the machine"

[[ $(uname -s) == Linux ]] || die "this only runs on Linux"

if [[ ! -e /etc/NIXOS ]] && ! grep -qs '^ID=nixos' /etc/os-release; then
    die "this is not a NixOS system.
    install.sh applies a NixOS configuration; there is nothing useful it can do
    on another distribution. Install NixOS first (https://nixos.org/download)."
fi
info "NixOS: yes"

for tool in nix git; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done
info "nix:   $(nix --version)"
info "git:   $(git --version | cut -d' ' -f3)"

# Flakes may not be enabled yet on a stock install; pass the features
# explicitly rather than editing the user's nix.conf behind their back. Once
# this configuration is active, nix.settings.experimental-features makes them
# permanent (see modules/nixos/core.nix).
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
if nix flake --help >/dev/null 2>&1 && nix show-config 2>/dev/null | grep -q 'experimental-features.*flakes'; then
    info "flakes: already enabled"
else
    info "flakes: not enabled system-wide yet — passing them per-command"
fi

if (( EUID == 0 )); then
    SUDO=()
    TARGET_LOGIN=${SUDO_USER:-root}
else
    command -v sudo >/dev/null 2>&1 || die "not root and no sudo available"
    SUDO=(sudo)
    TARGET_LOGIN=$USER
fi
info "privileges: $( ((EUID==0)) && echo "running as root" || echo "will use sudo" )"

# A full desktop closure is large; refuse to start a build that will obviously
# run the disk out rather than failing three hours in.
avail_gib=$(df -BG --output=avail /nix 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if [[ -n $avail_gib ]] && (( avail_gib < 25 )); then
    warn "only ${avail_gib} GiB free on /nix. This configuration needs roughly 40 GiB"
    warn "of store for a first build. Consider 'nix-collect-garbage -d' first."
    ask "Continue anyway?" 0 || die "aborted"
else
    info "free space on /nix: ${avail_gib} GiB"
fi

#=============================================================================
# 2. locate the repository
#=============================================================================

step "Locating the repository"

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ -f $REPO/flake.nix ]] || die "no flake.nix next to install.sh (looked in $REPO)"
cd "$REPO"
info "repository: $REPO"

if [[ -d $REPO/.git ]]; then
    # Nix reads flakes out of git, so anything untracked is invisible to the
    # build and produces confusing "file not found" errors deep in eval.
    if untracked=$(git -C "$REPO" ls-files --others --exclude-standard -- '*.nix' 'assets/*' 2>/dev/null) \
       && [[ -n $untracked ]]; then
        warn "these files are untracked and will be INVISIBLE to the flake build:"
        while IFS= read -r f; do printf '        %s\n' "$f" >&2; done <<<"$untracked"
        warn "run 'git add' on them first, or the build will fail confusingly."
        ask "Continue anyway?" 0 || die "aborted"
    fi
fi

# The one input that is not fetchable from the network. Catch it here rather
# than letting nix fail with an opaque error after several minutes of eval.
while IFS= read -r localpath; do
    [[ -n $localpath ]] || continue
    if [[ ! -d $localpath ]]; then
        die "flake.nix refers to a local checkout that does not exist:

        $localpath

    That input cannot be fetched from the network. Either clone the project
    to that path, or remove its input from flake.nix (and the package it
    provides from modules/nixos/desktop/apps.nix) and re-run:

        nix flake lock --update-input <name>"
    fi
    info "local flake input present: $localpath"
done < <(grep -oP '(?<=git\+file://)[^"]+' flake.nix || true)

#=============================================================================
# 3. choose a host
#=============================================================================

step "Choosing the flake host"

mapfile -t HOSTS < <(
    nix "${NIX_FLAGS[@]}" eval --raw \
        ".#nixosConfigurations" --apply \
        'cfgs: builtins.concatStringsSep "\n" (builtins.attrNames cfgs)' 2>/dev/null \
    || true
)
(( ${#HOSTS[@]} )) || die "could not read nixosConfigurations from the flake"

if [[ -n $HOST ]]; then
    printf '%s\n' "${HOSTS[@]}" | grep -qxF "$HOST" \
        || die "no such host '$HOST'. Available: ${HOSTS[*]}"
elif (( ${#HOSTS[@]} == 1 )); then
    HOST=${HOSTS[0]}
    info "only one host defined"
elif printf '%s\n' "${HOSTS[@]}" | grep -qxF "$(hostname)"; then
    HOST=$(hostname)
    info "matched this machine's hostname"
else
    info "several hosts are defined:"
    select choice in "${HOSTS[@]}"; do
        [[ -n ${choice:-} ]] && { HOST=$choice; break; }
    done
    [[ -n $HOST ]] || die "no host chosen"
fi
info "host: ${C_BOLD}${HOST}${C_RESET}"

HOSTDIR=$REPO/hosts/$HOST
[[ -d $HOSTDIR ]] || die "flake declares host '$HOST' but $HOSTDIR does not exist"

TARGET_USER=$(nix "${NIX_FLAGS[@]}" eval --raw \
    ".#nixosConfigurations.$HOST.config.my.username" 2>/dev/null || echo "")
[[ -n $TARGET_USER ]] || die "could not determine the primary user for host $HOST"
TARGET_HOME=$(nix "${NIX_FLAGS[@]}" eval --raw \
    ".#nixosConfigurations.$HOST.config.my.homeDirectory")
info "primary user: $TARGET_USER ($TARGET_HOME)"

#=============================================================================
# 4. hardware configuration
#=============================================================================
#
# The single most dangerous file in the repo. hardware-configuration.nix names
# filesystem UUIDs, the boot device and the CPU — copy one machine's to another
# and the result does not boot. So: generate it if absent, and otherwise leave
# it alone unless the operator explicitly asks, always with a backup.

if (( CHECK_ONLY )); then
    step "--check-only: skipping hardware, secrets, build and switch"
    BUILT=$(readlink -f /run/current-system)
fi

if (( ! CHECK_ONLY )); then
step "Checking hardware configuration"

HW=$HOSTDIR/hardware-configuration.nix

generate_hardware() {
    local dest=$1 tmp
    tmp=$(mktemp)
    if command -v nixos-generate-config >/dev/null 2>&1; then
        info "running nixos-generate-config --show-hardware-config"
        "${SUDO[@]}" nixos-generate-config --show-hardware-config > "$tmp" \
            || { rm -f "$tmp"; return 1; }
    elif [[ -r /etc/nixos/hardware-configuration.nix ]]; then
        info "nixos-generate-config unavailable; reusing /etc/nixos/hardware-configuration.nix"
        cat /etc/nixos/hardware-configuration.nix > "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
    [[ -s $tmp ]] || { rm -f "$tmp"; return 1; }
    install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"
}

# Does the checked-in file describe a machine whose root filesystem actually
# exists here? A UUID from another computer will not resolve.
hardware_matches_machine() {
    local file=$1 uuid found=0
    while read -r uuid; do
        found=1
        [[ -e /dev/disk/by-uuid/$uuid ]] || return 1
    done < <(grep -oP '(?<=by-uuid/)[0-9A-Fa-f-]+' "$file" | sort -u)
    (( found )) || return 1   # no UUIDs at all is also suspicious
    return 0
}

if (( REGEN_HARDWARE )); then
    if [[ -f $HW ]]; then
        backup=$HW.$(date +%Y%m%d-%H%M%S).bak
        cp -a "$HW" "$backup"
        info "backed up existing file to $(basename "$backup")"
    fi
    generate_hardware "$HW" || die "could not generate a hardware configuration"
    info "wrote a freshly generated $HW"
elif [[ ! -f $HW ]]; then
    info "no hardware configuration for this host yet — generating one"
    generate_hardware "$HW" || die "could not generate a hardware configuration.
    Run 'sudo nixos-generate-config --show-hardware-config > $HW' by hand."
    info "wrote $HW"
elif hardware_matches_machine "$HW"; then
    info "existing hardware configuration matches this machine — leaving it alone"
else
    warn "hosts/$HOST/hardware-configuration.nix references filesystem UUIDs that"
    warn "do not exist on this machine. It was almost certainly generated on a"
    warn "different computer, and booting from it will fail."
    if ask "Replace it with a freshly generated one? (the old file is backed up)" 1; then
        backup=$HW.$(date +%Y%m%d-%H%M%S).bak
        cp -a "$HW" "$backup"
        info "backed up to $(basename "$backup")"
        generate_hardware "$HW" || die "could not generate a hardware configuration"
        info "regenerated $HW"
    else
        warn "keeping the existing file — the build may succeed but the system may not boot"
    fi
fi

# A file created just now is untracked, and nix cannot see untracked files in a
# git tree. Stage it so the build picks it up.
if [[ -d $REPO/.git ]] && ! git -C "$REPO" ls-files --error-unmatch "$HW" >/dev/null 2>&1; then
    git -C "$REPO" add --intent-to-add "$HW"
    info "staged the new hardware configuration so nix can see it"
fi

fi

#=============================================================================
# 5. out-of-band secrets
#=============================================================================
#
# Nothing secret is ever committed. The configuration references exactly one
# file outside the repo, and this creates it if it is missing.

if (( ! CHECK_ONLY )); then
step "Checking secrets"

SEARX_ENV=/etc/searxng.env
if [[ -e $SEARX_ENV ]]; then
    info "$SEARX_ENV exists — not touching it"
else
    info "generating $SEARX_ENV (SearXNG instance secret)"
    secret=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    printf 'SEARXNG_SECRET=%s\n' "$secret" \
        | "${SUDO[@]}" install -m 0600 -o root -g root /dev/stdin "$SEARX_ENV"
    unset secret
    info "written (mode 0600, root-only)"
fi

fi

#=============================================================================
# 6. build
#=============================================================================
#
# Build before switching, always. A failed build leaves the running system
# untouched; a failed switch does not.

if (( ! CHECK_ONLY )); then
step "Building the configuration for $HOST"
note "first run on a fresh machine downloads/compiles a lot — expect a while"

if ! "${SUDO[@]}" nixos-rebuild build \
        --flake "$REPO#$HOST" \
        --option experimental-features "nix-command flakes"; then
    die "the configuration failed to build. Nothing has been changed.
    Fix the error above and re-run; 'nix flake check' gives the same result."
fi
BUILT=$(readlink -f "$REPO/result")
info "built: $BUILT"

if (( ! DO_SWITCH )); then
    step "--build-only: stopping here"
    info "activate it later with:"
    info "  sudo nixos-rebuild switch --flake $REPO#$HOST"
    exit 0
fi

fi

#=============================================================================
# 7. switch
#=============================================================================

if (( ! CHECK_ONLY )); then
step "Activating the configuration"

if ! "${SUDO[@]}" nixos-rebuild switch \
        --flake "$REPO#$HOST" \
        --option experimental-features "nix-command flakes"; then
    die "activation failed. The previous generation is still bootable — pick it
    from the boot menu, or run:
        sudo nixos-rebuild switch --rollback"
fi
info "activated"

fi

#=============================================================================
# 8. SIVA model assets
#=============================================================================
#
# Multi-gigabyte downloads of user data, so they are a separate, optional,
# resumable step rather than part of the system closure.

SHARE=$TARGET_HOME/.local/share/siva

if (( ! CHECK_ONLY )); then
step "SIVA runtime assets"

if [[ -s $SHARE/ggml-base.en.bin && -s $SHARE/piper/en_US-lessac-medium.onnx ]]; then
    info "STT + TTS models already present"
else
    info "SIVA needs a whisper model, a piper voice and the openWakeWord models"
    info "(about 250 MB in total)."
    if [[ -z $DO_ASSETS ]]; then
        ask "Download them now?" 1 && DO_ASSETS=1 || DO_ASSETS=0
    fi
    if (( DO_ASSETS )); then
        if (( EUID == 0 )) && [[ $TARGET_LOGIN != root ]]; then
            sudo -u "$TARGET_USER" -H siva-fetch-assets || warn "asset download failed — re-run 'siva-fetch-assets' later"
        else
            siva-fetch-assets || warn "asset download failed — re-run 'siva-fetch-assets' later"
        fi
    else
        note "skipped. Run 'siva-fetch-assets' whenever you like."
    fi
fi

fi

#=============================================================================
# 9. self-check
#=============================================================================

step "Verifying the installation"
echo

PENDING=0
FAILED=0

# report <label> <status> [detail]
#   status: OK | PENDING_REBOOT | PENDING_LOGIN | SKIP | FAIL
report() {
    local label=$1 status=$2 detail=${3:-}
    local dots text colour
    printf -v dots '%s' "$(printf '.%.0s' $(seq 1 $(( 26 - ${#label} > 0 ? 26 - ${#label} : 1 ))))"
    case "$status" in
        OK)             colour=$C_GREEN;  text="OK" ;;
        PENDING_REBOOT) colour=$C_YELLOW; text="PENDING REBOOT"; PENDING=1 ;;
        PENDING_LOGIN)  colour=$C_YELLOW; text="PENDING LOGIN";  PENDING=1 ;;
        SKIP)           colour=$C_DIM;    text="not configured" ;;
        *)              colour=$C_RED;    text="FAIL"; FAILED=1 ;;
    esac
    printf '  %s %s %s%s%s' "$label" "$dots" "$colour" "$text" "$C_RESET"
    [[ -n $detail ]] && printf ' %s(%s)%s' "$C_DIM" "$detail" "$C_RESET"
    printf '\n'
}

SW=/run/current-system/sw
uid=$(id -u "$TARGET_USER" 2>/dev/null || echo "")
RUNTIME_DIR="/run/user/${uid:-0}"
SESSION_LIVE=0
[[ -n $uid && -d $RUNTIME_DIR ]] && SESSION_LIVE=1

# usercmd <args...> — run systemctl --user in the target user's session
usercmd() {
    (( SESSION_LIVE )) || return 1
    if (( EUID == 0 )); then
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$RUNTIME_DIR" systemctl --user "$@"
    else
        XDG_RUNTIME_DIR="$RUNTIME_DIR" systemctl --user "$@"
    fi
}

# check_user_unit <label> <unit>
check_user_unit() {
    local label=$1 unit=$2
    if [[ ! -e $SW/lib/systemd/user/$unit && ! -e /etc/systemd/user/$unit ]]; then
        report "$label" SKIP "no unit"
        return
    fi
    if (( ! SESSION_LIVE )); then
        report "$label" PENDING_LOGIN "unit installed"
        return
    fi
    if usercmd is-active --quiet "$unit"; then
        report "$label" OK "active"
    elif usercmd is-failed --quiet "$unit"; then
        report "$label" FAIL "journalctl --user -u $unit"
    else
        report "$label" PENDING_LOGIN "installed, not started"
    fi
}

# ---- the system itself ----
if [[ $(readlink -f /run/current-system) == "$BUILT" ]]; then
    report "NixOS configuration" OK "$(basename "$BUILT" | cut -c34-)"
else
    report "NixOS configuration" PENDING_REBOOT "activated, kernel/initrd may differ"
fi

if nix "${NIX_FLAGS[@]}" flake metadata "$REPO" >/dev/null 2>&1; then
    report "Flake" OK
else
    report "Flake" FAIL
fi

# ---- hardware ----
# No --raw: the value is a bool, and nix refuses to coerce one to a string.
if [[ $(nix "${NIX_FLAGS[@]}" eval ".#nixosConfigurations.$HOST.config.my.nvidia.enable" 2>/dev/null) == true ]]; then
    if [[ -e /proc/driver/nvidia/version ]]; then
        report "NVIDIA" OK "driver $(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' /proc/driver/nvidia/version | head -1)"
    else
        report "NVIDIA" PENDING_REBOOT "driver configured, module not loaded"
    fi
else
    report "NVIDIA" SKIP
fi

if (( SESSION_LIVE )) && [[ -S $RUNTIME_DIR/pipewire-0 ]]; then
    report "PipeWire" OK
elif [[ -e $SW/bin/pipewire ]]; then
    report "PipeWire" PENDING_LOGIN "installed"
else
    report "PipeWire" FAIL
fi

# ---- sessions ----
# Ask SDDM where it looks rather than guessing: on NixOS the session
# directories are a store path named in sddm.conf, not /usr/share.
SESSION_DIRS=$(grep -hs '^SessionDir=' /etc/sddm.conf.d/*.conf /etc/sddm.conf 2>/dev/null \
               | cut -d= -f2- || true)
for pair in "Niri:niri" "COSMIC:cosmic"; do
    label=${pair%%:*}; file=${pair##*:}
    found=""
    while IFS= read -r dir; do
        [[ -n $dir && -e $dir/$file.desktop ]] && { found=$dir; break; }
    done <<<"$SESSION_DIRS"
    if [[ -n $found ]]; then
        report "$label" OK "$file.desktop"
    else
        report "$label" FAIL "no $file.desktop in SDDM's SessionDir"
    fi
done

# NB: `systemctl is-enabled display-manager` prints "linked" and exits 1 on
# NixOS — the unit is a symlink into the store, not enabled through a wants
# directory. Whether it is *running* is the question that matters.
if systemctl is-active --quiet display-manager.service; then
    report "SDDM" OK "running"
elif systemctl cat display-manager.service >/dev/null 2>&1; then
    report "SDDM" PENDING_REBOOT "unit installed, not running"
else
    report "SDDM" FAIL "no display-manager unit"
fi

if [[ -f $SW/share/sddm/themes/ascii-city/Main.qml ]] \
   && grep -qs '^Current=ascii-city' /etc/sddm.conf.d/*.conf /etc/sddm.conf 2>/dev/null; then
    report "sddm-ascii-city" OK "theme installed + selected"
elif [[ -f $SW/share/sddm/themes/ascii-city/Main.qml ]]; then
    report "sddm-ascii-city" FAIL "installed but not selected in sddm.conf"
else
    report "sddm-ascii-city" FAIL "theme not installed"
fi

# ---- desktop bits ----
for pair in "Waybar:waybar" "Ghostty:ghostty" "Nautilus:nautilus" "Helium:helium" "nixos-update:nixos-update"; do
    label=${pair%%:*}; bin=${pair##*:}
    if [[ -x $SW/bin/$bin ]]; then
        report "$label" OK
    else
        report "$label" FAIL "$bin not on the system path"
    fi
done

WP=$TARGET_HOME/Pictures/Wallpaper/wallpaper.jpg
if [[ -e $WP ]]; then
    if [[ -L $WP && $(readlink -f "$WP") == /nix/store/* ]]; then
        report "Wallpaper" OK "deployed from the repo"
    else
        report "Wallpaper" OK "present (not the repo copy)"
    fi
else
    report "Wallpaper" PENDING_LOGIN "Home Manager has not run for $TARGET_USER yet"
fi

# ---- SIVA ----
MODEL_DIR=$(nix "${NIX_FLAGS[@]}" eval --raw ".#nixosConfigurations.$HOST.config.services.siva.llama.modelDir" 2>/dev/null || echo "")
MODEL=$(nix "${NIX_FLAGS[@]}" eval --raw ".#nixosConfigurations.$HOST.config.services.siva.llama.model" 2>/dev/null || echo "")
if [[ -n $MODEL_DIR && -r $MODEL_DIR/$MODEL ]]; then
    check_user_unit "llama-server" siva-llama-server.service
else
    report "llama-server" FAIL "model missing: $MODEL_DIR/$MODEL"
fi

check_user_unit "SIVA"            siva.service
check_user_unit "SIVA wake word"  siva-wake.service
check_user_unit "SIVA-Voicefetch" siva-voicefetch.service
check_user_unit "SIVA-Type"       siva-type.service

if [[ -s $SHARE/ggml-base.en.bin ]]; then
    report "SIVA models (STT/TTS)" OK
else
    report "SIVA models (STT/TTS)" FAIL "run siva-fetch-assets"
fi

# ~/.local/bin is first on the user's PATH (home.sessionPath), so a leftover
# hand-installed copy of the SIVA scripts would shadow the packaged ones — and
# those old copies still point at ~/.local/bin/siva-daemon rather than the
# store. Catch that rather than leaving a confusing half-upgraded stack.
stale=()
for b in siva siva-daemon siva-wake siva-enroll siva-type siva-type-daemon \
         siva-voicefetch siva-voicefetch-daemon siva-rvc siva-rvc-setup siva-llm; do
    [[ -e $TARGET_HOME/.local/bin/$b ]] && stale+=("$b")
done
if (( ${#stale[@]} )); then
    report "No shadowed SIVA copies" FAIL "${#stale[@]} stale files in ~/.local/bin"
    note "these shadow the packaged commands (~/.local/bin comes first on PATH):"
    note "  ${stale[*]}"
    note "remove them once you are happy with the packaged stack:"
    note "  cd ~/.local/bin && rm -f ${stale[*]}"
else
    report "No shadowed SIVA copies" OK
fi

#=============================================================================
# done
#=============================================================================

echo
if (( FAILED )); then
    printf '%s%sSome checks failed.%s See the notes above; most are fixable without a rebuild.\n' \
        "$C_RED" "$C_BOLD" "$C_RESET"
elif (( PENDING )); then
    printf '%s%sInstalled.%s Some things cannot be verified until you reboot and log in.\n' \
        "$C_GREEN" "$C_BOLD" "$C_RESET"
else
    printf '%s%sInstalled and verified.%s\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
fi

cat <<EOF

  Next:
    reboot                                  # to the ascii-city login screen
    <-/->                                   # pick Niri or COSMIC at the greeter

  Useful:
    systemctl --user status siva.service
    journalctl --user -u siva-llama-server.service -f
    sudo nixos-rebuild switch --flake $REPO#$HOST
    sudo nixos-rebuild switch --rollback    # undo a bad rebuild

EOF
(( FAILED )) && exit 1
exit 0
