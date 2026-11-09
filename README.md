# quine-linux

Quine distro of Linux based on uBlue Aurora

## Building

The image is built in two repos:

- **[`quine-global-labs/aurora`](https://forge.in.quineglobal.com/quine-global-labs/aurora)**,
  our fork of [Aurora](https://github.com/ublue-os/aurora). Its workflow
  builds it with Aurora's own `just build` and publishes it as
  `forge.in.quineglobal.com/quine-global-labs/aurora:stable`. Changes that
  have to happen *inside* Aurora's build (its package set, build scripts,
  the Kinoite base it starts from) go there, as commits on the fork.
- **This repo's `Containerfile`**, which builds the quine-linux bootc image
  on top of that, layering in everything under `overlay/`, plus a
  `kmod-builder` stage that compiles the CS8409 mic-fix kernel module (see
  [Hardware-specific patches](#hardware-specific-patches) below). Anything a
  `RUN` step on top of Aurora can do belongs here, not in the fork. Its
  workflow publishes `forge.in.quineglobal.com/quine-global-labs/quine-linux`,
  and the live ISO and disk image (to MinIO). Installed systems pull and
  update from the same image as `registry.quineglobal.com/quine-linux`, a
  pull-only name for it (Taskfile.yml's `UPDATE_IMAGE`).

Like Aurora, there's one installer: the live ISO's. There's no separate
install ISO.

[`Taskfile.yml`](Taskfile.yml) (requires [`task`](https://taskfile.dev)) is
the supported way to drive all of this — run `task` with no arguments to
list what's available. Notably:

- `task build-image` — builds the image on our published Aurora. To build
  on stock upstream Aurora instead, pass
  `BASE_IMAGE=ghcr.io/ublue-os/aurora:stable`; on a local build of the fork,
  `BASE_IMAGE=localhost/aurora:stable`. Builds locally, as root, with podman, or
  docker if podman isn't installed (force either with
  `CONTAINER_RUNTIME=docker|podman`). Every task below works with either;
  under docker, images are copied via skopeo into a
  `quine-containers-storage` volume for `bootc-image-builder` to read.
- `task build-disk-image` — builds a ready-installed disk image (qcow2)
  via `bootc-image-builder`, landing in `output/qcow2/disk.qcow2`. It has
  no user: plasma-setup creates the first one at first boot.
- `task build-live-iso` — builds a live ISO (`live/`, after Aurora's):
  boots into a Quine Linux session with Anaconda WebUI to install it,
  landing in `output/live/Quine-Linux-Live.iso`. Podman only.
- `task test:stage` / `task test:boot` — stage the locally-built image as
  this machine's next boot target (`bootc switch`), optionally rebooting
  into it immediately. The fast way to test a change — especially the
  kernel module — against the real running system, without building an ISO
  or reinstalling anything.
- `task revert` — rolls back to the previously-booted deployment and
  reboots, undoing a `test:boot` switch (or any other deployment change) if
  something's wrong.

Equivalently, by hand:

```sh
sudo podman build -t quine-linux -f Containerfile .
```

To build the Aurora fork yourself (Linux, with buildah, cpp, just >= 1.46,
skopeo, jq, yq and cosign), in a clone of `quine-global-labs/aurora`:

```sh
sudo just build --image aurora --tag stable --flavor main   # -> localhost/aurora:stable
```

An ISO can then be generated from the built image with `bootc-image-builder`
(`ghcr.io/osbuild/bootc-image-builder`; the project now lives in
[osbuild/image-builder](https://github.com/osbuild/image-builder), and the old
`quay.io/centos-bootc/bootc-image-builder` image is no longer updated).

## Releasing

On the forge: **Actions → Release → Run workflow**. It works out the next
version from the newest `v*` tag, tags `main` with it and pushes the tag.
The tag push makes `iso.yml` build both architectures, upload the files to
`releases/<tag>/` and publish the Forgejo release. Choose `bump`:

| `bump` | From `v0.1.0-alpha.2` | From `v0.1.0` |
|---|---|---|
| `prerelease` (with `pre`) | `v0.1.0-alpha.3`, or `v0.1.0-beta.1` with `pre: beta` | `v0.1.1-alpha.1` |
| `release` | `v0.1.0` | an error (already released) |
| `patch` / `minor` / `major` | `v0.1.1` / `v0.2.0` / `v1.0.0` | the same, plus `-<pre>.1` unless `pre: none` |

`version` (e.g. `1.0.0`) sets the version exactly instead. `dry_run` only
reports the tag it would make. It refuses to reuse a tag or go backwards.
Pushing the tag needs the repo secret `RELEASE_TOKEN`, a Forgejo token with
`write:repository`. The automatic token can push, but a tag pushed with it
doesn't start `iso.yml`.

## Installing with a data disk

The installer (the live ISO's Anaconda) has a **Data disk** step after the
storage steps. It can keep home folders, Flatpak apps, containers and swap on
a second disk, so a small system disk doesn't fill up. The iMac (a 32 GB SSD
next to a 1 TB hard disk) is the case it was made for.

- **Choosing:** pick an existing ext4, XFS or Btrfs partition that isn't on a
  disk being installed to. A partition labelled `hdd`, `data` or `quine-data`
  is preselected. Nothing on it is erased.
- **Reusing an earlier layout:** whatever is already on the partition is used
  again (`home-<user>/`, `flatpak/`, `podman-storage/`, `swapfile`). Create
  your account at first boot with the same user name as before to get your
  files back.
- **A fresh disk:** it gets `home/` (every user's home), `flatpak/` (the
  ISO's apps) and `podman-storage/`. `quine-data-disk-relabel.service` gives
  them SELinux labels at first boot.
- **How it works:**
  - The partition is mounted at `/var/hdd` (`nofail`), and its folders are
    bind-mounted into place in `/etc/fstab`.
  - The home binds have no `nofail`: if the disk is missing, boot stops
    instead of showing an empty home.
- **Code:**
  - the page is `live/anaconda-webui/` (upstream's source plus
    `steps.patch`, built in `live/Containerfile`'s `anaconda-webui` stage at
    the version Fedora ships);
  - the install step is `data-disk.ks` in `live/build.sh`;
  - the hand-made original is described in `docs/relocate-home-to-hdd.md`.

## overlay/

Files here mirror their path on the root filesystem and are baked into the
image via `COPY overlay/ /` in the Containerfile.

- `overlay/etc/...` — local/admin config. On the ostree-based image, content
  shipped here becomes the default `/etc` and is still locally overridable
  (3-way merged on upgrade), same as any package-installed `/etc` file.
- `overlay/usr/lib/systemd/...` — vendor-shipped units. `/usr` is replaced
  wholesale on each image build/upgrade, so anything here always matches the
  image and isn't meant to be hand-edited on a running system.

### overlay/etc/gitconfig

System-wide git config so every user on the box gets `main` as the default
init branch, not `master`.

### overlay/etc/systemd/system/rpm-ostree-cleanup.{service,timer}

Weekly, runs as root via systemd (not cron/sudoers): `rpm-ostree cleanup -rb`
(drops rollback deployment and any pending deployment). Enabled at build time
via `RUN systemctl enable` in the Containerfile.

### overlay/etc/systemd/journald.conf.d/size-cap.conf

Continuous 500M journal retention cap instead of a periodic vacuum job.

### overlay/usr/lib/systemd/user/disk-cleanup.{service,timer}

Weekly, runs as the user, no privilege needed: `podman system prune -af`,
`flatpak uninstall --unused -y`, clears `~/.cache`. Auto-enabled for every
user via `overlay/usr/lib/systemd/user-preset/90-quine-linux.preset` — no
manual `systemctl --user enable` needed.

### overlay/etc/xdg/kwinrc

KWin defaults for every user. The top-left hot corner that opens Overview
is off (`[Effect-overview] BorderActivate=9`). A user's own
`~/.config/kwinrc`, which System Settings writes, still overrides it.

### Graceful updates: `update-confirm`, `update-rollback`, `update-skip-rejected`, `update-failed`

Aurora's nightly update (`uupd`) stages a new system version in the
background. These scripts, all in `overlay/usr/libexec/quine-linux/`, handle
the two ways that can go wrong.

**A new version that doesn't work:**
- On the first login into a new version, `update-confirm` asks "Quine Linux
  was updated from X to Y. Is everything working?" It's started by
  `etc/xdg/autostart/quine-update-confirm.desktop` and shown with `kdialog`.
  This is the same check layer-wizard does after layering a package.
- **Keep this update** records the version in
  `~/.local/state/quine-linux/confirmed-deployment`.
- **Ask me later** asks again at the next login.
- **Roll back** asks for confirmation, then runs `update-rollback` through
  `pkexec`, which asks for an admin password. That runs
  `bootc rollback --apply` and restarts into the previous version. If the
  system image itself changed, it also records the image in
  `/var/lib/quine-linux/rejected-images`.
- A new install or new user isn't asked: their first login just records
  the current version.
- While layer-wizard has its own confirmation pending, `update-confirm`
  stays quiet, so there's never a double prompt.

**Not reinstalling a rejected image:** `update-skip-rejected` is an
`ExecCondition` of `uupd.service` (`uupd.service.d/60-quine-graceful.conf`).
It skips the nightly run while the newest image is one someone rolled back
from. Updates resume by themselves once a newer image is published. Flatpak
updates are skipped on those nights too, because uupd does both in one
run. `update-check` doesn't offer a rejected image in the update bar either
(`rejected: true`).

**Failed updates:** after uupd's own retries, `quine-update-failed.service`
(the unit's `OnFailure`) runs `update-failed`. It saves uupd's last errors,
and whether the disk was full, to
`/var/lib/quine-linux/last-update-failure.json`. `update-check` publishes
that as `lastFailure` in `update-status.json`, for the update bar. uupd
itself already notifies the user. A successful run deletes the file.

### overlay/etc/systemd/system/cs8409-intmike-power-fixup.service

Hardware-specific fixup for the iMac19,2 internal mic (see below).

## Hardware-specific patches

`docs/` and `patches/` hold write-ups and out-of-tree kernel module patches
for hardware quirks on the machines this image runs on, that don't fit
anywhere else in this repo:

- [`docs/imac19-2-mic-fix.md`](docs/imac19-2-mic-fix.md) — the internal mic
  on iMac19,2 capturing near-silence despite maxed gain; root cause, fix,
  and current verification status.
- `patches/snd-hda-codec-cs8409/` — the vendored driver source and patch
  backing that fix, built into `Containerfile`'s `kmod-builder` stage.
- [`docs/imac19-2-speaker-fix.md`](docs/imac19-2-speaker-fix.md) — the
  internal speakers on iMac19,2 producing no sound at all; investigation and
  prior-art writeup, no fix packaged yet.

## Software fork directions

Write-ups of problems found on this image that point at a fork/patch of an
upstream project, kept here before anyone's had time to act on them:

- [`docs/chromium-dbus-singleton-activation.md`](docs/chromium-dbus-singleton-activation.md)
  — not started: Chromium lacks D-Bus activation, so KDE + Flatpak can't
  dedupe a slow-starting launch, and repeated launcher clicks stack up full
  duplicate browser instances instead of forwarding to the existing one.
