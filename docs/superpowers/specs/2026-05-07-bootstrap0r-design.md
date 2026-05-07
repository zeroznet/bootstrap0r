# bootstrap0r — Design

**Date:** 2026-05-07
**Author:** Robert Bopko (with Boba Bott / Claude Opus 4.7)
**Status:** Approved

## Goal

A single-file POSIX `sh` bootstrap script that takes a fresh Debian 13 (or Ubuntu) install and brings it to Robert's working environment in one run: umask-clamp `$HOME`, install personal sudoers defaults, deploy dotfiles via `nadrbomz`, install i386 multiarch + gaming/base packages, install Google Chrome and Steam, set up Flathub + ProtonPlus.

The script lives at `https://github.com/zeroznet/bootstrap0r/blob/main/bootstrap0r.sh` and is invokable via curl-pipe one-liner.

## Non-goals

- Not a general-purpose provisioner (Ansible, fleet, profiles for other users).
- Not a dotfile manager — that is `nadrbomz`'s job.
- No SSH key, GPG, or other secret material handling.
- No interactive prompts mid-run (other than the initial `sudo -v` password).
- No distro support beyond Debian 13 and current Ubuntu (best-effort; package names happen to align).

## Architecture

**Single fat linear script** (`bootstrap0r.sh`). Helpers at top, phase functions below, `main()` at bottom calling phases via a `run_step` wrapper that handles spinner + step counter + log redirection.

Rationale: preserves the curl-pipe one-liner pattern from `nadrbomz`, keeps everything auditable in one file, easy to mirror its style.

### Repo layout

```
bootstrap0r/
├── bootstrap0r.sh        # main script
├── README.md             # nadrbomz-style: what / one-liner / flags / files / license
├── LICENSE               # BSD-2-Clause
├── .gitignore            # mirrored from nadrbomz
├── CLAUDE.md             # project guidance for Claude (already exists)
└── docs/superpowers/specs/
    └── 2026-05-07-bootstrap0r-design.md   # this file
```

### Header

Every source file starts with the workspace-standard attribution line:

```sh
#!/usr/bin/env sh
# scripted/written by Robert Bopko (github.com/zeroznet) with Boba Bott (Claude Opus 4.7)
```

## CLI surface

```
bootstrap0r.sh [--help] [--dry-run] [--allow-root]
```

- `--help` — print usage (flags, env vars, phase list, repo URL) and exit.
- `--dry-run` — print what each step would do, modify nothing on disk.
- `--allow-root` — permit running as `root` (default: refused with `die`).

### Env vars

- `UMASK` — `077` (default) or `022`. Any other value → `die`.

## Globals

```sh
set -eu

UMASK="${UMASK:-077}"
LOG_FILE="${TMPDIR:-/tmp}/bootstrap0r-$(date +%Y%m%d%H%M%S).log"
NADRBOMZ_URL="https://raw.githubusercontent.com/zeroznet/nadrbomz/main/nadrbomz.sh"
DRY_RUN=0
ALLOW_ROOT=0
TOTAL_STEPS=8
CURRENT_STEP=0
_apt_updated=0     # apt_update_once cache
_spinner_pid=""    # active spinner background pid (for trap cleanup)
```

## Helpers

Reused from `nadrbomz`:
- `log()`, `warn()`, `die()` — stdout/stderr printers; `die` exits 1.
- `has_cmd()`, `need_cmd()` — command-presence checks.

New for `bootstrap0r`:
- `is_tty()` — `[ -t 1 ] && [ -t 2 ]`. Gates spinner.
- `step_label "<text>"` — increments `CURRENT_STEP`, prints `[N/M] <text>...` to stderr.
- `spin_start` / `spin_stop` — start/stop a background braille-spinner (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) that overwrites the current line. No-op when `is_tty` returns false. Stores pid in `$_spinner_pid`; `spin_stop` kills it and clears the line.
- `run_step "<label>" <cmd...>` — orchestration wrapper:
  1. `step_label "<label>"`
  2. `spin_start` (if TTY and not dry-run)
  3. If `DRY_RUN=1` → echo `[DRY] would run: <cmd>` and return 0
  4. Else → run `<cmd> >>"$LOG_FILE" 2>&1`
  5. `spin_stop`
  6. On exit 0 → print ` OK\n`
  7. On exit != 0 → print ` FAIL\nLog: $LOG_FILE\n`, tail last 20 lines of `$LOG_FILE` to stderr, `exit 1`
