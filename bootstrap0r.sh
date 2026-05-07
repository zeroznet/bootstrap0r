#!/usr/bin/env sh
# scripted/written by Robert Bopko (github.com/zeroznet) with Boba Bott (Claude Opus 4.7)

set -eu

# ---------- globals ----------
UMASK="${UMASK:-077}"
ROOTPW="${ROOTPW:-0}"
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

# ASCII spinner. Single-byte frames so cut -c indexes correctly regardless
# of locale; multi-byte (e.g. braille) frames fragment under GNU cut and
# render as replacement chars in some terminals (notably Windows Terminal + WSL).
spin_start() {
    if ! is_tty; then
        return 0
    fi
    (
        frames='|/-\'
        i=0
        while :; do
            frame=$(printf '%s' "$frames" | cut -c "$((i + 1))")
            printf '\b%s' "$frame" >&2
            i=$(((i + 1) % 4))
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

# ---------- apt helpers ----------
apt_update_once() {
    if [ "$_apt_updated" -eq 0 ]; then
        sudo apt update
        _apt_updated=1
    fi
}

# Filters out already-installed packages. Calls sudo apt install only on missing.
apt_install() {
    missing=""
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing="$missing $pkg"
        fi
    done
    if [ -z "$missing" ]; then
        printf 'all packages already installed: %s\n' "$*"
        return 0
    fi
    # shellcheck disable=SC2086
    sudo DEBIAN_FRONTEND=noninteractive apt install -y $missing
}

validate_umask() {
    case "$UMASK" in
        077|022) : ;;
        *) die "UMASK must be 077 or 022 (got: $UMASK)" ;;
    esac
}

validate_rootpw() {
    case "$ROOTPW" in
        0|1) : ;;
        *) die "ROOTPW must be 0 or 1 (got: $ROOTPW)" ;;
    esac
}

# When ROOTPW=1, refuse to install a Defaults rootpw drop-in if root has no
# usable password. Otherwise sudo would prompt for a password that doesn't
# exist and lock the user out. Skipped under --dry-run since it needs sudo.
check_root_password_or_die() {
    [ "$ROOTPW" -eq 1 ] || return 0
    [ "$DRY_RUN" -eq 0 ] || return 0
    status=$(sudo passwd -S root 2>/dev/null | awk '{print $2}')
    case "$status" in
        P)  : ;;
        L|LK) die "ROOTPW=1 but root account is locked. Run: sudo passwd root  (then re-run)" ;;
        NP) die "ROOTPW=1 but root has no password. Run: sudo passwd root  (then re-run)" ;;
        *)  die "ROOTPW=1 but could not determine root password status (passwd -S root said: ${status:-empty})" ;;
    esac
}

# ---------- cleanup ----------
cleanup_on_exit() {
    if [ -n "$_spinner_pid" ]; then
        kill "$_spinner_pid" 2>/dev/null || true
        _spinner_pid=""
    fi
    # Remove any temp .deb files we created. _tmp_debs is space-separated paths.
    if [ -n "$_tmp_debs" ]; then
        # shellcheck disable=SC2086
        rm -f $_tmp_debs
    fi
}

# ---------- preflight ----------
preflight() {
    if [ "$(id -u)" -eq 0 ] && [ "$ALLOW_ROOT" -eq 0 ]; then
        die "refusing to run as root; sudo is invoked per-command. Use --allow-root to override."
    fi

    need_cmd curl
    need_cmd git
    need_cmd sudo

    if [ "$DRY_RUN" -eq 0 ]; then
        sudo -v
    fi
}

