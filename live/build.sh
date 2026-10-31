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
podman pull "$PAYLOAD_IMAGE"

grep -v '#' /usr/share/ublue-os/homebrew/system-flatpaks.Brewfile | grep '^flatpak' |
  sed 's/flatpak //' | tr -d '"' >/tmp/flatpaks.list
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo
xargs -r flatpak install -y --noninteractive </tmp/flatpaks.list || true
flatpak list --columns=runtime,app

# ── Booting from the ISO ───────────────────────────────────────────────────
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
  grub2-efi-x64-cdboot

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
cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi

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
