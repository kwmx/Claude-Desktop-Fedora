# The Chromium sandbox and `install.sh --sandbox`

Claude Desktop is an Electron app, so it ships an embedded Chromium. Chromium
runs untrusted work — page rendering, JS execution, network parsing — inside
low-privilege **renderer** processes that are isolated from the rest of the
system by a sandbox. If a renderer is compromised, the sandbox is what stops
that code from reading your files or talking to the kernel freely.

On Linux, Chromium builds that isolation from two layers:

1. A **setuid helper** (`chrome-sandbox`) that sets up the initial namespace
   jail before the renderer drops privileges. Because it needs to call
   privileged APIs during startup, it must be owned by `root` and carry the
   setuid bit (`chmod 4755`).
2. **Unprivileged user namespaces**, a kernel feature that lets a normal user
   create the same jail *without* a setuid binary.

Chromium can use either layer. `install.sh` lets you pick which one — or opt
out — via `--sandbox`. The choice only affects **how the jail is created**; in
the `setuid` and `namespace` cases the renderer ends up equally sandboxed.

## The three modes

### `setuid` _(default)_

```bash
./install.sh                     # or: --sandbox setuid
```

`install.sh` runs `chown root:root` + `chmod 4755` on the bundled
`/opt/claude-desktop/chrome-sandbox`, then launches the app with **no** extra
flags. Chromium finds the properly-permissioned helper and uses it.

- **Isolation:** full.
- **Cost:** one small `root`-owned setuid binary lives in `/opt`. Setuid
  binaries are a classic local-privilege-escalation surface, so some people
  would rather not have one — that's what `namespace` is for.
- **Fallback:** if `chrome-sandbox` isn't present in the payload, `install.sh`
  prints a warning and automatically drops to `namespace`.

### `namespace`

```bash
./install.sh --sandbox namespace
```

Launches with `--disable-setuid-sandbox`, so Chromium skips the setuid helper
and builds the jail from **unprivileged user namespaces** instead. No
root-owned setuid file to install or maintain.

- **Isolation:** full — same jail, different setup path.
- **Requirement:** the kernel must allow unprivileged user namespaces.
  `install.sh` checks `sysctl user.max_user_namespaces` and warns if it reads
  as `0` (disabled). Fedora ships this enabled by default; a hardened or
  locked-down kernel may not. If the app won't start under this mode, that
  sysctl is the first thing to check.
- **Recommended** if you'd prefer not to own a root setuid binary.

### `none`

```bash
./install.sh --sandbox none
```

Launches with `--no-sandbox`. The renderer runs **with no isolation** — a
compromised page or renderer has the same access to your account as any program
you run. Last resort only, e.g. to confirm that a startup failure is
sandbox-related before fixing the real cause.

- **Isolation:** none.
- **Use when:** neither of the above works and you understand the risk.

## How the mode is wired in

`install.sh` translates the mode into a launch flag (`install.sh:64`):

| mode        | flag                       |
| ----------- | -------------------------- |
| `setuid`    | _(none)_                   |
| `namespace` | `--disable-setuid-sandbox` |
| `none`      | `--no-sandbox`             |

When there's no flag, the CLI entry (`/usr/local/bin/claude-desktop`) is a plain
symlink to the app. When a flag is needed, `install.sh` writes a tiny wrapper
script that `exec`s the app with the flag instead, and bakes the same flag into
the `Exec=` line of the `.desktop` launcher. So both the terminal command and
the GUI icon honor your `--sandbox` choice.

Re-running `install.sh` with a different `--sandbox` value switches modes
cleanly; the setuid bit is only applied in `setuid` mode.

## Which should I use?

- **Just want it to work with full isolation:** the default (`setuid`).
- **Don't want a root setuid binary, on a stock Fedora kernel:** `namespace`.
- **Debugging a won't-launch problem, or nothing else works:** `none`,
  temporarily.
