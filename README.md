# quine-linux

Collection of system tweaks/config for this machine (Fedora Aurora, bootc/ostree).

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

## systemd/journald.conf.d/size-cap.conf

Continuous 500M journal retention cap instead of a periodic vacuum job.

```sh
sudo mkdir -p /etc/systemd/journald.conf.d
sudo cp systemd/journald.conf.d/size-cap.conf /etc/systemd/journald.conf.d/
sudo systemctl restart systemd-journald
```
