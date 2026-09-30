# Chromium D-Bus singleton activation (future fork direction)

Not started -- this is a write-up of a problem observed on this machine and
the shape a fix would take in a Chromium fork, kept here so the idea isn't
lost before anyone has time to act on it. Unlike
[`docs/patched-anaconda-installer.md`](patched-anaconda-installer.md), there
is no fork yet.

## Symptom

`flatpak run org.chromium.Chromium`, launched from KDE Plasma's task
manager, appeared to hang indefinitely. What actually happened: the first
launch was slow to map its first window (cold profile/cache, GPU process
init). Re-clicking the launcher icon while waiting didn't focus/wait on that
in-progress launch -- it ran the `.desktop` file's `Exec=` line again. This
repeated a handful of times, producing five fully independent Chromium
process trees (each with its own zygote, GPU process, network/storage
service, and renderers) all fighting over the same CPU cores, disk cache,
and `/dev/dri/renderD128`, which made every one of them even slower to
start -- compounding into what looked like a permanent hang.

## Root cause

Two things stacked:

1. **KDE's task manager has no way to know a launch is in flight** without
   the freedesktop startup-notification protocol or an existing window to
   match against. With neither available yet, a second click is
   indistinguishable from a fresh launch request.
2. **Chromium doesn't use D-Bus activation.** On Linux it implements its own
   legacy singleton check (a lock file + Unix domain socket handshake, see
   `chrome/browser/process_singleton_posix.cc` upstream) that predates
   `org.freedesktop.Application`. That handshake is timeout-based: if the
   already-running instance doesn't answer fast enough (because it's still
   starting up, or because Flatpak's per-launch sandbox namespacing gets in
   the way of the socket), the new process assumes there's no existing
   instance and cold-starts a full second browser instead of forwarding the
   "open a window" request.

Neither KDE nor Flatpak are missing a check they're supposed to run
themselves -- both already fully support the standard fix (D-Bus
activation: `DBusActivatable=true` in the `.desktop` file + an
`org.freedesktop.Application` implementation), and other well-behaved
Flatpak apps get correct, invisible single-instance behavior for free
through it. Chromium (and Electron apps generally) just never adopted that
contract, because the existing singleton code is shared, cross-platform
logic that already works well enough on Windows/macOS without it.

## Direction for a fork

- Add a Linux-only `org.freedesktop.Application` implementation to
  Chromium's browser-process startup, gated behind `BUILDFLAG(IS_LINUX)`
  (excluding ChromeOS), that responds to `Activate`/`Open` D-Bus calls the
  same way the existing process-singleton IPC responds to a second launch
  today.
- Ship a matching `<app-id>.service` file so `flatpak run` (or a native
  desktop launch) can be delivered via bus activation instead of always
  exec'ing a fresh `chrome` binary; wire `DBusActivatable=true` into the
  `.desktop` file.
- Keep the existing lock-file/socket mechanism as the fallback for
  non-D-Bus environments (still needed for other embedders, e.g. CEF).
- Flatpak manifest side: the sandbox needs `--own-name=<app-id>` (or the
  equivalent `finish-args`) for the bus name the service file activates, so
  this doesn't depend on the fragile shared-socket path across sandbox
  namespaces at all.

## Why this is genuinely a fork, not just a patch to carry

Chromium's process-singleton code is shared across all desktop platforms;
Linux-specific D-Bus activation is new surface area with its own
maintenance cost, and upstream has historically been conservative about
platform-specific branches in that file. Realistic expectation: this stays
a downstream patch (in the vein of what Vivaldi/Brave carry) rather than
something likely to land upstream quickly, so plan for it to need rebasing
across Chromium version bumps.

## Stopgap in use today

No fork exists yet, so the actual fix on this machine is external to
Chromium: wrap the launcher's `Exec=` in an `flock`-guarded script so a
second launch blocks (or no-ops) on a lockfile instead of racing the first
instance's cold start, and set `StartupNotify=true` /
correct`StartupWMClass` on the `.desktop` file so KDE's task manager shows
a busy state instead of silently permitting a duplicate launch.
