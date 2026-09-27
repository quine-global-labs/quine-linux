# Patched Anaconda installer

How to get a forked/patched Anaconda into the install ISO, instead of the
stock Fedora one.

## Why this needs a second container

`task build-iso` (the existing task) builds the ISO straight from RPMs via
bootc-image-builder's `iso` type -- there's no separate place to inject a
custom Anaconda build.

bootc-image-builder's `bootc-installer` type is different: it takes **two**
containers -- an "installer environment" container that has Anaconda
installed in it, and (via `--bootc-installer-payload-ref`) the actual OS to
install. The installer environment is just a container you build with a
`Containerfile`, so that's the hook: build your own installer image with
your patched Anaconda `dnf install`ed instead of Fedora's, and point
bootc-image-builder at it.

`installer/Containerfile` in this repo is that installer environment. It's
unrelated to the quine-linux OS image built by the root `Containerfile` --
Anaconda only exists in this side container, never in the installed system.

## Which Anaconda to fork

Fedora's `anaconda` package resolves to one of two UIs depending on the
image's release-identity package: `anaconda-gui` (old GTK hub-and-spoke) on
server/basic/IoT identities, `anaconda-webui` (Cockpit + React/PatternFly)
everywhere else. All current upstream feature work happens on the WebUI, so
that's the one to fork:

- https://github.com/rhinstaller/anaconda-webui, forked to
  https://github.com/philip-peterson/quine-anaconda-webui

`installer/Containerfile` depends on `anaconda-webui` explicitly (not just
the bare `anaconda` metapackage) so the UI doesn't depend on incidentally
matching a release-identity package.

## Workflow

1. **Fork** `rhinstaller/anaconda-webui` to
   `philip-peterson/quine-anaconda-webui` on GitHub, make your panel/control
   changes there.
2. **Get it built as an RPM your installer container can `dnf install`.**
   The fork's own Forgejo Actions workflow does this, as a self-hosted
   stand-in for COPR: `.forgejo/workflows/rpm.yml` runs
   `.forgejo/build-rpm.sh` in a fresh `fedora:rawhide` container (upstream's
   `make srpm`, then `rpmbuild`) and uploads the RPM to the forge's package
   registry. Setup, once:
   - Host the fork on `forge.quinefoundation.com` (Forgejo Actions only runs
     for repos on the forge), under the account the package should be
     published as -- the `quine` org by default
     (`quine/quine-anaconda-webui`).
   - Add a repo secret `RPM_UPLOAD_TOKEN`: an access token for that account
     with `write:package` scope, from a user
     allowed to publish packages for that org.
   - The result is served at
     `https://forge.quinefoundation.com/api/packages/quine/rpm.repo`,
     already wired in as the `RPM_REPO_URL` default in `Taskfile.yml`.
     Publishing under a different owner means overriding `RPM_REPO_URL=` on
     the `task` invocations below.

   Versioning: the build fetches upstream's tags so `git describe` yields
   e.g. `86.3.gabcdef0` (3 commits past upstream 86), and the Release is
   `<run number>.quine`, so each build is a new version that sorts above
   Fedora's own. The installer also gives this repo dnf `priority=10`, so
   it wins even when Fedora ships a newer upstream release.
3. **Build the installer image and ISO:**
   ```sh
   task build-installer-iso
   ```
   This builds the quine-linux OS image (if needed), builds
   `installer/Containerfile` with that repo enabled, and produces
   `output/bootc-installer/install.iso`. `RPM_REPO_URL=` (empty) builds
   with stock Fedora `anaconda-webui` instead.
4. **Iterate:** push a change to your fork, wait for its RPM workflow,
   rerun `task build-installer-iso`. The Taskfile passes a checksum of the
   repo's metadata into the build, so a newly published RPM invalidates
   the cached `dnf install` layer and gets picked up.

## Local alternative (no forge)

If you'd rather not publish the fork anywhere: build the RPM locally with
`mock` targeting the same Fedora release/arch as the installer base,
`createrepo_c` the output into a directory, and either bind-mount that
directory into `installer/Containerfile`'s build context and add it as a
`file://` repo, or drop the built RPMs into a `dnf localinstall` step. This
avoids any external service but means keeping the mock chroot's Fedora
release in sync with the installer base by hand.

## Caveats

- `anaconda-webui`'s package/dependency structure moves with each Fedora
  release; if `dnf install anaconda-webui` starts failing, check what
  `anaconda.spec.in` in your fork currently requires.
- The installer environment's Fedora release should stay close to whatever
  release the actual `quine-linux` image (and thus the ISO's kernel/dracut)
  is built against, to avoid mismatches between the boot environment and the
  installed system.
