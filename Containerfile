# Built on our Aurora fork (quine-global-labs/aurora), which its own workflow
# builds and publishes to this forge's registry. Pass e.g.
# --build-arg BASE_IMAGE=ghcr.io/ublue-os/aurora:stable to build on stock
# upstream Aurora instead, or localhost/aurora:stable for a local build of
# the fork.
ARG BASE_IMAGE=forge.quinefoundation.com/quine-global-labs/aurora:stable

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
    echo "Building snd-hda-codec-cs8409 against kernel ${NVR}"; \
    dnf install -y gcc make elfutils-libelf-devel bc perl patch; \
    dnf install -y "kernel-devel-${NVR}" \
      || dnf install -y "https://kojipkgs.fedoraproject.org/packages/kernel/${VERSION}/${RELEASE}/x86_64/kernel-devel-${NVR}.rpm"; \
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

# --- Final image. ---
FROM ${BASE_IMAGE} AS final

COPY overlay/ /

# alsa-tools provides hda-verb, used by cs8409-intmike-power-fixup.service.
RUN dnf install -y alsa-tools

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

# System-level units are enabled explicitly. User units are picked up
# automatically via overlay/usr/lib/systemd/user-preset/.
RUN systemctl enable rpm-ostree-cleanup.timer cs8409-intmike-power-fixup.service
