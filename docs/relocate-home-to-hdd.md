# Relocating `/var/home/ironmagma` onto the HDD (sda3)

## TL;DR

The nvme btrfs pool (`/`, `/home`, `/var` subvolumes sharing one ~23.5 GiB
partition) is ~92% full and caused a Discord SIGBUS crash (full disk cache
write — see [`hdd-partition-split-for-btrfs-pool.md`](./hdd-partition-split-for-btrfs-pool.md)
for that investigation). Breakdown of the ~20.9 GiB used:

| Location | Size |
|---|---|
| `/sysroot/ostree/repo` (the OS image itself, one deployment, not staged) | 8.4G |
| `/var/home/ironmagma` (actual `$HOME` — lives in the "home" subvolume) | 11G |
| `/var` itself (logs/cache) | 169M |

`/var/home/ironmagma` is the single biggest reclaimable chunk and is not
part of the OS image, so relocating it onto the HDD (`sda3`, mounted at
`~/hdd`, 259G free at time of writing) fixes the actual problem directly,
rather than just giving the pool more room to keep filling up
(the partition-split doc's approach).

**Not yet executed.** This must be run from a TTY after a full logout —
Claude Code itself runs from files under `$HOME`, so it cannot perform or
supervise this live; there is no assistant available mid-procedure. Follow
this doc standalone.

## Why this is trickier than the existing flatpak bind mount

`/var/lib/flatpak` is already bind-mounted from the HDD
(`/var/home/ironmagma/hdd/flatpak`), which works because the *bind mount's
source* is nested a level below where the HDD itself is mounted, and none of
that nesting is itself the target of another mount.

Relocating `$HOME` is different: the HDD (`sda3`) is currently mounted
**inside** the very directory (`/var/home/ironmagma`) we want to replace
with a bind mount. If we tried to keep that nesting and just bind-mount some
subdirectory of the HDD back onto `/var/home/ironmagma`, the new mount would
sit *on top of* the path leading to the HDD mount itself — Linux mount
shadowing means the original `sda3` mount (and the flatpak bind nested
inside it) would become unreachable via the normal path afterward, even
though it's technically still mounted underneath. **This is why the HDD's
mount point must first move to a path that is a sibling of `/var/home/ironmagma`,
not a descendant of it** (e.g. `/var/hdd` instead of
`/var/home/ironmagma/hdd`).

## Pre-flight checks done (safe, no changes made)

- Grepped for hardcoded references to the old `/var/home/ironmagma/hdd`
  path across `~/Code` and `~/.config`: no scripts, systemd units, or build
  configs depend on it. Only two trivial, non-blocking references found:
  - `~/.config/spectaclerc` — Spectacle's screenshot save folder
  - `~/.config/session/dolphin_dolphin_dolphin` — a remembered Dolphin tab
  Both just need re-pointing after the move; neither blocks anything.
- Current relevant `/etc/fstab` lines:
  ```
  UUID=a45a95fa-805f-43f2-bc32-8da8970c1b91 /var/home/ironmagma/hdd ext4 defaults,nofail 0 2
  /var/home/ironmagma/hdd/flatpak /var/lib/flatpak none bind,nofail 0 0
  ```

## Plan

### Phase 0 — from the normal desktop session, before logging out

1. **Take a real backup of `/var/home/ironmagma`** to somewhere independent
   of this machine's disks (external drive, another machine, cloud). The
   copy made in Phase 2 is *not* a substitute for this — it lands on the
   same physical HDD this plan is otherwise trusting; a real backup is the
   actual safety net if something goes wrong mid-procedure.
2. Note down anything you'd hate to lose track of that isn't obviously
   under `$HOME` in the usual places (e.g. GPG/SSH agent state, browser
   session you care about) so you can sanity-check it post-move.

### Phase 1 — drop to a TTY

Log out of the graphical session fully (this ends the current Claude Code
session too). Switch to a TTY (Ctrl+Alt+F3) and log in as `ironmagma`.

### Phase 2 — move the HDD's mount point out from under `$HOME`

```bash
sudo mkdir -p /var/hdd
sudo umount /var/lib/flatpak
sudo umount /var/home/ironmagma/hdd
```

Edit `/etc/fstab`, changing:
```
UUID=a45a95fa-805f-43f2-bc32-8da8970c1b91 /var/home/ironmagma/hdd ext4 defaults,nofail 0 2
/var/home/ironmagma/hdd/flatpak /var/lib/flatpak none bind,nofail 0 0
```
to:
```
UUID=a45a95fa-805f-43f2-bc32-8da8970c1b91 /var/hdd ext4 defaults,nofail 0 2
/var/hdd/flatpak /var/lib/flatpak none bind,nofail 0 0
```

Then:
```bash
sudo systemctl daemon-reload
sudo mount /var/hdd
sudo mount /var/lib/flatpak
ls /var/hdd          # sanity check: should show the same old contents, incl. flatpak/
```

Home directory content is untouched by this phase — `/var/home/ironmagma`
still has its old (now unused) empty `hdd/` placeholder directory in it,
harmless, cleaned up later.

### Phase 3 — copy `$HOME` onto the HDD

Nothing is mounted inside `/var/home/ironmagma` anymore at this point, so
this is a plain, non-nested copy:

```bash
sudo rsync -aHAX --info=progress2 /var/home/ironmagma/ /var/hdd/home-ironmagma/
```

`-aHAX` preserves permissions, hardlinks, ACLs, and xattrs (including
SELinux labels stored as `security.selinux` xattrs — matters for `.ssh`
permissions and SELinux contexts).

### Phase 4 — verify before touching the original

```bash
sudo diff -rq /var/home/ironmagma /var/hdd/home-ironmagma
```
Should report no differences. Do not proceed if it does.

### Phase 5 — swap

```bash
sudo mv /var/home/ironmagma /var/home/ironmagma.old
sudo mkdir /var/home/ironmagma
sudo chown ironmagma:ironmagma /var/home/ironmagma
```

Add to `/etc/fstab`:
```
/var/hdd/home-ironmagma /var/home/ironmagma none bind 0 0
```

**Deliberately no `nofail` here**, unlike the hdd/flatpak lines. If the HDD
fails to come up, we want boot to visibly stop and demand attention, not
silently hand you a freshly-empty `/var/home/ironmagma` that looks like your
whole home directory vanished.

```bash
sudo systemctl daemon-reload
sudo mount /var/home/ironmagma
ls -la /var/home/ironmagma        # should show all the familiar dotfiles/dirs
sudo restorecon -R /var/home/ironmagma   # SELinux label safety net
```

### Phase 6 — test before rebooting

```bash
sudo -u ironmagma touch /var/home/ironmagma/.relocate-test
ls -la /var/home/ironmagma/.relocate-test
rm /var/home/ironmagma/.relocate-test
```

### Phase 7 — reboot and verify for real

Reboot, log into the normal graphical session, and check:
- SSH agent / keys work
- `git` works in `~/Code`
- Dropbox resumes syncing
- 1Password unlocks
- Browser profile intact
- Claude Code itself starts (it lives under `$HOME` — if this doc is
  readable again from inside a working Claude Code session, that's a good
  sign the move succeeded)
- Re-point Spectacle's save folder and check the stale Dolphin tab (see
  pre-flight checks above)

