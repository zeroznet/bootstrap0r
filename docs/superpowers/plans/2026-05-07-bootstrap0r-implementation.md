# bootstrap0r Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `bootstrap0r.sh`, a single-file POSIX `sh` bootstrap script that takes a fresh Debian 13 / Ubuntu install and lands Robert's full working environment (umask-clamped `$HOME`, sudoers defaults, dotfiles via `nadrbomz`, base + gaming packages, Chrome, Steam, Flathub + ProtonPlus). Ship it as a public GitHub repo `zeroznet/bootstrap0r` with `nadrbomz`-style scaffolding (README, LICENSE, .gitignore, CLAUDE.md).

**Architecture:** Single-file linear bash-portable POSIX `sh` script. Helpers at top, phase functions below, `main()` calls phases through a `run_step` wrapper that handles spinner + step counter + log redirection. Idempotent re-runs. Curl-pipe one-liner install, mirroring the `nadrbomz` distribution model.

**Tech Stack:** POSIX `sh` (Debian/Ubuntu `/bin/sh` = `dash`-compatible), `shellcheck` for lint, `git` + `gh` for repo distribution, `apt`, `flatpak`, `dpkg`, `sudo`, `curl`. No test framework — verification is `shellcheck` + `sh -n` syntax check + `./bootstrap0r.sh --dry-run` end-to-end.

**Source of truth:** `/home/zero/dev/bootstrap0r/docs/superpowers/specs/2026-05-07-bootstrap0r-design.md`

---

## Verification model

Shell scripts that mutate system state don't fit classical xUnit TDD. The verification ladder for this project:

1. **Static** — `shellcheck bootstrap0r.sh` (zero warnings) + `sh -n bootstrap0r.sh` (syntax).
2. **Smoke** — `./bootstrap0r.sh --help` exits 0 and prints usage.
3. **Dry-run** — `./bootstrap0r.sh --dry-run` runs end-to-end without modifying the system; every phase prints intended actions; exit 0.
4. **Real** — running on a fresh Debian 13 / Ubuntu VM (out of scope for this plan; manual after merge).

Every code-adding task ends with `shellcheck` + a targeted dry-run smoke. Final task does the full end-to-end dry-run.

`shellcheck` is not installed yet — Task 1 installs it.

## File structure

Single-file script. All scaffolding plus the script live at the repo root:

```
/home/zero/dev/bootstrap0r/
├── bootstrap0r.sh
├── README.md
├── LICENSE
├── .gitignore
├── CLAUDE.md                                  (already exists)
└── docs/superpowers/
    ├── specs/2026-05-07-bootstrap0r-design.md (already exists)
    └── plans/2026-05-07-bootstrap0r-implementation.md  (this file)
```

The script is built top-to-bottom in this internal order:

```
1.  shebang + attribution header
2.  set -eu
3.  globals (UMASK, LOG_FILE, NADRBOMZ_URL, DRY_RUN, ALLOW_ROOT, TOTAL_STEPS, CURRENT_STEP, _apt_updated, _spinner_pid, _tmp_debs)
4.  log / warn / die / has_cmd / need_cmd
5.  is_tty / step_label / spin_start / spin_stop / run_step
6.  validate_umask / apt_update_once / apt_install
7.  cleanup_on_exit trap
8.  usage / parse_args
9.  preflight
10. phase_umask_walk
11. phase_sudoers
12. phase_nadrbomz
13. phase_apt_base
14. phase_chrome
15. phase_steam
16. phase_flatpak_protonplus
17. phase_finalize
18. print_summary
19. main
20. main "$@"
```

Tasks add code in roughly this order, committing after each working chunk.

---

### Task 1: Bootstrap dev tooling and repo scaffold

**Files:**
- Install: `shellcheck` (system-wide, dev dep)
- Create: `/home/zero/dev/bootstrap0r/.gitignore`
- Create: `/home/zero/dev/bootstrap0r/LICENSE`
- Create: `/home/zero/dev/bootstrap0r/README.md`
- Create: `/home/zero/dev/bootstrap0r/bootstrap0r.sh` (stub)
- Init: git repo at `/home/zero/dev/bootstrap0r/`

- [ ] **Step 1: Install shellcheck (dev dependency, not a bootstrap0r runtime dep)**

```sh
sudo apt install -y shellcheck
shellcheck --version | head -2
```