- `apt_update_once` — if `$_apt_updated -eq 0`, run `sudo apt update`, set `_apt_updated=1`. Subsequent calls are no-ops.
- `apt_install <pkg...>` — filters out already-installed packages via `dpkg -s "$pkg" >/dev/null 2>&1`, calls `sudo DEBIAN_FRONTEND=noninteractive apt install -y` only on the missing list. If list empty, no-op.
- `validate_umask` — `case "$UMASK" in 077|022) : ;; *) die "UMASK must be 077 or 022" ;; esac`.
- `cleanup_on_exit` — `trap` handler: kills `$_spinner_pid` if set, removes `/tmp/bootstrap0r-*.deb` it created. Does NOT delete `$LOG_FILE`.

## Phases

`main()` runs these in order via `run_step`:

```sh
main() {
    parse_args "$@"
    preflight
    validate_umask
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

### `preflight`

- If `$(id -u) -eq 0` and `ALLOW_ROOT=0` → `die "run as user, not root; sudo invoked per-command. Use --allow-root to override"`.
- `need_cmd curl git sudo`. (`zsh` is needed by nadrbomz, but nadrbomz checks itself.)
- `sudo -v` — prime credential cache so the rest runs without prompts. If user enters wrong password, sudo exits non-zero, `set -e` aborts.
- Set `trap cleanup_on_exit EXIT HUP INT TERM`.

### `phase_umask_walk`

Walks the entire `$HOME` and applies the chosen umask retroactively. Runs **first** so subsequent install steps that drop files into `$HOME` (Flatpak overrides, Steam dirs, OMZ dirs, etc.) inherit the umask.

- `077` → `chmod -R go-rwx "$HOME"` — strip group + other read/write/execute.
- `022` → `chmod -R go-w "$HOME"` — strip group + other write only.
- Dry-run: print count of paths that would change, e.g. via:
  ```sh
  find "$HOME" \( -perm /go=rwx \) -type f | wc -l   # for 077
  find "$HOME" \( -perm /go=w \) -type f | wc -l      # for 022
  ```
- Idempotency: `chmod` on already-conforming files is a no-op.
- Scope justification: full walk, no excludes. Bootstrap0r runs as the FIRST step on a fresh machine — Chrome / Flatpak / Steam directories don't exist yet.

### `phase_sudoers`

Installs `/etc/sudoers.d/00-bootstrap0r-defaults` with:

```
Defaults timestamp_timeout=60,!tty_tickets
Defaults rootpw
```

Sequence:
1. `tmp="$(mktemp)"; printf '%s\n%s\n' '...' '...' > "$tmp"`.
2. `sudo visudo -cf "$tmp"` — validate before installing. Failure → `die`.
3. If `/etc/sudoers.d/00-bootstrap0r-defaults` exists and `cmp -s "$tmp" /etc/sudoers.d/00-bootstrap0r-defaults` → no-op (idempotent).
4. `sudo install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/00-bootstrap0r-defaults`.
5. `rm -f "$tmp"`.

Drop-in is preferred over editing `/etc/sudoers` directly: cleaner re-runs, easier rollback, no risk of breaking `/etc/sudoers` syntax.

### `phase_nadrbomz`

```sh
curl -fsSL "$NADRBOMZ_URL" | sh
```

Output redirected by `run_step` into `$LOG_FILE`. `nadrbomz` handles its own idempotency (skips OMZ if installed, `git pull` instead of clone for plugins, timestamped backups for dotfiles).

### `phase_apt_base`

```sh
sudo dpkg --add-architecture i386   # native idempotent
apt_update_once
apt_install \
    curl ca-certificates gnupg \
    flatpak \
    mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    vulkan-tools \
    gamemode \
    mangohud
```

### `phase_chrome`

```sh
if dpkg -s google-chrome-stable >/dev/null 2>&1; then return 0; fi
deb="${TMPDIR:-/tmp}/bootstrap0r-google-chrome.deb"
curl -fsSL -o "$deb" \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y "$deb"
rm -f "$deb"
```

Google's post-install hook adds `/etc/apt/sources.list.d/google-chrome.list` and a signed-by keyring under `/etc/apt/keyrings/`, so future `apt upgrade` keeps Chrome current.

### `phase_steam`

```sh
if dpkg -s steam-launcher >/dev/null 2>&1; then return 0; fi
deb="${TMPDIR:-/tmp}/bootstrap0r-steam.deb"
curl -fsSL -o "$deb" \
    https://repo.steampowered.com/steam/archive/stable/steam_latest.deb