### Phase 8 — only once fully confident (a few days of normal use)

**Nothing before this step actually frees space on the nvme pool** — until
now we've only relocated and kept a full fallback copy. This is the step
that does it:

```bash
sudo rm -rf /var/home/ironmagma.old
```

This drops nvme pool usage from ~92% to roughly ~43%.

### Optional cleanup

- `/var/home/ironmagma/hdd` no longer exists as a mountpoint (it's `/var/hdd`
  now); if you want a convenience path at the old location, a plain symlink
  works fine since nothing is mounted there anymore:
  ```bash
  ln -s /var/hdd /var/home/ironmagma/hdd
  ```

## Open risks / unknowns

- Whether SELinux contexts translate perfectly onto ext4 via rsync `-X` —
  `restorecon -R` in Phase 5 is the safety net, but not independently
  verified here.
- Making the home bind mount required (no `nofail`) means a failed/missing
  HDD blocks login entirely rather than degrading gracefully. This is a
  deliberate choice (see Phase 5) but worth revisiting if the HDD turns out
  to be less reliable than expected.
- The still-unexplained podman `system df` discrepancy (reports 2.412GB of
  "reclaimable" images with an empty image list, real 2.3G sitting in
  `~/.local/share/containers/storage/overlay`, and 9 volumes that return
  `Permission denied` on inspection) was not resolved — separate from this
  plan, and worth checking whether those volumes belong to a still-used
  distrobox/toolbox environment before ever running `podman system reset`.

---
*Written 2026-09-26. No steps executed yet.*