# ---------- phases ----------
phase_umask_walk() {
    if [ "$DRY_RUN" -eq 1 ]; then
        # In --dry-run, run_step short-circuited and never calls us. Belt-and-suspenders:
        case "$UMASK" in
            077) count=$(find "$HOME" -perm /go=rwx 2>/dev/null | wc -l) ;;
            022) count=$(find "$HOME" -perm /go=w   2>/dev/null | wc -l) ;;
        esac
        # shellcheck disable=SC2016
        printf '[DRY] %s files/dirs in $HOME would be tightened\n' "$count"
        return 0
    fi

    case "$UMASK" in
        077) chmod -R go-rwx "$HOME" ;;
        022) chmod -R go-w   "$HOME" ;;
    esac
}
phase_sudoers() {
    target="/etc/sudoers.d/00-bootstrap0r-defaults"
    tmp="$(mktemp "${TMPDIR:-/tmp}/bootstrap0r-sudoers.XXXXXX")"
    cat >"$tmp" <<'EOF'
Defaults timestamp_timeout=60
EOF
    if [ "$ROOTPW" -eq 1 ]; then
        printf 'Defaults rootpw\n' >>"$tmp"
    fi

    if ! sudo visudo -cf "$tmp" >/dev/null; then
        rm -f "$tmp"
        die "sudoers drop-in failed visudo validation"
    fi

    if sudo test -f "$target" && sudo cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
        log "sudoers drop-in already in place, skipping"
        return 0
    fi

    sudo install -m 0440 -o root -g root "$tmp" "$target"
    rm -f "$tmp"
}
phase_nadrbomz() {
    curl -fsSL "$NADRBOMZ_URL" | sh

    # nadrbomz installs the zsh config but doesn't touch the login shell,
    # so flip /etc/passwd's shell field to zsh if it isn't already.
    zsh_path=$(command -v zsh) || die "zsh not found after phase_apt_base"
    current_shell=$(getent passwd "$USER" | cut -d: -f7)
    if [ "$current_shell" != "$zsh_path" ]; then
        sudo chsh -s "$zsh_path" "$USER"
    fi
}
phase_apt_base() {
    sudo dpkg --add-architecture i386
    apt_update_once
    sudo DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
    sudo DEBIAN_FRONTEND=noninteractive apt -y autoremove --purge
    sudo apt -y autoclean
    apt_install \
        curl ca-certificates gnupg \
        zsh \
        flatpak \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        vulkan-tools \
        gamemode \
        mangohud mangohud:i386
}
phase_chrome() {
    if dpkg -s google-chrome-stable >/dev/null 2>&1; then
        printf 'google-chrome-stable already installed, skipping\n'
        return 0
    fi
    deb="${TMPDIR:-/tmp}/bootstrap0r-google-chrome.deb"
    _tmp_debs="$_tmp_debs $deb"
    curl -fsSL -o "$deb" \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt install -y "$deb"
    rm -f "$deb"
}
phase_steam() {
    if dpkg -s steam-launcher >/dev/null 2>&1; then
        printf 'steam-launcher already installed, skipping\n'
        return 0
    fi
    deb="${TMPDIR:-/tmp}/bootstrap0r-steam.deb"
    _tmp_debs="$_tmp_debs $deb"
    curl -fsSL -o "$deb" \
        https://repo.steampowered.com/steam/archive/stable/steam_latest.deb
    sudo apt install -y "$deb"
    rm -f "$deb"
}
phase_flatpak_protonplus() {
    # User-scoped install: no sudo, no polkit (system scope fails on WSL
    # where polkit isn't wired up).
    flatpak --user remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    if ! flatpak info --user com.vysp3r.ProtonPlus >/dev/null 2>&1; then
        flatpak --user install -y --noninteractive flathub com.vysp3r.ProtonPlus
    fi

    flatpak override --user --filesystem="$HOME/.steam"             com.vysp3r.ProtonPlus
    flatpak override --user --filesystem="$HOME/.local/share/Steam" com.vysp3r.ProtonPlus
}
phase_finalize() {
    # Reserved hook for post-install tweaks (default browser, MIME, etc.).
    # No-op today; print_summary is called from main after this.
    return 0
}

print_summary() {
    cat >&2 <<EOF

==> Done.
Log: $LOG_FILE

Next steps:
  1. Launch Steam, login
  2. Open ProtonPlus (com.vysp3r.ProtonPlus), install latest GE-Proton
  3. Steam launch options (e.g. for Cyberpunk 2077):
     gamemoderun mangohud PROTON_ENABLE_WAYLAND=1 PROTON_ENABLE_HDR=1 \\
       PROTON_FSR4_UPGRADE=1 PROTON_FSR4_INDICATOR=1 %command% \\
       --launcher-skip --intro-skip
EOF
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
  ROOTPW         0 (default) or 1. If 1, sudoers drop-in includes
                 'Defaults rootpw' so sudo prompts for root's password.
                 Refused at preflight if root is locked or has no password.
                 Pointless on WSL: 'wsl -u root' bypasses it from Windows.

Phases (run in order):
  1. Clamp permissions on \$HOME to UMASK
  2. Install sudoers defaults (/etc/sudoers.d/00-bootstrap0r-defaults)
  3. Add i386 multiarch, apt update + full-upgrade + autoremove --purge +
     autoclean, then install base/gaming packages (incl. zsh)
  4. Bootstrap shell via nadrbomz (curl-pipe install)
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
    validate_umask
    validate_rootpw
    umask "$UMASK"
    : > "$LOG_FILE"
    trap cleanup_on_exit EXIT HUP INT TERM

    preflight
    check_root_password_or_die

    log "==> bootstrap0r — Linux env bootstrap (UMASK=$UMASK)"

    run_step "Clamping permissions on \$HOME ($UMASK)" phase_umask_walk
    run_step "Installing sudoers defaults"               phase_sudoers
    run_step "Adding i386 multiarch and base packages"   phase_apt_base
    run_step "Bootstrapping shell (nadrbomz)"            phase_nadrbomz
    run_step "Installing Google Chrome"                  phase_chrome
    run_step "Installing Steam"                          phase_steam
    run_step "Setting up Flathub + ProtonPlus"           phase_flatpak_protonplus
    run_step "Final touches"                             phase_finalize

    print_summary
}

[ "${BOOTSTRAP0R_NO_MAIN:-0}" = "1" ] || main "$@"
