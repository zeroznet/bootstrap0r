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
