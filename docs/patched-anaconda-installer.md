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
  https://github.com/philip-peterson/anaconda-webui

`installer/Containerfile` depends on `anaconda-webui` explicitly (not just
the bare `anaconda` metapackage) so the UI doesn't depend on incidentally
matching a release-identity package.

## Workflow

1. **Fork** `rhinstaller/anaconda-webui` to
   `philip-peterson/anaconda-webui` on GitHub, make your panel/control
   changes there.
2. **Get it built as an RPM your installer container can `dnf install`.**
   Recommended: a Fedora COPR project.
   - Create the COPR project `philip-peterson/quine-anaconda-webui`
     (https://copr.fedorainfracloud.org/), point it at
     `philip-peterson/anaconda-webui` (branch or a webhook), let COPR build
     it against the Fedora release Aurora currently tracks.
   - That name is already wired in as the `COPR_REPO` default in
     `Taskfile.yml` and `installer/Containerfile`. Using a different COPR
     project name means overriding `COPR_REPO=` on the `task` invocations
     below instead.
   - This publishes your fork's source and build logs on COPR's
     infrastructure (marking a project "unlisted" hides it from browsing,
     not from direct access) -- worth knowing before you push anything you
     wouldn't want visible outside this machine.
3. **Build the installer image and ISO:**
   ```sh
   task build-installer-iso
   ```
   This builds the quine-linux OS image (if needed), builds
   `installer/Containerfile` with the `philip-peterson/quine-anaconda-webui`
   COPR repo enabled, and produces `output/bootc-installer/install.iso`.
4. **Iterate:** push a change to your fork, wait for COPR to rebuild, rerun
   `task build-installer-iso` -- podman/task will rebuild the installer
   layer to pick up the new RPM.

## Local alternative (no COPR)

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
