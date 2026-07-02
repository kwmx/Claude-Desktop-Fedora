# Claude Desktop on Fedora — install toolkit

Installs Claude Desktop from Anthropic's official Debian package on Fedora
(which isn't an officially supported target) by extracting the `.deb` and
wiring it into `/opt` + the GNOME apps list — This was written by claude to use claude so use it with caution and after review.

> Heads up: there is **no auto-update** on this path. To update, re-run
> `download.sh` then `install.sh` (see below).

## Files

| file           | run it? | what it does                                                          |
| -------------- | ------- | --------------------------------------------------------------------- |
| `lib.sh`       | no      | shared config + helpers, sourced by the other three                   |
| `download.sh`  | yes     | fetch the latest `.deb` from the apt pool and extract it locally      |
| `install.sh`   | yes     | copy payload to `/opt`, set up the sandbox, register the GUI launcher |
| `uninstall.sh` | yes     | undo the install and remove the downloaded/extracted files            |

Keep all four in the same directory. `download.sh` creates `deb/` and
`extract/` alongside them; `install.sh`/`uninstall.sh` read from there.

```bash
chmod +x download.sh install.sh uninstall.sh   # downloads drop the exec bit
```

## Install / update

```bash
./download.sh      # pulls newest .deb, verifies SHA256, extracts to ./extract
./install.sh       # installs to /opt + adds "Claude" to your apps list
```

One-shot update later: `./download.sh --install` (chains straight into install).
`download.sh` is idempotent — it skips the download/extract when you're already
on the latest version (use `--force` to redo).

## Sandbox choice (`install.sh --sandbox ...`)

Claude Desktop is an Electron app; its renderer runs in a Chromium sandbox.

- `setuid` _(default)_ — `chown root` + `chmod 4755` the bundled `chrome-sandbox`.
  Full isolation, no launch flags. Falls back to `namespace` if the helper is missing.
- `namespace` — launch with `--disable-setuid-sandbox` and use Fedora's
  unprivileged user namespaces instead. No setuid binary to maintain; **recommended**
  if you'd rather not have a root-owned setuid file. Verifies
  `user.max_user_namespaces` is nonzero.
- `none` — `--no-sandbox`. No isolation; last resort only.

See `CHROME-SANDBOX.md` for the full explanation.

## Uninstall

```bash
./uninstall.sh                # remove system install + local deb/ and extract/
./uninstall.sh --keep-local   # remove system install only, keep deb/ + extract/
./uninstall.sh --purge        # also delete your ~/.config + ~/.cache app data
```

## Requirements

`curl`, `binutils` (for `ar`), `zstd`, and coreutils. On Fedora only `binutils`
is usually missing: `sudo dnf install binutils`. All scripts use `sudo`
internally where they touch `/opt` and `/usr`.
