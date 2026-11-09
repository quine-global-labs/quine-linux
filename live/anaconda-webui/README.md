# anaconda-webui: the Data disk step

quine-linux's additions to Anaconda's web UI
([rhinstaller/anaconda-webui](https://github.com/rhinstaller/anaconda-webui)):

- `src/components/datadisk/` is the **Data disk** page. It's copied into
  upstream's source tree as is.
- `steps.patch` adds the page to the wizard, after the storage steps
  (`src/components/steps.js`).

`live/Containerfile`'s `anaconda-webui` stage clones upstream at the version
Fedora currently ships (`dnf repoquery anaconda-webui`), adds these files and
runs upstream's `make install`. The final stage replaces Fedora's
`/usr/share/cockpit/anaconda-webui` with the result, after checking that the
versions match.

The page writes the choice to `/run/quine-data-disk.json`, and
`data-disk.ks` (`live/build.sh`) applies it after installing.

**When Fedora moves to a new anaconda-webui:** if `steps.patch` no longer
applies, the stage fails. To fix it, clone the new tag, add the two lines
to `src/components/steps.js` by hand, and save `git diff` as `steps.patch`.
