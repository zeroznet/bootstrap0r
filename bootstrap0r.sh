#!/usr/bin/env sh
# scripted/written by Robert Bopko (github.com/zeroznet) with Boba Bott (Claude Opus 4.7)

set -eu

# ---------- globals ----------
UMASK="${UMASK:-077}"
LOG_FILE="${TMPDIR:-/tmp}/bootstrap0r-$(date +%Y%m%d%H%M%S).log"
NADRBOMZ_URL="https://raw.githubusercontent.com/zeroznet/nadrbomz/main/nadrbomz.sh"
DRY_RUN=0
ALLOW_ROOT=0
TOTAL_STEPS=8
CURRENT_STEP=0
_apt_updated=0
_spinner_pid=""
_tmp_debs=""

# ---------- basic helpers ----------
log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

need_cmd() {
    has_cmd "$1" || die "Missing required command: $1"
}

# ---------- UI helpers ----------
is_tty() {
    [ -t 1 ] && [ -t 2 ]
}

step_label() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf '[%d/%d] %s... ' "$CURRENT_STEP" "$TOTAL_STEPS" "$1" >&2
}

# Braille spinner. cut -c on Debian 13 coreutils counts characters under a
# UTF-8 locale, which matches the host. Switch to ASCII frames if a target
# system shows garbled glyphs.
spin_start() {
    if ! is_tty; then
        return 0
    fi
    (
        frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        i=0
        # shellcheck disable=SC2034
        while :; do
            frame=$(printf '%s' "$frames" | cut -c "$((i + 1))")
            printf '\b%s' "$frame" >&2
            i=$(((i + 1) % 10))
            sleep 0.1
        done
    ) &
    _spinner_pid=$!
    # Print a placeholder char so the first \b has something to overwrite.
    printf ' ' >&2
}

spin_stop() {
    if [ -n "$_spinner_pid" ]; then
        kill "$_spinner_pid" 2>/dev/null || true
        wait "$_spinner_pid" 2>/dev/null || true
        _spinner_pid=""
        # Erase the spinner char.
        printf '\b \b' >&2
    fi
}

run_step() {
    label="$1"
    shift
    step_label "$label"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[DRY] %s\n' "$*" >&2
        return 0
    fi

    spin_start
    if "$@" >>"$LOG_FILE" 2>&1; then
        spin_stop
        printf 'OK\n' >&2
    else
        rc=$?
        spin_stop
        printf 'FAIL\n' >&2
        printf 'Log: %s\n' "$LOG_FILE" >&2
        printf '%s\n' '--- last 20 lines of log ---' >&2
        tail -n 20 "$LOG_FILE" >&2 || true
        exit "$rc"
    fi
}

# ---------- usage / args ----------
usage() {
    cat <<EOF
bootstrap0r — personal Linux env bootstrap (Debian 13 / Ubuntu)

Usage:
  bootstrap0r.sh [--help] [--dry-run] [--allow-root]

Flags:
  --help         Show this help and exit.
  --dry-run      Print intended actions, modify nothing on disk.
  --allow-root   Permit running as root (default: refused).

Env:
  UMASK          077 (default) or 022. Other values rejected.

Phases (run in order):
  1. Clamp permissions on \$HOME to UMASK
  2. Install sudoers defaults (/etc/sudoers.d/00-bootstrap0r-defaults)
  3. Bootstrap shell via nadrbomz (curl-pipe install)
  4. Add i386 multiarch + base/gaming packages
  5. Install Google Chrome (.deb)
  6. Install Steam (.deb)
  7. Set up Flathub + ProtonPlus
  8. Final touches + summary

Repo: https://github.com/zeroznet/bootstrap0r
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)        usage; exit 0 ;;
            --dry-run)     DRY_RUN=1 ;;
            --allow-root)  ALLOW_ROOT=1 ;;
            -*)            die "Unknown flag: $1" ;;
            *)             die "Unexpected positional argument: $1" ;;
        esac
        shift
    done
}

# ---------- main ----------
main() {
    parse_args "$@"
    log "bootstrap0r: parsed args (DRY_RUN=$DRY_RUN ALLOW_ROOT=$ALLOW_ROOT UMASK=$UMASK)"
}

main "$@"