Expected: `version: 0.x.x` printed.

- [ ] **Step 2: Create `.gitignore` (mirrored from nadrbomz)**

Content:
```
.claude/settings.local.json
.env
.env.*
*.swp
.DS_Store
HANDOFF.md
HANDOFF.md.bak
```

- [ ] **Step 3: Create `LICENSE` (BSD-2-Clause, copy nadrbomz template, adjust)**

```sh
cp /home/zero/dev/nadrbomz/LICENSE /home/zero/dev/bootstrap0r/LICENSE
```

Then open and adjust the year to `2026` and any project-name references. Verify the copyright line reads:
```
Copyright (c) 2026, Robert Bopko <github.com/zeroznet>
```
(Match the exact format used in `nadrbomz/LICENSE`; the source-of-truth is that file's header.)

- [ ] **Step 4: Create `README.md` (full content from spec)**

Use the README content from `docs/superpowers/specs/2026-05-07-bootstrap0r-design.md` (the "README content" section — it is the canonical text, copy verbatim). The first heading must be `# bootstrap0r`.

- [ ] **Step 5: Create `bootstrap0r.sh` stub**

Content:
```sh
#!/usr/bin/env sh
# scripted/written by Robert Bopko (github.com/zeroznet) with Boba Bott (Claude Opus 4.7)

set -eu

main() {
    printf 'bootstrap0r: stub\n'
}

main "$@"
```

Then `chmod +x bootstrap0r.sh`.

- [ ] **Step 6: Verify stub runs and lints clean**

```sh
cd /home/zero/dev/bootstrap0r
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
./bootstrap0r.sh
```

Expected: shellcheck silent, syntax check silent, output `bootstrap0r: stub`.

- [ ] **Step 7: git init and initial commit**

```sh
cd /home/zero/dev/bootstrap0r
git init -b main
git add CLAUDE.md bootstrap0r.sh README.md LICENSE .gitignore docs/
git commit -m "init bootstrap0r: scaffold + stub script"
```

---

### Task 2: Globals, basic helpers, usage/parse_args

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

This task replaces the stub `main` with the foundation: globals, `log/warn/die/has_cmd/need_cmd`, `usage`, and `parse_args`. No phase logic yet — `main` just parses args and prints what it would do.

- [ ] **Step 1: Replace bootstrap0r.sh content with foundation**

Full file content:
```sh
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
```

- [ ] **Step 2: Lint and syntax-check**

```sh
cd /home/zero/dev/bootstrap0r
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

Expected: both silent.

- [ ] **Step 3: Smoke test the args**

```sh
./bootstrap0r.sh --help
./bootstrap0r.sh
./bootstrap0r.sh --dry-run
UMASK=022 ./bootstrap0r.sh --dry-run
./bootstrap0r.sh --allow-root --dry-run
./bootstrap0r.sh --bogus 2>&1 || true
```

Expected outputs:
- `--help` → usage block, exit 0.
- no flags → `bootstrap0r: parsed args (DRY_RUN=0 ALLOW_ROOT=0 UMASK=077)`.
- `--dry-run` → same, `DRY_RUN=1`.
- `UMASK=022 --dry-run` → `UMASK=022`.
- `--allow-root --dry-run` → `ALLOW_ROOT=1`.
- `--bogus` → `ERROR: Unknown flag: --bogus`, exit 1.

- [ ] **Step 4: Commit**

```sh
git add bootstrap0r.sh
git commit -m "add globals, basic helpers, usage and arg parsing"
```

---

### Task 3: UI helpers (is_tty, step_label, spin, run_step)

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

Add UI helpers. Do not call them from `main` yet — Task 4 wires the orchestration.

- [ ] **Step 1: Insert UI helpers after the `need_cmd` function**

Insert after `need_cmd`, before the `usage()` function:

```sh
# ---------- UI helpers ----------
is_tty() {
    [ -t 1 ] && [ -t 2 ]
}

step_label() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf '[%d/%d] %s... ' "$CURRENT_STEP" "$TOTAL_STEPS" "$1" >&2
}

