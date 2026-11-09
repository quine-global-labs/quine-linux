#!/usr/bin/bash
# Turns quine-linux into the live ISO's root filesystem (live/Containerfile):
# boots from the ISO into a KDE session as the live user, with Anaconda WebUI
# to install $PAYLOAD_IMAGE. Adapted from Aurora's live ISO,
# github.com/get-aurora-dev/iso (Apache-2.0), iso_files/*.sh at bee017f.
#
# Installed systems get their first user from plasma-setup at first boot, so
# the installer hides its account pages, as Aurora's does.
set -exo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create the directory that /root is symlinked to
mkdir -p "$(realpath /root)"
# bwrap (flatpak) writes /proc/sys/user/max_user_namespaces, read-only here
mount -o remount,rw /proc/sys

# ── The image to install, and the system Flatpaks to copy over ─────────────
# Both land in this filesystem, so installing needs no network.
# PAYLOAD_PULL: where to pull it from, if not its own name (iso.yml: the
# forge directly, ~100x faster from the runners than the
# registry.quineglobal.com proxy). Same manifest, so same digest; it's
# then known only by PAYLOAD_IMAGE, the name installs follow.
pull="${PAYLOAD_PULL:-$PAYLOAD_IMAGE}"
podman pull "$pull"
if [ "$pull" != "$PAYLOAD_IMAGE" ]; then
  podman tag "$pull" "$PAYLOAD_IMAGE"
  podman untag "$pull" "$pull"
fi

grep -v '#' /usr/share/ublue-os/homebrew/system-flatpaks.Brewfile | grep '^flatpak' |
  sed 's/flatpak //' | tr -d '"' >/tmp/flatpaks.list
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo
xargs -r flatpak install -y --noninteractive </tmp/flatpaks.list || true
flatpak list --columns=runtime,app

# ── Booting from the ISO ───────────────────────────────────────────────────
# EFI's name for this architecture, in Fedora's package and file names.
case $(uname -m) in
  x86_64) efi=x64 ;;
  aarch64) efi=aa64 ;;
  *) echo "no EFI name for $(uname -m)" >&2; exit 1 ;;
esac
dnf install -y \
  dracut-live \
  livesys-scripts \
  anaconda-live \
  anaconda-webui \
  pykickstart \
  jq \
  rsync \
  desktop-file-utils \
  libblockdev-btrfs \
  libblockdev-lvm \
  libblockdev-dm \
  "grub2-efi-$efi-cdboot"

kernel=$(find /usr/lib/modules -maxdepth 1 -type d -printf '%P\n' | grep . | head -1)
DRACUT_NO_XATTR=1 dracut -v --force --zstd --reproducible --no-hostonly \
  --add "dmsquash-live dmsquash-live-autooverlay" \
  "/usr/lib/modules/$kernel/initramfs.img" "$kernel"

# The live user, logged in to KDE
sed -i 's/^livesys_session=.*/livesys_session=kde/' /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

# Titanoboa reads EFI from /boot/efi. The fallback entry is grub itself.
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
cp -v "/boot/efi/EFI/fedora/grub$efi.efi" "/boot/efi/EFI/BOOT/fb$efi.efi"

# A larger /var/tmp than the live overlay's
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%,nr_inodes=1m,x-systemd.graceful-option=usrquota

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

rm -f /etc/localtime
systemd-firstboot --timezone UTC

mkdir -p /usr/lib/bootc-image-builder
cp "$SRC/iso.yaml" /usr/lib/bootc-image-builder/iso.yaml

# ── What a live session shouldn't do ───────────────────────────────────────
for unit in tailscaled.service brew-upgrade.timer brew-update.timer brew-setup.service \
  uupd.timer ublue-system-setup.service flatpak-preinstall.service; do
  systemctl disable "$unit" || true
done
systemctl --global disable podman-auto-update.timer ublue-user-setup.service || true
rm -f /usr/share/applications/dev.getaurora.system-update.desktop
rm -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service

# Only the system Flatpaks above get copied to the installed system, not
# what the live user installs.
cat >/usr/lib/systemd/system/var-lib-flatpak.mount <<'EOF'
[Unit]
Description=tmpfs so only the system Flatpaks are transferred to the installed system
Conflicts=umount.target