sudo apt install -y "$deb"
rm -f "$deb"
```

Same pattern as Chrome — Valve's `.deb` post-install adds `/etc/apt/sources.list.d/steam-stable.list` + Steam keyring. No need to enable `contrib/non-free/non-free-firmware`: required deps are in `main`.

### `phase_flatpak_protonplus`

```sh
flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

if ! flatpak info com.vysp3r.ProtonPlus >/dev/null 2>&1; then
    flatpak install -y --noninteractive flathub com.vysp3r.ProtonPlus
fi

flatpak override --user --filesystem="$HOME/.steam"             com.vysp3r.ProtonPlus
flatpak override --user --filesystem="$HOME/.local/share/Steam" com.vysp3r.ProtonPlus
```

`remote-add --if-not-exists` and `flatpak override --user` are natively idempotent.

### `phase_finalize`

Currently no-op. Reserved hook for future post-install tweaks (default browser, MIME associations, etc.). Exists so `TOTAL_STEPS` reflects reality and a future step can slot in without renumbering.

### `print_summary`

Final block printed after all steps:

```
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

## Idempotency contract

| Phase | Mechanism |
|---|---|
| `umask_walk` | `chmod` on already-conforming bits is a no-op at the kernel level. |
| `sudoers` | `cmp` tmpfile vs target; identical → skip. |
| `nadrbomz` | Owned by `nadrbomz` script (skips OMZ, pulls vs clones, backups). |
| `apt_base` | `dpkg --add-architecture i386` is natively idempotent. `apt_install` filters via `dpkg -s`. |
| `chrome` | `dpkg -s google-chrome-stable` skip. |
| `steam` | `dpkg -s steam-launcher` skip. |
| `flatpak_protonplus` | `--if-not-exists` for remote, `flatpak info` skip for app, `--user` overrides idempotent. |
| `finalize` | Print only. |

A successful re-run prints all steps as `OK` with no system mutations.

## Error handling

- `set -eu` at top.
- No `pipefail` (not POSIX `sh` portable). Where pipe-error detection matters, use tmpfile-and-check pattern instead of pipes.
- `run_step` traps non-zero exit, prints `FAIL` + log path + tail of log, exits 1.
- `cleanup_on_exit` trap on `EXIT HUP INT TERM` kills any active spinner pid and removes `/tmp/bootstrap0r-*.deb` artifacts. Preserves `$LOG_FILE`.
- Ctrl-C mid-run → trap fires → exit 130, partial state visible in log.

## Dry-run semantics

| Phase | `--dry-run` behavior |
|---|---|
| `umask_walk` | Print count of files that would be modified. |
| `sudoers` | Write tmpfile, run `visudo -cf`, print `[DRY] would install <tmp> -> /etc/sudoers.d/00-bootstrap0r-defaults`. |
| `nadrbomz` | Print `[DRY] would curl-pipe $NADRBOMZ_URL`. |
| `apt_base` | Print `[DRY] would apt install <missing-pkg-list>` (skip-if-installed check is real, not dry). |
| `chrome` / `steam` | Print `[DRY] would download <url>; would dpkg install <deb>`. |
| `flatpak_protonplus` | Print `[DRY] would flatpak install com.vysp3r.ProtonPlus + overrides`. |
| `finalize` | Print summary as if real run. |

`run_step` adds the `[DRY]` prefix automatically; phase functions don't need their own dry-run branches except for the umask walk's count query.

## Visual UX

Successful TTY run looks like:

```
$ ./bootstrap0r.sh
==> bootstrap0r — Linux env bootstrap (UMASK=077)
[1/8] Clamping permissions on $HOME (077)... ⠋ OK
[2/8] Installing sudoers defaults... ⠹ OK
[3/8] Bootstrapping shell (nadrbomz)... ⠼ OK
[4/8] Adding i386 multiarch and base packages... ⠧ OK
[5/8] Installing Google Chrome... ⠇ OK
[6/8] Installing Steam... ⠏ OK
[7/8] Setting up Flathub + ProtonPlus... ⠋ OK
[8/8] Final touches... OK

==> Done.
Log: /tmp/bootstrap0r-20260507143022.log
...
```

