# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

`bootstrap0r` is Robert's personal Linux bootstrap script. Run it on a fresh install (or a clobbered home dir) and it brings the box back to the working environment Robert expects: shell defaults, umask, repos and keys for third-party packages, a curated set of installs (e.g. Chrome), and any post-install tweaks.

It is opinionated for Robert's machine, not a general-purpose provisioner. No Ansible, no fleet management, no profiles for other users. It is a script, not a framework.

## Target

Primary target is **Debian 13 (trixie)** on x86_64, matching the host this repo lives on. Anything outside that is best-effort. When adding distro-specific logic, gate it on `/etc/os-release` (`ID`, `VERSION_ID`) rather than guessing from `uname`.

## Scope

In scope:
- Shell/login defaults (umask, PATH, locale).
- APT sources, keyrings, and package installs.
- Third-party repos installed the supported way (signed-by keyrings under `/etc/apt/keyrings`, never `apt-key`).
- Idempotent re-runs: running the script twice should be a no-op the second time.

Out of scope unless explicitly requested:
- Dotfiles (Robert manages those separately).
- Secrets, SSH keys, GPG private material.
- Anything that requires interactive prompts in the middle of a long run.

## Conventions

Inherits everything from `/home/zero/dev/CLAUDE.md` (workspace rules, persona, commit style, attribution header, behavioral guidelines). Add project-specific details here only when they diverge or extend.

Script-specific points:
- POSIX `sh`, strict mode (`set -eu`), helpers `log`/`warn`/`die`/`has_cmd`/`need_cmd` per workspace convention.
- Every operation that touches the system must be **idempotent** and **safe to re-run**. Check before acting (`dpkg -s`, file existence, current value of a setting) instead of blindly applying.
- Privileged operations: prefer `sudo` invoked per-command over running the whole script as root. The script should refuse to run as root unless an explicit flag says otherwise.
- `--help` / `usage()` is mandatory. Add a `--dry-run` mode early; destructive system changes without one are a footgun.
- Network installs use `curl` first, `fetch` fallback, per workspace convention. Verify checksums or signatures for anything pulled outside APT.

## Status

`bootstrap0r.sh` is the entry point. Run it directly or via the curl-pipe one-liner from the README. Phases run in fixed order:

1. `phase_umask_walk`        — chmod `$HOME` to match `$UMASK` (077 default, 022 alt)
2. `phase_sudoers`           — install `/etc/sudoers.d/00-bootstrap0r-defaults`
3. `phase_apt_base`          — i386 multiarch + base/gaming packages (incl. `zsh`, prereq for nadrbomz)
4. `phase_nadrbomz`          — curl-pipe `https://github.com/zeroznet/nadrbomz`
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

## Repo

Public GitHub repo will be attached. Until then this is local-only. License default is BSD-2-Clause per workspace policy.
