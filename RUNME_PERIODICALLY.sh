#!/usr/bin/env bash
# Periodic disk cleanup for /var/home (nvme0n1p3, 24G btrfs).
# The command that actually mattered on 2026-09-25: podman system prune -af (freed 4.5G).
# Everything else here is safe/idempotent maintenance layered on top.
set -e

echo "== Before =="
df -h /var/home

echo "== podman: prune unused images/containers/build cache (this is the one that matters) =="
podman system prune -af

echo "== ostree: drop rollback deployment =="
sudo rpm-ostree cleanup -rb

echo "== journal: keep last 3 days =="
sudo journalctl --vacuum-time=3d

echo "== flatpak: remove unused runtimes/extensions =="
flatpak uninstall --unused -y

echo "== user cache: clear (safe, regenerates) =="
rm -rf ~/.cache/*

echo "== After =="
df -h /var/home
