#!/usr/bin/env bash
# Builds libtaskmanager (plasma-workspace's task manager models) with
# startup-feedback.patch, into /out/usr/lib64, for the Containerfile's
# taskmanager-builder (README: "Launch feedback"). Runs FROM BASE_IMAGE:
# the source is Fedora's own source RPM of the plasma-workspace the image
# ships (its two patches don't touch libtaskmanager), and the -devel
# packages are pinned to the installed versions, so the library can't
# drift from the Plasma it goes into.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

v() { rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"; }
nvr=$(v plasma-workspace)
V=$(rpm -q --qf '%{VERSION}' plasma-workspace)
echo "Building libtaskmanager from plasma-workspace-$nvr"

devel=(cmake gcc-c++ extra-cmake-modules patch redhat-rpm-config
  "plasma-workspace-devel-$nvr"
  "plasma-activities-devel-$(v plasma-activities)"
  "plasma-wayland-protocols-devel"
  "qt6-qtbase-devel-$(v qt6-qtbase)"
  "qt6-qtbase-private-devel-$(v qt6-qtbase)"
  "qt6-qtdeclarative-devel-$(v qt6-qtdeclarative)"
  "qt6-qtwayland-devel-$(v qt6-qtwayland)")
# kf6-kio is split (kf6-kio-core, -gui, ...): pin to whichever is there.
for f in kitemmodels kconfig ki18n kio kjobwidgets kservice kwindowsystem; do
  for pkg in "kf6-$f" "kf6-$f-core"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then devel+=("kf6-$f-devel-$(v "$pkg")"); break; fi
  done
done
dnf install -y --setopt=install_weak_deps=False \
  --enablerepo=updates-archive "${devel[@]}"

work=$(mktemp -d)
cd "$work"
dnf download --source --enablerepo=fedora-source,updates-source,updates-archive "plasma-workspace-$nvr"
rpm2cpio "plasma-workspace-$nvr.src.rpm" | cpio -id --quiet
tar -xJf "plasma-workspace-$V.tar.xz" \
  "plasma-workspace-$V/libtaskmanager" "plasma-workspace-$V/config-X11.h.cmake"
src=$work/plasma-workspace-$V
patch -d "$src" -p1 --no-backup-if-mismatch <"$here/startup-feedback.patch"

# Fedora's own flags (hardening, --as-needed), as its package build uses.
export CFLAGS=$(rpm -E '%{build_cflags}') CXXFLAGS=$(rpm -E '%{build_cxxflags}') LDFLAGS=$(rpm -E '%{build_ldflags}')
cmake -S "$here" -B "$work/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  -DPLASMA_SRC="$src" -DPLASMA_VERSION="$V"
cmake --build "$work/build" --target taskmanager -j"$(nproc)"

mkdir -p /out/usr/lib64
lib=$(find "$work/build" -name "libtaskmanager.so.$V" -type f | head -1)
[ -n "$lib" ] || { echo "no libtaskmanager.so.$V built" >&2; exit 1; }
strip --strip-unneeded -o "/out/usr/lib64/libtaskmanager.so.$V" "$lib"
# Same soname as the one it replaces, or plasmashell wouldn't load it.
[ "$(objdump -p "/out/usr/lib64/libtaskmanager.so.$V" | awk '/SONAME/{print $2}')" = \
  "$(objdump -p "/usr/lib64/libtaskmanager.so.$V" | awk '/SONAME/{print $2}')" ]
ls -l "/out/usr/lib64/libtaskmanager.so.$V"
