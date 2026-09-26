FROM ghcr.io/ublue-os/aurora:stable

COPY overlay/ /

# System-level units are enabled explicitly. User units are picked up
# automatically via overlay/usr/lib/systemd/user-preset/.
RUN systemctl enable rpm-ostree-cleanup.timer
