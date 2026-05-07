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
