# How Quine software reaches people, and updates

Quine Linux and the apps around it (Hyper, Quintodrome, KeyMaker, our own
RPMs) are built on our forge and published to a handful of public hosts.
This is the map: where each thing is downloaded from, what signs it, and how
it updates. How the hosts themselves run is in petersweb-infra's docs.

## The hosts

The forge (`forge.in.quineglobal.com`) is tailnet-only; everything people
outside download comes from one of these.

| Host | What | Notes |
|---|---|---|
| `registry.quineglobal.com` | Quine Linux's OS image (`registry.quineglobal.com/quine-linux:latest`) | Pull-only door to the forge's container registry; installed systems update from it |
| `flatpak.quineglobal.com` | Quine Linux's Flatpak repo | OSTree, collection `com.quineglobal.Flatpak`, branch `stable`, signed with `D8A7EB83CA7D77EFF171D12A98815AFF3222E41B`. Every install has it as the `quine` remote (`overlay/etc/flatpak/remotes.d/quine.flatpakrepo`) |
| `packages.quineglobal.com` | apt and dnf repos (Hyper's, for now) | `/hyper/deb` (suites `stable`, `canary`), `/hyper/rpm/{stable,canary}/`, signed with `06249465F4C6A0A851211266772797169CE1D647` (`/quine-packages.asc`). Filled from each GitHub release of Hyper by itself |
| `git.quineglobal.com` | Read-only git, including the Homebrew tap (`quine-global/homebrew-tap`) | The tap holds the `quine-hyper` and `quintodrome` casks and the Sparkle appcasts (`appcasts/*.xml`) the Mac apps read |
| `forge.in.quineglobal.com/<owner>/<repo>/releases/download/…` | Release files of public repos on the forge | The one public path on the forge: Quintodrome's appcasts and cask link here |
| `s3.quineglobal.com` | Quine Linux ISOs and disk images (`quine-linux/releases/<tag>/`), and the Flatpak repo's storage | Anonymous download on `releases/` and `flatpak/` only |
| `github.com/quine-global/*` | Mirrors of our repos; Hyper's releases | Hyper's installers and packages are downloaded from GitHub releases |
| `linux.quineglobal.com` | The website | |

## What updates how

| What | Installed from | Updates |
|---|---|---|
| Quine Linux itself | registry (bootc) | Nightly, by Aurora's `uupd` (README "Graceful updates"). To be replaced: app updates already don't depend on it |
| Flatpak apps (ours and Flathub's) | `flatpak.quineglobal.com`, Flathub | **When opened**: `quine-app-updates` checks the app's repo and installs a newer version before it starts (README "App updates on launch") |
| Our RPM apps (layer-wizard, dnf-package-store, swap-watchdog) | the forge's `quine` RPM group, built into the image | With the image |
| Hyper, macOS | Homebrew cask `quine-hyper` or the dmg | Sparkle, from the tap's `hyper-*.xml` appcasts; downloads in the background and installs when Hyper quits |
| Hyper, Linux | `packages.quineglobal.com` (apt/dnf), the AppImage, or the Homebrew cask | The package manager; Hyper's notification shows the command (`app/utils/linux-install.ts` in Hyper). Planned: the Quine Flatpak repo, so `quine-app-updates` covers it |
| Hyper, Windows | the installer from GitHub releases | Hyper's own updater, against `hyper.quineglobal.com/update` |
| Quintodrome, macOS | Homebrew cask `quintodrome` or the zip | Sparkle, from the tap's `quintodrome-*.xml` appcasts; downloads from the forge's public release path |
| KeyMaker | `flatpak.quineglobal.com` (preinstalled) | When opened, like every Flatpak |

## Signing keys (public halves)

- **Flatpak repo:** `D8A7EB83CA7D77EFF171D12A98815AFF3222E41B` (in the
  `.flatpakrepo` file).
- **apt/dnf repos:** `06249465F4C6A0A851211266772797169CE1D647`,
  "Quine Global Packages", at `https://packages.quineglobal.com/quine-packages.asc`.
- **Sparkle (Hyper and Quintodrome):** Ed25519, `SUPublicEDKey`
  `PasstyI8TVmTzH+i0ICnqwn2Z6BpqwOjcMwpyKhSFXk=` in each app's Info.plist.
  The two apps share the key; their appcasts are separate.

## Publishing to the Flatpak repo

An app's CI builds its Flatpak and adds it to the repo: KeyMaker's
`.forgejo/workflows/flatpak.yml` and `.forgejo/flatpak-publish.sh` (in a
privileged Fedora container, since flatpak-builder needs bubblewrap; once per
architecture). Each run downloads the whole repo from S3, adds the build,
signs it and uploads it again, so two apps publishing at the same moment
could lose one's upload: the `quine-flatpak-repo` concurrency group only
covers runs of the same workflow. With more apps, a single publisher that
takes each app's `.flatpak` and imports them one at a time should replace it.

An app opts out of updating on launch with
`flatpak build-finish --metadata=X-Quine=UpdateOnLaunch=false`.

## Gaps

- Hyper isn't in the Flatpak repo yet (its only Flatpak was a standalone
  `.flatpak` file on one release, which nothing updates).
- Quine Linux still updates itself nightly through `uupd`; the plan is to
  move off it.
- The Mac apps check for updates once a day (Sparkle's schedule), not when
  they're opened.
