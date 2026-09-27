# Provenance: vendored `anaconda-webui` source

## Origin

- Upstream project: [`rhinstaller/anaconda-webui`](https://github.com/rhinstaller/anaconda-webui)
  (Anaconda's Cockpit/React web UI, shipped in Fedora as the `anaconda-webui`
  package).
- **Pinned release:** tag `86`, commit
  `cd472cd02dec354bb9df463b8724b16bad27202f` ("Show "Installation completed"
  instead of "Initializing..." after reboot").
- **Date vendored:** 2026-09-27.
- `vendor/` is `git archive 86` verbatim. Local changes are made directly in
  `vendor/` and show up in this repo's history against that baseline.

## Submodules not vendored

Upstream has two git submodules, which `git archive` leaves out:

- `node_modules` -> [`rhinstaller/node-cache`](https://github.com/rhinstaller/node-cache),
  gitlink `99a26de1065b0c39bad3d11197a37e1a8b0edb99`. This is the npm package
  cache the build needs; upstream's `tools/node-modules` fetches it by that
  sha at build time. The sha is recorded as `NODE_MODULES_REF` in
  `installer/Containerfile`, which recreates the gitlink before building.
- `test/reference` (pixel-test screenshots): not needed to build.

The build also fetches cockpit's shared `pkg/lib` at the commit pinned in
`vendor/Makefile` (`COCKPIT_REPO_COMMIT`). So building needs network access
to GitHub; it is not offline-capable.

## How it's built and used

`installer/Containerfile`'s `anaconda-webui` stage runs upstream's own
`make install` (what the Fedora RPM's `%install` runs) and the final stage
copies the result over stock Fedora `anaconda-webui`, which is still
installed for its dependencies. Verified at vendoring time: the produced file
set matches Fedora's `anaconda-webui-86-1.fc46` file list exactly.

## Updating to a new upstream release

1. Replace `vendor/` with `git archive <new tag>` of upstream, then re-apply
   local changes (diff `vendor/` against the old baseline first to see them).
2. Update `ANACONDA_WEBUI_VERSION` and `NODE_MODULES_REF` in
   `installer/Containerfile` (`git ls-tree <new tag> node_modules`).
3. Update the tag, commit and date above.
