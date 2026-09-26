# quine-linux

Quine distro of Linux based on uBlue Aurora

## systemd/user/disk-cleanup.{service,timer}

Weekly, runs as the user, no privilege needed: `podman system prune -af`,
`flatpak uninstall --unused -y`, clears `~/.cache`.

```sh
cp systemd/user/disk-cleanup.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now disk-cleanup.timer
```

## systemd/system/rpm-ostree-cleanup.{service,timer}

Weekly, runs as root via systemd (not cron/sudoers): `rpm-ostree cleanup -rb`
(drops rollback deployment and any pending deployment).

```sh
sudo cp systemd/system/rpm-ostree-cleanup.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now rpm-ostree-cleanup.timer
```

## overlay/

Files here mirror their path on the root filesystem, meant to be baked into
the image (e.g. `COPY overlay/ /` in a future Containerfile). Until then,
apply manually:

```sh
sudo cp overlay/etc/gitconfig /etc/gitconfig
```

### overlay/etc/gitconfig

System-wide git config so every user on the box gets `main` as the default
init branch, not `master`.

## systemd/journald.conf.d/size-cap.conf

Continuous 500M journal retention cap instead of a periodic vacuum job.

```sh
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp systemd/journald.conf.d/size-cap.conf /etc/systemd/journald.conf.d/
sudo systemctl restart systemd-journald
```
