# Built on our Aurora fork (quine-global-labs/aurora), which its own workflow
# builds and publishes to this forge's registry (`stable` for x86_64,
# `stable-arm64` for aarch64; iso.yml picks). Pass e.g.
# --build-arg BASE_IMAGE=ghcr.io/ublue-os/aurora:stable to build on stock
# upstream Aurora instead, or localhost/aurora:stable for a local build of
# the fork.
ARG BASE_IMAGE=forge.in.quineglobal.com/quine-global-labs/aurora:stable

# --- Builds the out-of-tree snd-hda-codec-cs8409 module (iMac19,2 mic fix). ---
# See docs/imac19-2-mic-fix.md and patches/snd-hda-codec-cs8409/ for the full
# story. Kept as its own stage so the build toolchain never lands in the
# final image, and built FROM the same BASE_IMAGE as the final stage so the
# kernel-devel headers installed here can never drift out of sync with the
# kernel that actually ships below.
FROM ${BASE_IMAGE} AS kmod-builder

RUN set -eux; \
    NVR="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"; \
    VERSION="$(rpm -q kernel-core --qf '%{VERSION}')"; \
    RELEASE="$(rpm -q kernel-core --qf '%{RELEASE}')"; \
    ARCH="$(rpm -q kernel-core --qf '%{ARCH}')"; \
    echo "Building snd-hda-codec-cs8409 against kernel ${NVR}"; \
    dnf install -y gcc make elfutils-libelf-devel bc perl patch; \
    dnf install -y "kernel-devel-${NVR}" \
      || dnf install -y "https://kojipkgs.fedoraproject.org/packages/kernel/${VERSION}/${RELEASE}/${ARCH}/kernel-devel-${NVR}.rpm"; \
    echo "${NVR}" > /kernel-nvr.txt

COPY patches/snd-hda-codec-cs8409/vendor/ /usr/src/snd-hda-codec-cs8409/
COPY patches/snd-hda-codec-cs8409/0001-imac19-2-force-intmike-adc-nid-fallback.patch /tmp/

# --fuzz=0: fail loudly on a context mismatch (e.g. a future kernel bump that
# shifts this file) instead of silently mis-patching.
RUN set -eux; \
    cd /usr/src/snd-hda-codec-cs8409; \
    patch -p1 --fuzz=0 < /tmp/0001-imac19-2-force-intmike-adc-nid-fallback.patch; \
    make KVER="$(cat /kernel-nvr.txt)"; \
    mkdir -p /output; \
    cp snd-hda-codec-cs8409.ko /output/

# --- Builds Kickoff (the start menu) with our update bar. ---
# Kickoff is QML packed into one plugin of plasma-desktop. This rebuilds
# just that plugin from our fork, quine-global-labs/plasma-desktop, branch
# quine-v<version>: KDE's release of the plasma-desktop version the image
# ships, plus our commits. The final stage puts it in place of the stock
# one. Like kmod-builder, it's built FROM BASE_IMAGE so it can't drift from
# the Plasma it runs on; the -devel packages are pinned to the installed
# versions (older ones come from Fedora's updates-archive). kickoff/ holds
# the CMakeLists.txt that builds the applet outside plasma-desktop's tree.
FROM ${BASE_IMAGE} AS kickoff-builder

COPY kickoff/CMakeLists.txt /tmp/kickoff/