# Background spinner — overwrites the trailing chars of the current line.
# No-op when stdout/stderr are not a TTY.
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
        printf '--- last 20 lines of log ---\n' >&2
        tail -n 20 "$LOG_FILE" >&2 || true
        exit "$rc"
    fi
}
```

Note on POSIX cut + UTF-8 braille chars: `cut -c` operates on **bytes** in many implementations. On Debian/Ubuntu `cut` from coreutils, `-c` actually does count characters when `LC_ALL` is a UTF-8 locale, but to keep this portable, fall back to ASCII spinner if UTF-8 handling is unreliable. Replace `frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'` with `frames='|/-\|/-\|/'` (10 chars) if you observe garbled output during smoke testing in step 3. Document the choice in a comment above `spin_start`.

- [ ] **Step 2: Lint**

```sh
cd /home/zero/dev/bootstrap0r
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

Expected: shellcheck silent (the disable comment handles `frames` being read in arithmetic). If shellcheck complains about anything new, fix inline before continuing.

- [ ] **Step 3: Wire a temporary smoke that exercises run_step**

Temporarily replace `main()` with:

```sh
main() {
    parse_args "$@"
    LOG_FILE="${TMPDIR:-/tmp}/bootstrap0r-smoke.log"
    : > "$LOG_FILE"
    TOTAL_STEPS=2
    run_step "Sleeping briefly" sh -c 'sleep 1'
    run_step "Failing on purpose" sh -c 'echo boom; exit 7' || true
    run_step "Should not run" true
}
```

Run:
```sh
./bootstrap0r.sh
```

Expected (exact spinner glyphs may differ):
- TTY run: `[1/2] Sleeping briefly... ⠹ OK`, then `[2/2] Failing on purpose... FAIL`, log path printed, last 20 lines printed (showing "boom"), exit 7.
- The third `run_step` should not execute because the second one exits.

- [ ] **Step 4: Verify dry-run mode**

Edit the temporary `main` again or invoke:

```sh
./bootstrap0r.sh --dry-run
```

Expected: `[1/2] Sleeping briefly... [DRY] sh -c sleep 1`, then `[2/2] Failing on purpose... [DRY] sh -c echo boom; exit 7`. No log file written, no failures.

- [ ] **Step 5: Restore main() to the Task 2 version (no run_step calls)**

Revert `main()` back to:
```sh
main() {
    parse_args "$@"
    log "bootstrap0r: parsed args (DRY_RUN=$DRY_RUN ALLOW_ROOT=$ALLOW_ROOT UMASK=$UMASK)"
}
```

The smoke `run_step` calls were temporary — the real wiring lives in Task 4.

- [ ] **Step 6: Commit**

```sh
shellcheck bootstrap0r.sh
git add bootstrap0r.sh
git commit -m "add TTY-aware UI helpers (step_label, spinner, run_step)"
```

---

### Task 4: apt helpers + validate_umask + cleanup trap + preflight + wire main

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

This task wires the orchestration. Phase functions are added as no-ops (`return 0`) so `main` can call all eight `run_step` lines and produce the full sequence, both with and without `--dry-run`.

- [ ] **Step 1: Add apt helpers and validate_umask after the UI helpers**

Insert this block after the `run_step` function:

```sh
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
```

- [ ] **Step 2: Add cleanup_on_exit and preflight**

Insert after `validate_umask`:

```sh
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
```

- [ ] **Step 3: Add empty phase functions**

Insert after `preflight`:

```sh
# ---------- phases ----------
phase_umask_walk()         { return 0; }
phase_sudoers()            { return 0; }
phase_nadrbomz()           { return 0; }
phase_apt_base()           { return 0; }
phase_chrome()             { return 0; }
phase_steam()              { return 0; }
phase_flatpak_protonplus() { return 0; }
phase_finalize()           { return 0; }
```

- [ ] **Step 4: Add print_summary**

Insert after `phase_finalize`:

```sh
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
```

- [ ] **Step 5: Replace `main()` with the orchestrating version**

```sh
main() {
    parse_args "$@"
    validate_umask
    : > "$LOG_FILE"
    trap cleanup_on_exit EXIT HUP INT TERM

    preflight
    umask "$UMASK"

    log "==> bootstrap0r — Linux env bootstrap (UMASK=$UMASK)"

    run_step "Clamping permissions on \$HOME ($UMASK)" phase_umask_walk
    run_step "Installing sudoers defaults"               phase_sudoers
    run_step "Bootstrapping shell (nadrbomz)"            phase_nadrbomz
    run_step "Adding i386 multiarch and base packages"   phase_apt_base
    run_step "Installing Google Chrome"                  phase_chrome
    run_step "Installing Steam"                          phase_steam
    run_step "Setting up Flathub + ProtonPlus"           phase_flatpak_protonplus
    run_step "Final touches"                             phase_finalize

    print_summary
}
```

- [ ] **Step 6: Lint and syntax-check**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

Expected: silent.

- [ ] **Step 7: Full --dry-run end-to-end smoke (phases are no-ops)**

```sh
./bootstrap0r.sh --dry-run
```

Expected: header line, eight `[N/8] <label>... [DRY] phase_xxx` lines, then `==> Done.` summary block. Exit 0. The `_apt_updated` etc. globals stay zero.

```sh
UMASK=022 ./bootstrap0r.sh --dry-run
UMASK=999 ./bootstrap0r.sh --dry-run 2>&1 | head -1
```

Expected: first runs through with UMASK=022, second prints `ERROR: UMASK must be 077 or 022 (got: 999)` and exits 1.

- [ ] **Step 8: Commit**

```sh
git add bootstrap0r.sh
git commit -m "wire orchestrating main with run_step + empty phase stubs"
```

---

### Task 5: phase_umask_walk

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

Implements the chmod walk on `$HOME`.

- [ ] **Step 1: Replace the `phase_umask_walk` no-op with the real implementation**

```sh
phase_umask_walk() {
    if [ "$DRY_RUN" -eq 1 ]; then
        # In --dry-run, run_step short-circuited and never calls us. Belt-and-suspenders:
        case "$UMASK" in
            077) count=$(find "$HOME" -perm /go=rwx 2>/dev/null | wc -l) ;;
            022) count=$(find "$HOME" -perm /go=w   2>/dev/null | wc -l) ;;
        esac
        printf '[DRY] %s files/dirs in $HOME would be tightened\n' "$count"
        return 0
    fi

    case "$UMASK" in
        077) chmod -R go-rwx "$HOME" ;;
        022) chmod -R go-w   "$HOME" ;;
    esac
}
```

Note: `run_step` already short-circuits on `DRY_RUN=1` and prints `[DRY] phase_umask_walk` instead of calling the function. The dry-run branch above is defensive and only runs if `phase_umask_walk` is ever called directly (e.g., manually for testing the count). Keep it.

- [ ] **Step 2: Lint and syntax check**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Manual count verification (read-only)**

```sh
find "$HOME" -perm /go=rwx 2>/dev/null | wc -l
find "$HOME" -perm /go=w   2>/dev/null | wc -l
```

Note these counts. They are the populations the umask walk would touch.

- [ ] **Step 4: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
UMASK=022 ./bootstrap0r.sh --dry-run
```