Non-TTY (pipe / log capture / CI): no spinner, just the step labels with trailing `OK` / `FAIL`.

## Repo creation

Performed once after the script and scaffold are written:

```sh
cd /home/zero/dev/bootstrap0r
git init -b main
git add CLAUDE.md bootstrap0r.sh README.md LICENSE .gitignore docs/
git commit -m "init bootstrap0r: personal Debian/Ubuntu env bootstrap"
gh repo create zeroznet/bootstrap0r \
  --public \
  --description "Personal Linux bootstrap for Debian 13: umask clamp, dotfiles via nadrbomz, gaming + dev installs." \
  --source=. \
  --remote=origin \
  --push
```

Requires `gh` installed and authenticated. Fallback: manual `gh repo create` via web UI + `git remote add origin git@github.com:zeroznet/bootstrap0r.git && git push -u origin main`.

## README content

Mirrors `nadrbomz/README.md` shape. Full draft:

````markdown
# bootstrap0r

Personal Linux environment bootstrap for Debian 13 / Ubuntu.

## What it does

- clamps permissions on `$HOME` to match `UMASK` (077 default, 022 optional)
- installs personal sudoers defaults via `/etc/sudoers.d/00-bootstrap0r-defaults`
- bootstraps shell via [nadrbomz](https://github.com/zeroznet/nadrbomz)
- enables i386 multiarch, installs base + gaming packages
  (`mesa-vulkan-drivers`, `vulkan-tools`, `gamemode`, `mangohud`, multilib)
- installs Google Chrome (official `.deb`)
- installs Steam (Valve official `.deb`)
- sets up Flathub + ProtonPlus, with Steam paths exposed to ProtonPlus

Idempotent. Re-runs are no-ops once steps complete.

Updates of installed packages are not handled by `bootstrap0r`; they flow through
normal `apt upgrade` and `flatpak update` (Chrome and Steam each install their own
apt repo via `.deb` post-install hooks).

## One-line install

```sh
curl -fsSL https://raw.githubusercontent.com/zeroznet/bootstrap0r/main/bootstrap0r.sh | sh
```

With permissive umask:

```sh
curl -fsSL https://raw.githubusercontent.com/zeroznet/bootstrap0r/main/bootstrap0r.sh | UMASK=022 sh
```

Dry run (after cloning):

```sh
./bootstrap0r.sh --dry-run
```

## Flags

- `--help` — show usage
- `--dry-run` — print what would be done, do not modify anything
- `--allow-root` — permit running as root (default: refused)

## Env

- `UMASK` — `077` (default) or `022`. Other values rejected.

## Files

- `bootstrap0r.sh` — bootstrap script
- `LICENSE` — BSD-2-Clause

## Logs

`/tmp/bootstrap0r-YYYYMMDDHHMMSS.log` — full apt/flatpak output per run.

## License

Licensed under the BSD-2-Clause license. See LICENSE.
````

## LICENSE

BSD-2-Clause, copyright "2026 Robert Bopko". Copy of `~/dev/nadrbomz/LICENSE` with project name updated.

## .gitignore

```
.claude/settings.local.json
.env
.env.*
*.swp
.DS_Store
HANDOFF.md
HANDOFF.md.bak
```

(Identical to `nadrbomz/.gitignore`.)

## Open questions

None at design time. Future hooks reserved in `phase_finalize` for post-install tweaks not currently scoped.

## Verification (post-implementation)

A pass on a fresh Debian 13 VM should produce:

1. `$HOME` walk completes (verify random files are 0600 / dirs 0700 for 077).
2. `/etc/sudoers.d/00-bootstrap0r-defaults` exists, `sudo visudo -c` passes.
3. `~/.zshrc`, `~/.bashrc`, OMZ dirs deployed by nadrbomz.
4. `dpkg --print-foreign-architectures` includes `i386`.
5. `dpkg -s google-chrome-stable steam-launcher mesa-vulkan-drivers gamemode mangohud` all installed.
6. `flatpak list` includes `com.vysp3r.ProtonPlus`.
7. `flatpak info com.vysp3r.ProtonPlus | grep -i filesystem` shows `~/.steam` and `~/.local/share/Steam`.
8. Re-running the script prints all 8 steps as `OK` with no system mutations (verify via `apt list --installed` diff).
9. `--dry-run` on a fresh box prints intended actions and modifies nothing (`git status` of `/etc/` and `$HOME` clean afterward, modulo log file).