RUN set -eux; \
    v() { rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"; }; \
    devel=(cmake gcc-c++ extra-cmake-modules \
      "libplasma-devel-$(v libplasma)" \
      "qt6-qtbase-devel-$(v qt6-qtbase)" \
      "qt6-qtdeclarative-devel-$(v qt6-qtdeclarative)"); \
    for f in kcoreaddons kconfig kpackage kwindowsystem kservice ki18n kguiaddons knotifications; do \
      devel+=("kf6-$f-devel-$(v "kf6-$f")"); \
    done; \
    dnf install -y --setopt=install_weak_deps=False "${devel[@]}"; \
    V="$(rpm -q --qf '%{VERSION}' plasma-desktop)"; \
    echo "Building Kickoff from quine-global-labs/plasma-desktop, branch quine-v${V}"; \
    curl -fsSL --retry 3 -o /tmp/plasma-desktop.tar.gz \
      "https://forge.in.quineglobal.com/quine-global-labs/plasma-desktop/archive/quine-v${V}.tar.gz" \
      || { echo "No branch quine-v${V} in quine-global-labs/plasma-desktop: the image moved to Plasma ${V}; its rebase workflow makes the branch, or failed to (check its Actions)" >&2; exit 1; }; \
    mkdir -p /build-src; \
    tar -xzf /tmp/plasma-desktop.tar.gz -C /build-src --strip-components=2 \
      plasma-desktop/applets/kickoff; \
    cp /tmp/kickoff/CMakeLists.txt /build-src/; \
    cmake -S /build-src -B /build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr; \
    cmake --build /build -j"$(nproc)"; \
    DESTDIR=/out cmake --install /build --strip; \
    ls -l /out/usr/lib64/qt6/plugins/plasma/applets/org.kde.plasma.kickoff.so

# --- Final image. ---
FROM ${BASE_IMAGE} AS final

COPY overlay/ /

# alsa-tools provides hda-verb, used by cs8409-intmike-power-fixup.service.
RUN dnf install -y alsa-tools

# calligra-words, tailscale, teamviewer: NOT baked in here -- layer-wizard
# (already installed below) ships them as built-in recipes instead, so
# they're install-on-demand per machine rather than forced onto every
# system, and the recipes work on any rpm-ostree bootc system running
# layer-wizard, not just this image.

# Removes apps from the base image's default set that don't belong in ours.
# Native RPMs: plasma-welcome (Welcome Center), Sunshine (game-stream host).
RUN dnf remove -y plasma-welcome Sunshine

# Un-owned files baked directly into Aurora's own build, not from an RPM --
# dnf/rpm can't remove these, so plain rm: Aurora Offline Docs (a webapp
# shortcut to a local PDF) and Community (a webapp shortcut to the GitHub
# discussions page).
RUN rm -f /usr/share/applications/dev.getaurora.offline-docs.desktop \
          /usr/share/applications/dev.getaurora.discussions.desktop

COPY --from=kmod-builder /output/snd-hda-codec-cs8409.ko /tmp/snd-hda-codec-cs8409.ko

# Installs into .../extra/, which kmod's default search order gives
# precedence over the in-tree copy under .../kernel/... — this is the same
# mechanism Fedora's own kmod-* subpackages use to override an in-tree
# module of the same name/modalias. No blacklisting or renaming needed.
RUN set -eux; \
    NVR="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"; \
    mkdir -p "/usr/lib/modules/${NVR}/extra"; \
    mv /tmp/snd-hda-codec-cs8409.ko "/usr/lib/modules/${NVR}/extra/snd-hda-codec-cs8409.ko"; \
    depmod -a "${NVR}"

# Our own apps, from the forge's `quine` RPM group: each repo's rpm.yml
# builds and uploads them (quine-global-labs/layer-wizard, dnf-package-store,
# swap-watchdog). The repo is only used here, not left configured: the apps
# update with the image. kdotool, which swap-watchdog drives, is Fedora's.
# Forgejo signs the repository metadata, not the packages, so dnf checks the
# metadata (repo_gpgcheck), which pins each package's checksum.
RUN dnf install -y \
      --repofrompath=quine,https://forge.in.quineglobal.com/api/packages/quine-global-labs/rpm/quine \
      --setopt=quine.gpgcheck=0 --setopt=quine.repo_gpgcheck=1 \
      --setopt=quine.gpgkey=https://forge.in.quineglobal.com/api/packages/quine-global-labs/rpm/repository.key \
      layer-wizard dnf-package-store swap-watchdog

# Kickoff with our update bar (kickoff-builder, above), over plasma-desktop's.
COPY --from=kickoff-builder /out/usr/lib64/qt6/plugins/plasma/applets/org.kde.plasma.kickoff.so \
     /usr/lib64/qt6/plugins/plasma/applets/org.kde.plasma.kickoff.so

# System-level units are enabled explicitly. User units are picked up
# automatically via overlay/usr/lib/systemd/user-preset/.
# quine-update-check.timer: the status Kickoff's update bar shows.
RUN systemctl enable rpm-ostree-cleanup.timer cs8409-intmike-power-fixup.service \
      quine-update-check.timer
