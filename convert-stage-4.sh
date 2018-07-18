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
output_dir=${application_dir}/output

set -e

echo "Running: $(basename $0)"

# Platform specific hacks

if [ true ]; then # raspberrypi
    # TODO: Inherit, replace and append
    cat <<- EOF > $output_dir/fstab
proc              /proc     proc       defaults         0  0
/dev/root         /         auto       defaults         1  1
/dev/mmcblk0p1    /uboot    auto       defaults,sync    0  0
/dev/mmcblk0p4    /data     auto       defaults         0  0
EOF

    # Two things are important here:
    #
    # - we remove init=/usr/lib/raspi-config/init_resize.sh, this does an
    #   initial rootfs resize normally. We have no need to do this.
    #
    # - set root=${mender_kernel_root} to be able to switch root part

    # TODO: Inherit, replace, append
    cat <<- EOF > $output_dir/cmdline.txt
dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=\${mender_kernel_root} rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet splash plymouth.ignore-serial-consoles
EOF

    sudo install -m 0644 ${output_dir}/fstab ${output_dir}/rootfs/etc/fstab

    # Extract Linux kernel and install to /boot directory on rootfs
    mcopy -i ${output_dir}/boot.vfat -s ::kernel7.img ${output_dir}/zImage
    sudo cp ${output_dir}/zImage ${output_dir}/rootfs/boot/

    # Replace kernel with U-boot and add boot script
    mcopy -o -i ${output_dir}/boot.vfat -s ${application_dir}/files/u-boot.bin ::kernel7.img
    mcopy -i ${output_dir}/boot.vfat -s ${application_dir}/files/boot.scr ::boot.scr

    # Update Linux kernel command arguments
    mcopy -o -i ${output_dir}/boot.vfat -s ${output_dir}/cmdline.txt ::cmdline.txt

    sudo install -m 755 ${application_dir}/files/fw_printenv ${output_dir}/rootfs/sbin
    sudo install -m 755 ${application_dir}/files/fw_setenv ${output_dir}/rootfs/sbin
fi
