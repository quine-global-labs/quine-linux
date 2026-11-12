# CLAUDE.md: quine-linux

Quine Linux: a bootc image on our fork of Universal Blue's Aurora (KDE,
Fedora Kinoite underneath), with a live ISO that is also the installer.
[README.md](README.md) explains the build, the overlay and releases;
[GUIDELINES.md](GUIDELINES.md) the build/CI conventions shared with our
other apps. This file is what you'd otherwise rediscover the hard way.

## Where things are

- **Two repos build the image.** `quine-global-labs/aurora` (the fork,
  published as `forge.in.quineglobal.com/quine-global-labs/aurora:stable`
  and `:stable-arm64`) for changes *inside* Aurora's build; this repo's
  `Containerfile` for everything a `RUN` on top can do. Prefer this repo.
- **Published as** `forge.in.quineglobal.com/quine-global-labs/quine-linux`
  (`latest`, `latest-arm64`, date and commit tags). Installed systems follow
  `registry.quineglobal.com/quine-linux:latest` (the same image, a pull-only
  name). There's one channel: every build of `main` reaches every machine;
  release tags only make downloads and a Forgejo release.
- **The live ISO** (`live/`): `live/Containerfile` + `build.sh` turn the image
  into a live system; `titanoboa-build-iso.sh` is titanoboa's script with one
  marked change (MokManager in `EFI/BOOT/`). The installer is Anaconda's web
  UI with our **Data disk** step (`live/anaconda-webui/`, built from
  upstream's source at Fedora's version plus `steps.patch`).
- **Kickoff** (the start menu) is rebuilt from our plasma-desktop fork,
  branch `quine-v<Plasma version>`, which the fork's rebase workflow makes
  for each new Plasma. If it hasn't, the build stops and says so.
- **libtaskmanager** (the task manager's models, in plasma-workspace) is
  rebuilt with `taskmanager/startup-feedback.patch`, so the launch spinner
  follows the app's systemd unit (README "Launch feedback"). `taskmanager/
  build.sh` takes Fedora's source RPM of the installed version; if a new
  Plasma moves the code, the patch stops applying and the build says so.
- **Our apps** (layer-wizard, dnf-package-store, swap-watchdog) come from the
  forge's `quine` RPM group, built by each app's own CI; a fix to one reaches
  the image on the next build. KeyMaker comes as a Flatpak from our repo,
  flatpak.quineglobal.com.
- `installer/` and `output/` are local leftovers, not part of the build.

## CI (`.forgejo/workflows/`)

- `iso.yml`: every push to `main`, every `v*` tag, daily at 07:00 UTC. Builds
  amd64 on `runner-x86-linux` (zeus VM) and arm64 on `runner-arm64-linux`
  (Tart VM on the Mac mini): image, qcow2, live ISO, uploads to MinIO
  (`s3.quineglobal.com`, bucket `quine-linux`). A build takes ~3 hours.
  Concurrency is per ref: a push to `main` cancels the running `main` build,
  not a tag build.
- Put `[skip ci]` in a commit that can't change the image (docs, the VM
  test), or it costs a 3-hour build.
- `release.yml`: tags `main` (README "Releasing"). `vm-test.yml`: boots an
  ISO on zeus's VM 107 ([docs/VM_TEST.md](docs/VM_TEST.md)).
- Build steps run under `retry-on-network-error.sh` (retries on dropped
  fetches and on 30 minutes of silence); base-image pulls have a 60-minute
  limit.

## Gotchas

- **The runners are NixOS:** no `/bin/bash`; scripts use
  `#!/usr/bin/env bash`.
- **No short image names** in Containerfiles: `docker.io/library/node:22`,
  not `node:22`. The runners' podman asks which registry a short name means,
  and in CI nothing answers.
- **Disk space:** podman stages whole images in `/var/tmp`; on the arm64
  runner that's the 54 GB root disk, separate from the 49 GB containers
  disk. Jobs clear killed builds' leftovers at start and end.
- **os-release:** we set `NAME`/`PRETTY_NAME` to Quine Linux but keep
  `ID=aurora` and `VARIANT_ID`: Universal Blue's tooling (ujust, uupd) and
  the Anaconda profile (`os_id`) key on them.
- **The ISO is UEFI-only** (like Aurora's); VMs need OVMF/"Enable EFI".
- **Secure Boot:** the installer queues our MOK for enrollment; the next boot
  of anything with shim must find MokManager beside shim, or it loops.
- **The forge is tailnet-only** (`forge.in.quineglobal.com`, SSH on 2200).
  MinIO's public name resolves to the forge VM directly on the tailnet; off
  it, it goes through mainframe at Hetzner and is much slower.

## Testing a change

- On a Quine Linux machine: `task test:stage` / `task test:boot`, and
  `task revert` to undo.
- On a VM: Actions → **VM test** (or `task test:vm TAG=…`) puts an ISO on
  zeus's VM 107 and waits for its guest agent. VM 107 has a second 100 GB
  disk with an ext4 partition labelled `data`, for the Data disk step. To
  look at the screen: on zeus, `vmvnc 107 capture /tmp/x.png`.

## Pushing

Commit, then push to the forge first (`forge` remote), then GitHub (`github`
remote): GitHub is a mirror, and a push that loses the race to it fails with
"cannot lock ref"; check both show the same SHA.
