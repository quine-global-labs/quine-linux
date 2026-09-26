# quine-linux

Quine distro of Linux based on uBlue Aurora

## Building

`Containerfile` builds a custom bootc image on top of `ghcr.io/ublue-os/aurora:stable`,
layering in everything under `overlay/`:

```sh
podman build -t quine-linux -f Containerfile .
```

An ISO can then be generated from the built image with `bootc-image-builder`.

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
