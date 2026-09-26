# Splitting `~/hdd` (sda3) to grow the root btrfs pool

> **Superseded as the primary fix.** A later investigation found the actual
> largest reclaimable consumer on the pool is `/var/home/ironmagma` itself
> (11G), not something that needs more pool capacity to fix — see
> [`relocate-home-to-hdd.md`](./relocate-home-to-hdd.md), which frees that
> space directly instead of growing the pool to make room for it. This doc
> is kept for reference / as a fallback if more headroom is still wanted
> later.

## TL;DR

The root filesystem is a bootc/Fedora Atomic (uBlue Aurora) install where `/`,
`/home`, and `/var` are separate **btrfs subvolumes on the same physical
partition** (`nvme0n1p3`, 23.5 GiB total). That pool is at ~89% full with only
~1.7 GiB free, which caused a Discord crash (SIGBUS while writing its disk
cache — see [Trigger](#trigger)). `/var` itself only holds ~169 MiB, so the
actual space pressure lives elsewhere in the shared pool (likely `/home` or
ostree deployment data), not in `/var` specifically — **that root cause
should still be identified and possibly cleaned up for free before doing any
of this**, since this plan doesn't fix the cause, it just gives the pool more
room.

The plan: shrink the ext4 partition on the secondary HDD (`sda3`, mounted at
`~/hdd`) to free ~100 GiB at the end of the disk, create a new partition
(`sda4`) in that space, then add `sda4` as a second device to the nvme btrfs
pool (`btrfs device add` + `btrfs balance`).

**Not yet executed** — this doc captures the plan and exact numbers as of
the date below, for when this project picks it back up.

## Hardware / software identification

- Distro: Aurora (uBlue/Fedora Atomic, bootc-based), KDE Plasma
- Kernel: `7.1.8-200.fc44.x86_64`
- Root filesystem layout (`/etc/fstab`):
  ```
  UUID=8d071437-8c47-4669-94a5-4a669a3b3b66 / btrfs subvol=root,compress=zstd:1,ro
  UUID=8d071437-8c47-4669-94a5-4a669a3b3b66 /home btrfs subvol=home,compress=zstd:1
  UUID=8d071437-8c47-4669-94a5-4a669a3b3b66 /var btrfs subvol=var,compress=zstd:1
  UUID=a45a95fa-805f-43f2-bc32-8da8970c1b91 /var/home/ironmagma/hdd ext4 defaults,nofail
  /var/home/ironmagma/hdd/flatpak /var/lib/flatpak none bind,nofail
  ```
  `/`, `/home`, and `/var` are three subvolumes of **one** btrfs partition
  (`nvme0n1p3`), so they share a single free-space pool.
- `nvme0n1p3` (the OS btrfs pool): 23.5 GiB total, 20.9 GiB used, 1.7 GiB
  free (89% full) at time of writing.
- `sda` (secondary HDD, GPT): `sda1` EFI System, `sda2` Apple APFS (leftover
  from a prior macOS install — unused, not touched by this plan), `sda3`
  Microsoft basic data (ext4), which is the **last** partition on the disk.
- `sda3` (`~/hdd`, ext4): 456.9 GiB total, 174.5 GiB used, 259.2 GiB free
  (41% full) at time of writing. Already bind-mounted at `/var/lib/flatpak`
  in fstab, so all flatpak app data already lives here.

## Trigger

```
Sep 26 01:12:11 imac audit[11852]: ANOM_ABEND ... comm="CacheThread_Blo" ... sig=7 res=1
Sep 26 01:12:11 imac systemd-coredump[20186]: Process 11852 (Discord) ... terminated abnormally with signal 7/BUS, processing...
Sep 26 01:12:12 imac systemd-coredump[20187]: Cannot store coredump of 11852 (Discord): No space left on device
```

Discord (Flatpak) crashed with SIGBUS on a Chromium cache thread — classic
symptom of a memory-mapped cache file hitting a full filesystem — and the
subsequent coredump couldn't even be written, confirming the pool was
nearly out of space.

## Why not just relocate `/var` wholesale

Considered and rejected: bind-mounting all of `/var` (not just
`/var/lib/flatpak`) onto the HDD, the same way flatpak already is.

- `/var`'s own subvolume is only ~169 MiB — moving it wouldn't free
  meaningful space, since the 89%-full number is pool-wide, not `/var`-only.
- `/var` holds state systemd needs very early in boot (NetworkManager
  profiles, container/podman storage, machine state). The existing
  `/var/lib/flatpak` bind mount is `nofail` and only needed well after boot;
  making all of `/var` depend on an external/secondary disk being ready in
  time is a much larger risk — a slow-to-init or disconnected HDD could
  leave the system unable to start normal services, not just unable to
  launch flatpak apps.

Growing the existing btrfs pool (this doc's plan) avoids that: the pool
gains capacity, but nothing critical becomes dependent on the HDD being
present at early boot in a way it isn't already.

## Plan

### 0. Prerequisites

- Back up anything on `sda3` you can't afford to lose. This is a resize of
  an in-use partition holding 174.5 GiB of real data (including all flatpak
  app data), not a no-risk operation.
- `sudo` needs an interactive password/TTY in this environment — these
  steps must be run from a real terminal, not automated non-interactively.
- `/var/lib/flatpak` (on `sda3`) is held open by far more than just Discord
  — confirmed via `fuser -vm /var/lib/flatpak`: Chrome, 1Password, Dolphin,
  Konsole, KWrite, `xdg-desktop-portal`, and Plasmashell all had handles
  into it. A live unmount from inside the desktop session isn't realistic;
  do this from a plain TTY (Ctrl+Alt+F3) after logging out of the
  graphical session, not from a terminal window inside it.

### 1. Shrink `sda3` (ext4) to free ~100 GiB at the end

From a TTY, logged out of the graphical session:

```bash
sudo umount /var/lib/flatpak
sudo umount /var/home/ironmagma/hdd

# required before any resize — stop here if this reports errors
sudo e2fsck -f /dev/sda3

# shrink filesystem well below the future partition size for safety margin
# (current usage 174.5 GiB; new partition will be ~356.9 GiB)
sudo resize2fs /dev/sda3 350G

# shrink the partition to match, using parted's "from the end" syntax —
# sda3 is the last partition on the disk, so this leaves clean trailing
# free space
sudo parted /dev/sda resizepart 3 -100GiB
```

### 2. Create `sda4` in the freed space

```bash
sudo parted /dev/sda unit GiB print
# note sda3's new End value, then:
sudo parted /dev/sda mkpart primary <sda3-new-End> 100%
```

### 3. Verify before doing anything else

```bash
sudo mount /var/home/ironmagma/hdd
sudo mount /var/lib/flatpak
lsblk -f
```

Reboot once, log back into the normal graphical session, and confirm
flatpak apps (Discord included) still launch fine before proceeding to
step 4. Don't chain step 4 onto the same session — verify this part is
solid first.

### 4. Add `sda4` to the nvme btrfs pool

Not yet detailed to exact commands — high-level:

```bash
sudo btrfs device add /dev/sda4 /
sudo btrfs balance start /
```

Open questions to resolve before running this step:
- Balance filters, if any, to control how data gets distributed rather than
  spread arbitrarily across both devices.
- Whether to convert to a specific btrfs profile (e.g. keep `single` data
  profile across both devices, vs. something with redundancy) — plain
  `single` means losing `sda4` (or the whole `sda` disk) can take out data
  that landed there, including parts of `/`, `/home`, or `/var`. This
  raises the HDD from "flatpak-only dependency" to "part of the core OS
  pool" — a real increase in blast radius that should be a deliberate
  choice, not a default.

## Open risks / unknowns

- Exact root cause of the pool being 89% full was never identified in the
  session that produced this doc — only ruled out `/var` itself (169 MiB).
  Should check `rpm-ostree status` / `bootc status` for stale deployments
  and `du` on `/home` before assuming this resize is even necessary; some
  or all of the space may be reclaimable for free.
- `sda2` (Apple APFS, unused leftover from a prior macOS install on this
  disk) was not investigated as an alternative space source — reclaiming it
  instead of shrinking `sda3` was not evaluated.
- Once `sda4` joins the btrfs pool, disk health/failure handling for `sda`
  matters a lot more than it does today. Not yet decided whether to monitor
  it differently once it's part of the OS pool.

---
*Written 2026-09-26, based on a live investigation of a Discord crash caused
by the pool being full. No resize has been performed yet.*
