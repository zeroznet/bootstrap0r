# bootstrap0r

<p align="center">
  <a href="https://github.com/zeroznet/bootstrap0r/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/zeroznet/bootstrap0r/ci.yml?branch=main&style=flat-square&label=ci&labelColor=000000" alt="CI"></a>
  <a href="https://github.com/zeroznet/bootstrap0r/commits/main"><img src="https://img.shields.io/github/last-commit/zeroznet/bootstrap0r?style=flat-square&labelColor=000000&color=ff5fff" alt="Last Commit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/zeroznet/bootstrap0r?style=flat-square&labelColor=000000&color=875fff" alt="License"></a>
  <img src="https://img.shields.io/badge/shell-POSIX%20sh-00ffff?style=flat-square&labelColor=000000" alt="POSIX sh">
</p>

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

Idempotent.

Every run starts with `apt full-upgrade` + `autoremove --purge` + `autoclean`, so a
re-run also upgrades installed APT packages. Flatpak updates are left to normal
`flatpak update` (Chrome and Steam each install their own apt repo via `.deb`
post-install hooks, so they upgrade with APT).

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