Expected: `[1/8] Clamping permissions on $HOME (077)... [DRY] phase_umask_walk` (the function itself is not called by `run_step` in dry-run mode — the bracket-DRY line comes from `run_step`).

- [ ] **Step 5: DO NOT run without --dry-run yet**

Real execution would chmod the user's $HOME. Defer to the final end-to-end task. This step is a reminder, not an action.

- [ ] **Step 6: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_umask_walk (077: go-rwx, 022: go-w)"
```

---

### Task 6: phase_sudoers

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

- [ ] **Step 1: Replace `phase_sudoers` no-op with the real implementation**

```sh
phase_sudoers() {
    target="/etc/sudoers.d/00-bootstrap0r-defaults"
    tmp="$(mktemp "${TMPDIR:-/tmp}/bootstrap0r-sudoers.XXXXXX")"
    cat >"$tmp" <<'EOF'
Defaults timestamp_timeout=60,!tty_tickets
Defaults rootpw
EOF

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
```

- [ ] **Step 2: Lint**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
```

Expected: `[2/8] Installing sudoers defaults... [DRY] phase_sudoers`. No actual sudo invocation, no temp file lingers.

```sh
ls /tmp/bootstrap0r-sudoers.* 2>/dev/null || echo "no temp files (expected)"
```

- [ ] **Step 4: Manual real-run smoke (single-step)**

This step runs only `phase_sudoers` for real, since the rest of the script is still mostly stubbed. The user is on the same machine the spec was designed for; this is safe and matches the desired end state.

```sh
sh -c '
. /home/zero/dev/bootstrap0r/bootstrap0r.sh --help >/dev/null  # noop, validates parse_args
'
# Direct invocation:
sudo -v
( cd /home/zero/dev/bootstrap0r &&
  sh -c '. ./bootstrap0r.sh; phase_sudoers' 2>&1 ) || true
```

Note: the script ends with `main "$@"`, so sourcing it will run `main` with no args, which invokes preflight+full pipeline. To avoid that during this single-phase test, instead **temporarily** add `BOOTSTRAP0R_NO_MAIN=1` guard around `main "$@"`:

Find the last line `main "$@"` and replace with:
```sh
[ "${BOOTSTRAP0R_NO_MAIN:-0}" = "1" ] || main "$@"
```

Then:
```sh
cd /home/zero/dev/bootstrap0r
BOOTSTRAP0R_NO_MAIN=1 . ./bootstrap0r.sh
phase_sudoers
sudo cat /etc/sudoers.d/00-bootstrap0r-defaults
sudo visudo -c
```

Expected:
- Drop-in created (or skip-message if running second time).
- Cat shows the two `Defaults` lines.
- `visudo -c` reports `parsed OK`.

Re-run `phase_sudoers` once more in the same shell:
Expected: `sudoers drop-in already in place, skipping`.

The `BOOTSTRAP0R_NO_MAIN` guard becomes a permanent feature of the script — it costs one line and enables future per-phase debugging. Keep it.

- [ ] **Step 5: Verify dry-run still works after the guard change**

```sh
./bootstrap0r.sh --dry-run
```

Expected: full eight-step dry-run printout, no behavior change.

- [ ] **Step 6: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_sudoers and add BOOTSTRAP0R_NO_MAIN guard"
```

---

### Task 7: phase_nadrbomz

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

- [ ] **Step 1: Replace `phase_nadrbomz` no-op**

```sh
phase_nadrbomz() {
    curl -fsSL "$NADRBOMZ_URL" | sh
}
```

That's the whole phase. `nadrbomz` handles its own idempotency, dotfile backups, and OMZ skip-if-installed logic.

- [ ] **Step 2: Lint**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
```

Expected line: `[3/8] Bootstrapping shell (nadrbomz)... [DRY] phase_nadrbomz`. No network call.

- [ ] **Step 4: Verify the URL responds (read-only network check)**

```sh
curl -fsSI "$NADRBOMZ_URL" | head -1 || echo "URL unreachable"
```

Expected: `HTTP/2 200`. If 404, the nadrbomz repo URL or branch name has changed — fix `NADRBOMZ_URL` constant in the script.

The URL constant lives in the globals block of `bootstrap0r.sh`. Read with:
```sh
grep ^NADRBOMZ_URL /home/zero/dev/bootstrap0r/bootstrap0r.sh
```

- [ ] **Step 5: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_nadrbomz (curl-pipe install)"
```

---

### Task 8: phase_apt_base

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

- [ ] **Step 1: Replace `phase_apt_base` no-op**

```sh
phase_apt_base() {
    sudo dpkg --add-architecture i386
    apt_update_once
    apt_install \
        curl ca-certificates gnupg \
        flatpak \
        mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        vulkan-tools \
        gamemode \
        mangohud
}
```

- [ ] **Step 2: Lint**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
```

Expected: `[4/8] Adding i386 multiarch and base packages... [DRY] phase_apt_base`.

- [ ] **Step 4: Sanity check - i386 already enabled?**

```sh
dpkg --print-foreign-architectures
```

If `i386` already listed, the `dpkg --add-architecture i386` invocation in this phase is a no-op (idempotent by design).

- [ ] **Step 5: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_apt_base (i386 + base + gaming packages)"
```

---

### Task 9: phase_chrome

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

- [ ] **Step 1: Replace `phase_chrome` no-op**

```sh
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
```

The `_tmp_debs` accumulator is so `cleanup_on_exit` can purge any orphaned `.deb` files if the install fails.

- [ ] **Step 2: Lint**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
```

Expected: `[5/8] Installing Google Chrome... [DRY] phase_chrome`.

- [ ] **Step 4: Verify Google's URL responds**

```sh
curl -fsSI https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb | head -1
```

Expected: `HTTP/2 200`.

- [ ] **Step 5: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_chrome (Google official .deb)"
```

---

### Task 10: phase_steam

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

- [ ] **Step 1: Replace `phase_steam` no-op**

```sh
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
```

- [ ] **Step 2: Lint**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
```

Expected: `[6/8] Installing Steam... [DRY] phase_steam`.

- [ ] **Step 4: Verify Valve's URL responds**

```sh
curl -fsSI https://repo.steampowered.com/steam/archive/stable/steam_latest.deb | head -1
```

Expected: `HTTP/2 200`.

- [ ] **Step 5: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_steam (Valve official .deb)"
```

---

### Task 11: phase_flatpak_protonplus

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

- [ ] **Step 1: Replace `phase_flatpak_protonplus` no-op**

```sh
phase_flatpak_protonplus() {
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    if ! flatpak info com.vysp3r.ProtonPlus >/dev/null 2>&1; then
        flatpak install -y --noninteractive flathub com.vysp3r.ProtonPlus
    fi

    flatpak override --user --filesystem="$HOME/.steam"             com.vysp3r.ProtonPlus
    flatpak override --user --filesystem="$HOME/.local/share/Steam" com.vysp3r.ProtonPlus
}
```

- [ ] **Step 2: Lint**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

- [ ] **Step 3: Dry-run smoke**

```sh
./bootstrap0r.sh --dry-run
```

Expected: `[7/8] Setting up Flathub + ProtonPlus... [DRY] phase_flatpak_protonplus`.

- [ ] **Step 4: Verify Flathub URL responds**

```sh
curl -fsSI https://dl.flathub.org/repo/flathub.flatpakrepo | head -1
```

Expected: `HTTP/2 200`.

- [ ] **Step 5: Commit**

```sh
git add bootstrap0r.sh
git commit -m "implement phase_flatpak_protonplus (Flathub + ProtonPlus + Steam paths)"
```

---

### Task 12: phase_finalize and final lint pass

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/bootstrap0r.sh`

`phase_finalize` is intentionally a no-op reserved hook, but it must not be `return 0` empty (shellcheck dislikes truly-empty function bodies). Keep it as `return 0` with a comment.

- [ ] **Step 1: Replace `phase_finalize` no-op with documented hook**

```sh
phase_finalize() {
    # Reserved hook for post-install tweaks (default browser, MIME, etc.).
    # No-op today; print_summary is called from main after this.
    return 0
}
```

- [ ] **Step 2: Final shellcheck + syntax**

```sh
shellcheck bootstrap0r.sh
sh -n bootstrap0r.sh
```

Expected: silent.

- [ ] **Step 3: Full --dry-run end-to-end on this machine**

```sh
./bootstrap0r.sh --dry-run
```

Expected output (line for line):
```
==> bootstrap0r — Linux env bootstrap (UMASK=077)
[1/8] Clamping permissions on $HOME (077)... [DRY] phase_umask_walk
[2/8] Installing sudoers defaults... [DRY] phase_sudoers
[3/8] Bootstrapping shell (nadrbomz)... [DRY] phase_nadrbomz
[4/8] Adding i386 multiarch and base packages... [DRY] phase_apt_base
[5/8] Installing Google Chrome... [DRY] phase_chrome
[6/8] Installing Steam... [DRY] phase_steam
[7/8] Setting up Flathub + ProtonPlus... [DRY] phase_flatpak_protonplus
[8/8] Final touches... [DRY] phase_finalize

==> Done.
Log: /tmp/bootstrap0r-YYYYMMDDHHMMSS.log

Next steps:
  1. Launch Steam, login
  2. Open ProtonPlus (com.vysp3r.ProtonPlus), install latest GE-Proton
  3. Steam launch options (e.g. for Cyberpunk 2077):
     gamemoderun mangohud PROTON_ENABLE_WAYLAND=1 PROTON_ENABLE_HDR=1 \
       PROTON_FSR4_UPGRADE=1 PROTON_FSR4_INDICATOR=1 %command% \
       --launcher-skip --intro-skip
```

Exit code 0.

- [ ] **Step 4: Verify the log file is created and empty in dry-run**

```sh
ls -l /tmp/bootstrap0r-*.log | tail -1
wc -l /tmp/bootstrap0r-*.log | tail -1
```

The log is `: > "$LOG_FILE"` truncated at start of `main`, and `run_step` doesn't write to it in dry-run mode. Expect `0 lines`.

- [ ] **Step 5: Commit**

```sh
git add bootstrap0r.sh
git commit -m "finalize bootstrap0r.sh: phase_finalize hook + full dry-run pass"
```

---

### Task 13: README polish + final repo audit

**Files:**
- Verify: `/home/zero/dev/bootstrap0r/README.md`
- Verify: `/home/zero/dev/bootstrap0r/LICENSE`
- Verify: `/home/zero/dev/bootstrap0r/.gitignore`
- Verify: `/home/zero/dev/bootstrap0r/CLAUDE.md`

- [ ] **Step 1: Read each scaffold file and check against the spec**

```sh
cd /home/zero/dev/bootstrap0r
ls -la
head README.md
head LICENSE
cat .gitignore
```

Cross-check that the README has the canonical content from the spec (one-liner install URLs, flags, env, license note). Confirm LICENSE has BSD-2-Clause + 2026 copyright. Confirm .gitignore matches nadrbomz exactly.

- [ ] **Step 2: Confirm CLAUDE.md is unchanged from /init**

```sh
git log --oneline -- CLAUDE.md
```

Expected: only the initial scaffold commit. The implementation should not have modified CLAUDE.md.

- [ ] **Step 3: git status clean check**

```sh
git status
```

Expected: clean working tree, all commits accounted for.

- [ ] **Step 4: Inventory commits**

```sh
git log --oneline
```

Expected commit list (titles approximate, the order matters):
```
init bootstrap0r: scaffold + stub script
add globals, basic helpers, usage and arg parsing
add TTY-aware UI helpers (step_label, spinner, run_step)
wire orchestrating main with run_step + empty phase stubs
implement phase_umask_walk (077: go-rwx, 022: go-w)
implement phase_sudoers and add BOOTSTRAP0R_NO_MAIN guard
implement phase_nadrbomz (curl-pipe install)
implement phase_apt_base (i386 + base + gaming packages)
implement phase_chrome (Google official .deb)
implement phase_steam (Valve official .deb)
implement phase_flatpak_protonplus (Flathub + ProtonPlus + Steam paths)
finalize bootstrap0r.sh: phase_finalize hook + full dry-run pass
```

If any commits are missing or out of order, stop and reconcile.

- [ ] **Step 5: No commit needed (this is an audit task)**

If README/LICENSE/.gitignore had drift, fix them and commit before proceeding to Task 14.

---

### Task 14: Push to GitHub via `gh`

**Files:**
- Remote: `https://github.com/zeroznet/bootstrap0r`

This is the visible-to-others step. Verify the user wants to push before doing so.

- [ ] **Step 1: Confirm `gh` is authenticated**

```sh
gh auth status
```

Expected: shows `zeroznet` (or robert@bopko.com) authenticated. If not, instruct the user to run `gh auth login` themselves and pause.

- [ ] **Step 2: Confirm with user before creating the public repo**

State plainly: "About to run `gh repo create zeroznet/bootstrap0r --public --push`. This creates a public repo on github.com/zeroznet/bootstrap0r and pushes the current `main` branch. Proceed?"

Wait for explicit go-ahead. Do not auto-run; this is a public, hard-to-reverse action.

- [ ] **Step 3: Create the repo and push**

```sh
cd /home/zero/dev/bootstrap0r
gh repo create zeroznet/bootstrap0r \
  --public \
  --description "Personal Linux bootstrap for Debian 13: umask clamp, dotfiles via nadrbomz, gaming + dev installs." \
  --source=. \
  --remote=origin \
  --push
```

Expected output: `https://github.com/zeroznet/bootstrap0r` URL printed.

- [ ] **Step 4: Verify the repo is live**

```sh
gh repo view zeroznet/bootstrap0r --json url,description,visibility,defaultBranchRef
```

Expected:
- `visibility`: `PUBLIC`
- `description`: matches the `--description` value above
- `defaultBranchRef.name`: `main`

- [ ] **Step 5: Verify the curl-pipe one-liner resolves**

```sh
curl -fsSI https://raw.githubusercontent.com/zeroznet/bootstrap0r/main/bootstrap0r.sh | head -1
```

Expected: `HTTP/2 200`.

- [ ] **Step 6: No commit (the push WAS the commit handover)**

The repo and code are now public.

---

### Task 15: Documentation update — CLAUDE.md status section

**Files:**
- Modify: `/home/zero/dev/bootstrap0r/CLAUDE.md`

The project-level `CLAUDE.md` says "Greenfield. No code yet." That is no longer true.

- [ ] **Step 1: Update the Status section in CLAUDE.md**

Find the section starting with `## Status`. Replace its body with:

```markdown
## Status

`bootstrap0r.sh` is the entry point. Run it directly or via the curl-pipe one-liner from the README. Phases run in fixed order:

1. `phase_umask_walk`        — chmod `$HOME` to match `$UMASK` (077 default, 022 alt)
2. `phase_sudoers`           — install `/etc/sudoers.d/00-bootstrap0r-defaults`
3. `phase_nadrbomz`          — curl-pipe `https://github.com/zeroznet/nadrbomz`
4. `phase_apt_base`          — i386 multiarch + base/gaming packages
5. `phase_chrome`            — Google official `.deb`
6. `phase_steam`             — Valve official `.deb`
7. `phase_flatpak_protonplus` — Flathub + `com.vysp3r.ProtonPlus` + Steam path overrides
8. `phase_finalize`          — reserved hook (no-op today)

Flags: `--help`, `--dry-run`, `--allow-root`. Env: `UMASK=077|022`. Logs to `/tmp/bootstrap0r-YYYYMMDDHHMMSS.log`.

The `BOOTSTRAP0R_NO_MAIN=1` guard at the bottom of the script lets you `source` it for per-phase debugging:

```sh
BOOTSTRAP0R_NO_MAIN=1 . ./bootstrap0r.sh
phase_sudoers   # for example
```

Spec: `docs/superpowers/specs/2026-05-07-bootstrap0r-design.md`.
Plan: `docs/superpowers/plans/2026-05-07-bootstrap0r-implementation.md`.
```

- [ ] **Step 2: Commit and push**

```sh
cd /home/zero/dev/bootstrap0r
git add CLAUDE.md
git commit -m "update CLAUDE.md status: bootstrap0r is no longer greenfield"
git push origin main
```

---

## Self-Review

**Spec coverage:**
- Goal / repo layout → Task 1
- Header attribution → Task 1 (stub) and Task 2 (full)
- CLI surface (`--help`, `--dry-run`, `--allow-root`) → Task 2
- `UMASK` env + `validate_umask` → Task 4
- Globals → Task 2 + Task 4 (apt + cleanup additions)
- Helpers (`log`/`warn`/`die`/`has_cmd`/`need_cmd`) → Task 2
- UI helpers (`is_tty`/`step_label`/`spin_*`/`run_step`) → Task 3
- apt helpers + idempotency contract → Task 4 + per-phase tasks
- `cleanup_on_exit` trap → Task 4
- `preflight` (refuse root, need_cmd, sudo -v) → Task 4
- 8 phases → Tasks 5–12
- `print_summary` → Task 4
- Repo creation (gh) → Task 14
- README / LICENSE / .gitignore → Task 1 + audited Task 13
- Status section in CLAUDE.md → Task 15

All spec sections covered.

**Placeholder scan:** No `TBD`, `TODO`, `implement later`, or "similar to Task N" references. Each task has full code.

**Type / name consistency:** `phase_umask_walk`, `phase_sudoers`, `phase_nadrbomz`, `phase_apt_base`, `phase_chrome`, `phase_steam`, `phase_flatpak_protonplus`, `phase_finalize` — same names used in `main()` (Task 4), function definitions (Tasks 5–12), and CLAUDE.md status (Task 15). `_tmp_debs` declared in Task 2 globals, used in Tasks 9 and 10. `BOOTSTRAP0R_NO_MAIN` introduced in Task 6 and referenced in Task 15.

**Notable trade-offs documented in the plan:**
- No xUnit-style test harness (verification ladder explained at top).
- UTF-8 spinner has an ASCII fallback documented inline (Task 3).
- `BOOTSTRAP0R_NO_MAIN` guard kept permanently for debuggability.
- Real-execution of phases on the user's box is deferred — the dry-run path is the verifiable artifact; full runs are manual on a fresh VM.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-07-bootstrap0r-implementation.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session via `superpowers:executing-plans`, batch with checkpoints.

Which approach?
