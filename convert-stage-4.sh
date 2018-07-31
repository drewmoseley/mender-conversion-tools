#!/bin/bash -e

#    Copyright 2018 Northern.tech AS
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
bin_dir=${application_dir}/bin
output_dir=${MENDER_CONVERSION_OUTPUT_DIR:-${application_dir}}/output

set -e

echo "Running: $(basename $0)"
echo "args: $#"
mender_platform="$1"

platform_raspberrypi() {
    local bin_dir_pi=${bin_dir}/raspberrypi
    # TODO: Inherit, replace and append
    cat <<- EOF > $output_dir/fstab
proc              /proc     proc       defaults         0  0
/dev/root         /         auto       defaults         1  1
/dev/mmcblk0p1    /uboot    auto       defaults,sync    0  0
/dev/mmcblk0p4    /data     auto       defaults         0  0
EOF
    sudo install -m 0644 ${output_dir}/fstab ${output_dir}/rootfs/etc/fstab

    # Make a copy of Linux kernel arguments and modify.
    mcopy -o -i ${output_dir}/boot.vfat -s ::cmdline.txt ${output_dir}/cmdline.txt

    sed -i 's/\b[ ]root=[^ ]*/ root=\${mender_kernel_root}/' ${output_dir}/cmdline.txt

    # If the the image that we are trying to convert has been booted once on a
    # device, it will have removed the init_resize.sh init argument from cmdline.
    #
    # But we want it to run on our image as well to resize our data part so in
    # case it is missing, add it back to cmdline.txt
    if ! grep "init=/usr/lib/raspi-config/init_resize.sh" ${output_dir}/cmdline.txt; then
        cmdline=$(cat ${output_dir}/cmdline.txt)
        echo "${cmdline} init=/usr/lib/raspi-config/init_resize.sh" > ${output_dir}/cmdline.txt
    fi

    # Extract Linux kernel and install to /boot directory on rootfs
    mcopy -i ${output_dir}/boot.vfat -s ::kernel7.img ${output_dir}/zImage
    sudo cp ${output_dir}/zImage ${output_dir}/rootfs/boot/

    # Replace kernel with U-boot and add boot script
    mcopy -o -i ${output_dir}/boot.vfat -s ${bin_dir_pi}/u-boot.bin ::kernel7.img
    mcopy -i ${output_dir}/boot.vfat -s ${bin_dir_pi}/boot.scr ::boot.scr

    # Update Linux kernel command arguments with our custom configuration
    mcopy -o -i ${output_dir}/boot.vfat -s ${output_dir}/cmdline.txt ::cmdline.txt

    mcopy -i ${output_dir}/boot.vfat -s ::config.txt ${output_dir}/config.txt

    # dtoverlays seems to break U-boot for some reason, simply remove all of
    # them as they do not actually work when U-boot is used.
    sed -i /^dtoverlay=/d ${output_dir}/config.txt

    mcopy -o -i ${output_dir}/boot.vfat -s ${output_dir}/config.txt ::config.txt

    # Raspberry Pi configuration files, applications expect to find this on
    # the device and in some cases parse the options to determinate
    # functionality.
    sudo ln -sf /uboot/config.txt ${output_dir}/rootfs/boot/config.txt

    sudo install -m 755 ${bin_dir_pi}/fw_printenv ${output_dir}/rootfs/sbin/fw_printenv
    sudo install -m 755 ${bin_dir_pi}/fw_printenv ${output_dir}/rootfs/sbin/fw_setenv

    # Override init script to expand the data part instead of rootfs, which it
    # normally expands in standard Raspberry Pi distributions.
    sudo install -m 755 ${bin_dir_pi}/init_resize.sh \
                        ${output_dir}/rootfs/usr/lib/raspi-config/init_resize.sh
}

platform_pc_ubuntu() {
    local bin_dir_pi=${bin_dir}/pc/ubuntu
    # TODO: Inherit, replace and append
    cat $output_dir/rootfs/etc/fstab | grep -v ' / ' > $output_dir/fstab
    cat <<- EOF >> $output_dir/fstab

/dev/root         /          auto       defaults         1  1
LABEL=data        /data      auto       defaults         0  0
/dev/sda1         /boot/grub auto       defaults         0  0
EOF
    sudo install -m 0644 ${output_dir}/fstab ${output_dir}/rootfs/etc/fstab

    sudo mv ${output_dir}/rootfs/boot/grub ${output_dir}/rootfs/boot/grub.ubuntu-stock
    sudo mkdir ${output_dir}/rootfs/boot/grub

    if [ ! -f ${output_dir}/boot-part-env ]; then
        echo "${output_dir}/boot-part-env: not found"
        exit 1
    fi

    . ${output_dir}/boot-part-env

    echo "Creating a vfat file-system image for boot partition contents"
    dd if=/dev/zero of=${output_dir}/boot.vfat seek=${boot_part_size} count=0 bs=512 status=none conv=sparse
    sudo mkfs.vfat ${output_dir}/boot.vfat

    # Do a file-system check and fix if there are any problems
    sync
    (fsck.vfat ${output_dir}/boot.vfat || true)
    fatlabel ${output_dir}/boot.vfat BOOT

    # Populate the boot/grub partition
    mkdir -p ${output_dir}/boot/grub
    sudo mount -o loop ${output_dir}/boot.vfat ${output_dir}/boot/grub
    sudo rsync -aq --no-o --no-p --no-g --safe-links --delete ${application_dir}/pc-grub/ ${output_dir}/boot/grub/
    sudo umount ${output_dir}/boot/grub
}

# Platform specific hacks
case "${mender_platform}" in
    "rpi-ubuntu" ) platform_raspberrypi;;
    "pc-ubuntu"  ) platform_pc_ubuntu;;
esac
