#!/bin/bash

#    Copyright 2018 Northern.tech AS
#    Copyright 2018 Piper Networks Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
output_dir=${application_dir}/output

set -e

allign_partition_size() {
  local rvar_size=$1
  local rvar_alignment=$2

  size_in_bytes=$(( $rvar_size * 512 ))
  alignment_in_bytes=$(( $rvar_alignment * 512))
  reminder=$(( ${size_in_bytes} % ${alignment_in_bytes} ))

  if [ $reminder -ne 0 ]; then
    size_in_bytes=$(( $size_in_bytes - $reminder + $alignment_in_bytes ))
  fi

  local lsize=$(( $size_in_bytes / 512 ))

  echo $lsize
}

echo "Running: $(basename $0)"

if [ -z "$1" ]; then
    echo "Usage:"
    echo "    $(basename $0) < rootfs part size >"
fi

rootfs_part_size=$1
# Sanity check
if [ ${rootfs_part_size} -ge 16384 ]; then
    echo "Root file-system part set to: ${rootfs_part_size} MB"
    echo "Assuming that this is a mistake and exiting"
    exit 1
fi

# Convert to 512 blocks
rootfs_part_size=$(expr ${rootfs_part_size} \* 1024 \* 2)

if [ ! -f ${output_dir}/rootfs/usr/bin/mender ]; then
    echo "Can not find Mender client on target root file-system"
    exit 1
fi

device_type=$(cat ${output_dir}/data/mender/device_type | sed 's/[^=]*=//')
artifact_name=$(cat ${output_dir}/rootfs/etc/mender/artifact_info | sed 's/[^=]*=//')

if [ -z "${device_type}" ]; then
    echo "Device type not found in root file-system. Aborting..."
    exit 1
fi

if [ -z "${artifact_name}" ]; then
    echo "Articat name not found in root file-system. Aborting..."
    exit 1
fi

# Make sure that everything is flushed before we create the file-systems
sync

actual_rootfs_size=$(du -s --block-size=512 ${output_dir}/rootfs | awk '{ print $1 }')

# 20 % free space, not to be confused with rootfs_part_size
rootfs_size=$(awk -v r1="$actual_rootfs_size" 'BEGIN{printf "%.0f", r1 * 1.20}')

echo "Creating a ext4 file-system image from modified root file-system"
dd if=/dev/zero of=${output_dir}/rootfs.ext4 seek=${rootfs_size} count=0 bs=512 status=none

# From mkfs.ext4 man page
#
# -F
#     Force mke2fs to create a filesystem, even if the specified device is not
#     a partition on a block special device, or if other parameters do not make
#     sense. In order to force mke2fs to create a filesystem even if the
#     filesystem appears to be in use or is mounted (a truly dangerous thing
#     to do), this option must be specified twice.
sudo mkfs.ext4 -FF ${output_dir}/rootfs.ext4 -d ${output_dir}/rootfs

# Do a file-system check and fix if there are any problems
fsck.ext4 -fp ${output_dir}/rootfs.ext4

# number of sectors (256 MB)
data_size=$((512*256*2))

echo "Creating an ext4 file-system image of /data contents"
dd if=/dev/zero of=${output_dir}/data.ext4 seek=${data_size} count=0 bs=512 status=none
sudo mkfs.ext4 -F ${output_dir}/data.ext4 -d ${output_dir}/data

if [[ $(which mender-artifact) = 1 ]]; then
    echo "mender-artifact not found in PATH"
    exit 1
fi

mender_artifact=${output_dir}/${artifact_name}-${device_type}.mender

echo "Writing Mender artifact to: ${mender_artifact}"

#Create Mender artifact
mender-artifact write rootfs-image \
    --update ${output_dir}/rootfs.ext4 \
    --output-path ${mender_artifact} \
    --artifact-name ${artifact_name} \
    --device-type ${device_type}

echo "Creating Mender compatible disk-image"

if [ ! -f ${output_dir}/boot-part-env ]; then
    echo "${output_dir}/boot-part-env: not found"
    exit 1
fi

. ${output_dir}/boot-part-env

# number of sectors, 12MB
#
# We should really use the value in boot_part_start as alignment but current
# integration of raspberrypi puts U-boot env at 8 MB offset so have to put the
# alignment further in at 12 MB, which is also the start of boot part.
image_alignmnet="24576"

sdimg_path=${output_dir}/${artifact_name}-${device_type}.sdimg
sdimg_size=$(expr ${image_alignmnet} + ${boot_part_size} + ${rootfs_part_size} \* 2 + ${data_size} + ${data_size})

echo "Creating filesystem with :"
echo "    Boot partition $(expr ${boot_part_size} / 2) KiB"
echo "    RootFS         $(expr ${rootfs_part_size} / 2) KiB"
echo "    Data           $(expr ${data_size} / 2) KiB"

image_has_boot_part=$(test -f ${output_dir}/boot.vfat)

# Initialize sdcard image file
dd if=/dev/zero of=${sdimg_path} bs=512 count=0 seek=${sdimg_size}

# Align sizes
boot_part_size=$(allign_partition_size ${boot_part_size} ${image_alignmnet})
rootfs_part_size=$(allign_partition_size ${rootfs_part_size} ${image_alignmnet})
data_size=$(allign_partition_size ${data_size} ${image_alignmnet})

boot_part_start=${image_alignmnet}
boot_part_end=$(expr ${image_alignmnet} + ${boot_part_size})
rootfsa_start=$(expr ${boot_part_end} + ${image_alignmnet})
rootfsa_end=$(expr ${rootfsa_start} + ${rootfs_part_size})
rootfsb_start=$(expr ${rootfsa_end} + ${image_alignmnet})
rootfsb_end=$(expr ${rootfsb_start} + ${rootfs_part_size})
data_start=$(expr ${rootfsb_end} + ${image_alignmnet})
data_end=$(expr ${data_start} + ${data_size})

echo "rootfsa_start: ${rootfsa_start}"
echo "rootfsb_start: ${rootfsb_start}"
echo "data_start: ${data_start}"
echo "boot_start: ${boot_part_start}"

# Create partition table
parted -s ${sdimg_path} mklabel msdos
# Create boot partition and mark it as bootable
parted -s ${sdimg_path} unit s mkpart primary fat32 ${boot_part_start} ${boot_part_end}
parted -s ${sdimg_path} set 1 boot on
parted -s ${sdimg_path} -- unit s mkpart primary ext2 ${rootfsa_start} ${rootfsa_end}
parted -s ${sdimg_path} -- unit s mkpart primary ext2 ${rootfsb_start} ${rootfsb_end}
parted -s ${sdimg_path} -- unit s mkpart primary ext2 ${data_start} ${data_end}
parted ${sdimg_path} print

# Burn Partitions
dd if=${output_dir}/boot.vfat of=${sdimg_path} conv=notrunc seek=${boot_part_start}
dd if=${output_dir}/rootfs.ext4 of=${sdimg_path} conv=notrunc seek=${rootfsa_start}
dd if=${output_dir}/rootfs.ext4 of=${sdimg_path} conv=notrunc seek=${rootfsb_start}
dd if=${output_dir}/data.ext4 of=${sdimg_path} conv=notrunc seek=${data_start}
