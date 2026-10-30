# Patched Anaconda installer

How to get a forked/patched Anaconda into the install ISO, instead of the
stock Fedora one.

## Why this needs a second container

`task build-iso` (the existing task) builds the ISO straight from RPMs via
bootc-image-builder's `iso` type -- there's no separate place to inject a
custom Anaconda build.

bootc-image-builder's `bootc-installer` type is different: it takes **two**
containers -- an "installer environment" container that has Anaconda
installed in it, and (via `--installer-payload-ref`) the actual OS to
install. The installer environment is just a container you build with a
`Containerfile`, so that's the hook: build your own installer image with
your patched Anaconda in it instead of Fedora's, and point
bootc-image-builder at it.

`installer/Containerfile` in this repo is that installer environment. It's
unrelated to the quine-linux OS image built by the root `Containerfile` --
Anaconda only exists in this side container, never in the installed system.

## Which Anaconda to patch

Fedora's `anaconda` package resolves to one of two UIs depending on the
image's release-identity package: `anaconda-gui` (old GTK hub-and-spoke) on
server/basic/IoT identities, `anaconda-webui` (Cockpit + React/PatternFly)
everywhere else. All current upstream feature work happens on the WebUI, so
that's the one to patch: https://github.com/rhinstaller/anaconda-webui,
vendored in this repo at `installer/anaconda-webui/vendor/` (see
`installer/anaconda-webui/PROVENANCE.md` for the pinned release and how to
update it).

`installer/Containerfile` depends on `anaconda-webui` explicitly (not just
the bare `anaconda` metapackage) so the UI doesn't depend on incidentally
matching a release-identity package.

## Workflow

1. **Edit** the web UI directly in `installer/anaconda-webui/vendor/`
   (mostly `src/`, React/PatternFly). Your changes are this repo's diff
   against the vendored upstream release.
2. **Build the installer image and ISO:**
   ```sh
   task build-installer-iso
   ```
   `installer/Containerfile` builds the vendored source with upstream's own
   `make install` (the same step Fedora's RPM runs), installs stock Fedora
   `anaconda-webui` for its dependencies, and copies the built files over
   it. The ISO lands in `output/bootiso/install.iso`.
3. **Iterate:** edit, rerun. The build stage is cached until something in
   `vendor/` changes.

The build stage runs on the build host's native architecture (the output is
platform-independent web assets and scripts), and needs network access: it
fetches upstream's npm package cache and cockpit's shared lib from GitHub.

## Caveats

- The installer base tracks Fedora rawhide, while `vendor/` is pinned to one
  upstream release. If rawhide's `anaconda-webui` moves well ahead, its
  dependencies (e.g. `anaconda-core`) may stop matching the vendored UI;
  re-vendor a newer release (see PROVENANCE.md) or pin the base to a
  stable Fedora release.
- The installer environment's Fedora release should stay close to whatever
  release the actual `quine-linux` image (and thus the ISO's kernel/dracut)
  is built against, to avoid mismatches between the boot environment and the
  installed system.
