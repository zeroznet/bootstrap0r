<!-- written by Robert Bopko (github.com/zeroznet) with Boba Bott (Claude Opus 5.5) -->

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
- Every operation that touches the system must be **idempotent** and **safe to re-run**. Check before acting (`dpkg -s`, file existence, current value of a setting) instead of blindly applying.
- Privileged operations: prefer `sudo` invoked per-command over running the whole script as root. The script should refuse to run as root unless an explicit flag says otherwise.
- Add a `--dry-run` mode early; destructive system changes without one are a footgun.
- Verify checksums or signatures for anything pulled outside APT.

## Status

`bootstrap0r.sh` is the entry point. Run it directly or via the curl-pipe one-liner from the README. Phases, flags and env vars live in `usage()` (`sh bootstrap0r.sh --help`); keep the README in sync when they change.

The `BOOTSTRAP0R_NO_MAIN=1` guard at the bottom of the script lets you `source` it for per-phase debugging:

```sh
BOOTSTRAP0R_NO_MAIN=1 . ./bootstrap0r.sh
phase_sudoers   # for example
```

## Repo

Public at https://github.com/zeroznet/bootstrap0r, BSD-2-Clause. CI (`.github/workflows/ci.yml`) runs shellcheck, a dash parse and a `--help` smoke run; it never executes a phase.
