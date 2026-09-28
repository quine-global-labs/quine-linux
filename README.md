# quine-linux

Quine distro of Linux based on uBlue Aurora

## Building

The image is built in two stages:

- **Stage 0: `stage-0/`**, a git submodule holding our fork of
  [Aurora](https://github.com/ublue-os/aurora). It's built with Aurora's own
  `just build` into `localhost/aurora:stable`. Changes that have to happen
  *inside* Aurora's build (its package set, build scripts, the Kinoite base
  it starts from) go here, as commits on the fork; bump the submodule to ship
  them. Needs a Linux host with buildah, cpp, just (>= 1.46), skopeo, jq, yq
  and cosign.
- **Stage 1: `Containerfile`**, which builds the quine-linux bootc image on
  top of stage 0, layering in everything under `overlay/`, plus a
  `kmod-builder` stage that compiles the CS8409 mic-fix kernel module (see
  [Hardware-specific patches](#hardware-specific-patches) below). Anything a
  `RUN` step on top of Aurora can do belongs here, not in stage 0.

Clone with `git clone --recurse-submodules`, or run
`git submodule update --init` in an existing checkout.

[`Taskfile.yml`](Taskfile.yml) (requires [`task`](https://taskfile.dev)) is
the supported way to drive all of this — run `task` with no arguments to
list what's available. Notably:

- `task build-base` — builds stage 0. It's skipped when `stage-0/` is
  unchanged and the image exists. Run `task build-base --force` to rebuild
  anyway, e.g. to pick up upstream kernel and package updates, which Aurora's
  build resolves at build time.
- `task build-image` — builds stage 0 if needed, then stage 1. To skip stage 0
  and build on stock upstream Aurora (the only option on macOS), pass
  `BASE_IMAGE=ghcr.io/ublue-os/aurora:stable`. Builds locally, as root, with podman, or
  docker if podman isn't installed (force either with
  `CONTAINER_RUNTIME=docker|podman`). Every task below works with either;
  under docker, images are copied via skopeo into a
  `quine-containers-storage` volume for `bootc-image-builder` to read.
- `task build-iso` — builds a bootable install ISO from that image via
  `bootc-image-builder`, landing in `output/bootiso/install.iso`.
- `task build-installer-iso` — builds an install ISO using a custom
  Anaconda installer environment (`installer/Containerfile`) instead of
  stock Fedora's, landing in `output/bootc-installer/install.iso`. See
  [`docs/patched-anaconda-installer.md`](docs/patched-anaconda-installer.md)
  for forking/patching Anaconda itself.
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
(cd stage-0 && sudo just build --image aurora --tag stable --flavor main)
sudo podman build -t quine-linux -f Containerfile .
```

An ISO can then be generated from the built image with `bootc-image-builder`
(`ghcr.io/osbuild/bootc-image-builder`; the project now lives in
[osbuild/image-builder](https://github.com/osbuild/image-builder), and the old
`quay.io/centos-bootc/bootc-image-builder` image is no longer updated).

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
