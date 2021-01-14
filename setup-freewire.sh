#!/bin/sh
#

# Configure the release name to be used with this version
export MENDER_ARTIFACT_NAME="release-1"

# Select an appropriate base configuration
#./scripts/bootstrap-rootfs-overlay-demo-server.sh --output-dir ./rootfs_overlay_freewire
#./scripts/bootstrap-rootfs-overlay-production-server.sh --output-dir ./rootfs_overlay_freewire
#./scripts/bootstrap-rootfs-overlay-hosted-server.sh --output-dir ./rootfs_overlay_freewire --tenant-token '<COPY TENANT TOKEN HERE>'

#### No need to configure anything below here.

# Extract the backend binaries into the rootfs overlay
sudo tar -C rootfs_overlay_freewire -xf backend-binaries.tar

# Blacklist the active and passive partitions from being automounted
sudo mkdir -p rootfs_overlay_freewire/etc/udev/mount.blacklist.d/
echo '/dev/mmcblk0p1' | sudo tee rootfs_overlay_freewire/etc/udev/mount.blacklist.d/mender >/dev/null
echo '/dev/mmcblk0p2' | sudo tee -a rootfs_overlay_freewire/etc/udev/mount.blacklist.d/mender >/dev/null
echo '/dev/mmcblk0p3' | sudo tee -a rootfs_overlay_freewire/etc/udev/mount.blacklist.d/mender >/dev/null
echo '/dev/mmcblk0p4' | sudo tee -a rootfs_overlay_freewire/etc/udev/mount.blacklist.d/mender >/dev/null

sudo chown -R root rootfs_overlay_freewire/
sudo chgrp -R root rootfs_overlay_freewire/

./docker-build
./docker-mender-convert --config configs/mender_convert_config --config configs/generic_x86-64_hdd_config --config mender_freewire_config  --disk-image input/reliagate-installed.img  --overlay rootfs_overlay_freewire/