[Mount]
Type=overlay
What=overlay
Where=/var/lib/flatpak
Options=lowerdir=/var/lib/flatpak,upperdir=/run/overlay/flatpak,workdir=/run/overlay/flatpak.work
[Install]
WantedBy=local-fs.target
EOF
cat >/usr/lib/tmpfiles.d/quine-live-flatpak.conf <<'EOF'
d /run/overlay/flatpak 0755 - - -
d /run/overlay/flatpak.work 0755 - - -
EOF
systemctl enable var-lib-flatpak.mount

# ── KDE in the live session ────────────────────────────────────────────────
# The installer in Kickoff's favourites; no wallet prompts
sed -i '2s/$/;liveinst.desktop/' /usr/share/kde-settings/kde-profile/default/xdg/kicker-extra-favoritesrc
tee -a /etc/xdg/kwalletrc <<'EOF'
[Wallet]
Enabled=false
EOF

. /etc/os-release
echo "Quine Linux $VERSION_ID" >/etc/system-release

# plasma-welcome crashes with --live-environment unless given its pages
# (github.com/ublue-os/aurora/issues/2624, bugs.kde.org/523540)
cat >/usr/bin/plasma-welcome <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/plasma-welcome-original --pages Live,Welcome,SimpleByDefault,PowerfulWhenNeeded,Enjoy "$@"
EOF
rm -f /usr/share/plasma/plasma-welcome/intro-customization.desktop

# ── The installer ──────────────────────────────────────────────────────────
sed -i 's/ANACONDA_PRODUCTVERSION=.*/ANACONDA_PRODUCTVERSION=""/' /usr/{,s}bin/liveinst || true

# The profile matches os-release's ID (Aurora's, which quine-linux keeps).
mkdir -p /etc/anaconda/profile.d
tee /etc/anaconda/profile.d/quine-linux.conf <<EOF
[Profile]
profile_id = quine-linux

[Profile Detection]
os_id = $ID

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
webui_web_engine = slitherer
hidden_spokes =
    NetworkSpoke
    PasswordSpoke
    UserSpoke
hidden_webui_pages =
    anaconda-screen-date-time
    anaconda-network
    anaconda-screen-accounts
EOF

desktop-file-edit --set-key=StartupWMClass --set-value=slitherer \
  /usr/share/applications/liveinst.desktop

# Install the pulled image, then point the system at the registry for updates.
tee -a /usr/share/anaconda/interactive-defaults.ks <<EOF
ostreecontainer --url=$PAYLOAD_IMAGE --transport=containers-storage --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
%include /usr/share/anaconda/post-scripts/data-disk.ks
%include /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks
EOF

tee /usr/share/anaconda/post-scripts/install-configure-upgrade.ks <<EOF
%post --erroronfail
bootc switch --mutate-in-place --transport registry $PAYLOAD_IMAGE
%end
EOF

tee /usr/share/anaconda/post-scripts/install-flatpaks.ks <<'EOF'
%post --erroronfail --nochroot
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
target="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0/var/lib/"
mkdir -p "$target"
systemctl stop var-lib-flatpak.mount
rsync -aAXUHKP /var/lib/flatpak "$target"
sync
%end
EOF

# The installer's Data disk step (anaconda-webui/) writes the partition chosen
# to /run/quine-data-disk.json. Mount it at /var/hdd and bind what's on it
# into place, as the iMac was set up by hand (docs/relocate-home-to-hdd.md):
#   home-<user>/          -> /var/home/<user>   (each; no nofail: a missing
#                            disk stops the boot rather than show an empty home)
#   home/                 -> /var/home          (a new disk: everyone's homes)
#   flatpak/              -> /var/lib/flatpak   (made from the ISO's if absent)
#   podman-storage/storage, tmp -> /var/lib/containers/storage, /var/tmp
#   swapfile              -> swap, below zram's priority
# Nothing on the disk is deleted or formatted. Runs after install-flatpaks.ks.
tee /usr/share/anaconda/post-scripts/data-disk.ks <<'EOF'
%post --erroronfail --nochroot
set -euo pipefail
choice=/run/quine-data-disk.json
[ -s "$choice" ] || exit 0
dev="$(jq -r '.device // empty' "$choice")"
[ -b "$dev" ] || { echo "data disk: $dev isn't a block device" >&2; exit 1; }
uuid="$(blkid -s UUID -o value "$dev")"
fstype="$(blkid -s TYPE -o value "$dev")"
echo "data disk: $dev (UUID=$uuid, $fstype)"

deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
deploy="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0"
var="/mnt/sysimage/ostree/deploy/default/var"
fstab="$deploy/etc/fstab"

data="$(mktemp -d)"
mount "$dev" "$data"
trap 'umount "$data"' EXIT

lines=("UUID=$uuid /var/hdd $fstype defaults,nofail 0 2")
bind() { lines+=("$1 $2 none bind,x-systemd.requires-mounts-for=/var/hdd${3:+,$3} 0 0"); }
created=false

homes=()
for d in "$data"/home-*/; do
  [ -d "$d" ] && homes+=("$(basename "$d")")
done
if [ ${#homes[@]} -gt 0 ]; then
  for h in "${homes[@]}"; do
    mkdir -p "$var/home/${h#home-}"
    bind "/var/hdd/$h" "/var/home/${h#home-}"
  done
else
  [ -d "$data/home" ] || { mkdir -p "$data/home"; created=true; }
  bind /var/hdd/home /var/home
fi

if [ ! -d "$data/flatpak" ]; then
  mkdir -p "$data/flatpak"
  rsync -aAXUHK "$deploy/var/lib/flatpak/" "$data/flatpak/"
  created=true
fi
bind /var/hdd/flatpak /var/lib/flatpak nofail

if [ ! -d "$data/podman-storage" ]; then
  mkdir -p "$data/podman-storage/storage" "$data/podman-storage/tmp"
  created=true
fi
# It becomes /var/tmp: everyone writes there.
chmod 1777 "$data/podman-storage/tmp"
bind /var/hdd/podman-storage/storage /var/lib/containers/storage nofail
bind /var/hdd/podman-storage/tmp /var/tmp nofail

[ ! -f "$data/swapfile" ] || lines+=("/var/hdd/swapfile none swap sw,pri=10,nofail 0 0")

mkdir -p "$var/hdd" "$var/lib/flatpak" "$var/lib/containers/storage" "$var/tmp"
{
  echo "# Data disk (quine-linux installer): $dev"
  printf '%s\n' "${lines[@]}"
} >>"$fstab"
cat "$fstab"

# What this created has no SELinux labels yet: quine-data-disk-relabel.service
# labels it at first boot.
if $created; then
  mkdir -p "$var/lib/quine-linux"
  touch "$var/lib/quine-linux/relabel-data-disk"
fi
sync
%end
EOF

# Queues the key Aurora's kernel modules are signed with for enrolment in
# shim's MOK manager at the next boot (password: universalblue).
tee /usr/share/anaconda/post-scripts/secureboot-enroll-key.ks <<'EOF'
%post --erroronfail --nochroot
set -oue pipefail

readonly ENROLLMENT_PASSWORD="universalblue"
readonly SECUREBOOT_KEY="/etc/pki/akmods/certs/akmods-ublue.der"

if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "EFI mode not detected. Skipping key enrollment."
    exit 0
fi
if [[ ! -f "$SECUREBOOT_KEY" ]]; then
    echo "Secure boot key not provided: $SECUREBOOT_KEY"
    exit 0
fi
SYS_ID="$(cat /sys/devices/virtual/dmi/id/product_name)"
if [[ ":Jupiter:Galileo:" =~ ":$SYS_ID:" ]]; then
    echo "Steam Deck hardware detected. Skipping key enrollment."
    exit 0
fi

mokutil --timeout -1 || :
echo -e "$ENROLLMENT_PASSWORD\n$ENROLLMENT_PASSWORD" | mokutil --import "$SECUREBOOT_KEY" || :
%end
EOF

ksflatten -c /usr/share/anaconda/interactive-defaults.ks
stat /etc/pki/akmods/certs/akmods-ublue.der

dnf clean all
