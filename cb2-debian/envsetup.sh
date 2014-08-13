#!/bin/bash

#Product Variants
CB_PRODUCT_ROOTFS_IMAGE=${CB_PACKAGES_DIR}/debian-rootfs-20140809.tar.gz
CB_PRODUCT_ONLY_KERNEL=0
U_BOOT_WITH_SPL=${CB_PACKAGES_DIR}/u-boot-a20/u-boot-sunxi-with-spl-mmc2.bin 

cb_build_linux()
{
    if [ ! -d ${CB_KBUILD_DIR} ]; then
	mkdir -pv ${CB_KBUILD_DIR}
    fi

    echo "Start Building linux"
    cp -v ${CB_PRODUCT_DIR}/kernel_defconfig ${CB_KSRC_DIR}/arch/arm/configs/
    make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} kernel_defconfig
    rm -rf ${CB_KSRC_DIR}/arch/arm/configs/kernel_defconfig
    make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_TARGET_DIR} uImage modules
    ${CB_CROSS_COMPILE}objcopy -R .note.gnu.build-id -S -O binary ${CB_KBUILD_DIR}/vmlinux ${CB_KBUILD_DIR}/bImage
    echo "Build linux successfully"
}

cb_build_clean()
{
    sudo rm -rf ${CB_OUTPUT_DIR}/*
    sudo rm -rf ${CB_BUILD_DIR}/*
}


cb_build_card_image()
{
    cb_build_linux

    sudo rm -rf ${CB_OUTPUT_DIR}/card0-part1 ${CB_OUTPUT_DIR}/card0-part2
    mkdir -pv ${CB_OUTPUT_DIR}/card0-part1 ${CB_OUTPUT_DIR}/card0-part2

    #part1
    cp -v ${CB_KBUILD_DIR}/arch/arm/boot/uImage ${CB_OUTPUT_DIR}/card0-part1
    fex2bin ${CB_PRODUCT_DIR}/configs/sys_config.fex ${CB_OUTPUT_DIR}/card0-part1/script.bin
    cp -v ${CB_PRODUCT_DIR}/configs/uEnv-mmc.txt ${CB_OUTPUT_DIR}/card0-part1/uEnv.txt
    (cd ${CB_OUTPUT_DIR}/card0-part1;  tar -c *) |gzip -9 > ${CB_OUTPUT_DIR}/bootfs-part1.tar.gz

    #part2
    sudo tar -C ${CB_OUTPUT_DIR}/card0-part2 --strip-components=1 -xpf ${CB_PRODUCT_ROOTFS_IMAGE}
    sudo make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_OUTPUT_DIR}/card0-part2 modules_install
    (cd ${CB_PRODUCT_DIR}/overlay; tar -c *) |sudo tar -C ${CB_OUTPUT_DIR}/card0-part2  -x --no-same-owner
    cp -v ${CB_PRODUCT_DIR}/configs/firstrun ${CB_OUTPUT_DIR}/card0-part2/etc/init.d/firstrun
    (cd ${CB_OUTPUT_DIR}/card0-part2; sudo tar -cvp * )|gzip -9 > ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
}

cb_install_card()
{
    local sd_dev=$1
    if cb_sd_sunxi_part $1
    then
	echo "Make sunxi partitons successfully"
    else
	echo "Make sunxi partitions failed"
	return 1
    fi

    mkdir /tmp/sdc1
    sudo mount /dev/${sd_dev}1 /tmp/sdc1
    sudo tar -C /tmp/sdc1 -xvf ${CB_OUTPUT_DIR}/bootfs-part1.tar.gz
    sync
    sudo umount /tmp/sdc1
    rm -rf /tmp/sdc1

    if cb_sd_make_boot2 $1 $U_BOOT_WITH_SPL
    then
	echo "Build successfully"
    else
	echo "Build failed"
	return 2
    fi

    mkdir /tmp/sdc2
    sudo mount /dev/${sd_dev}2 /tmp/sdc2
    sudo tar -C /tmp/sdc2 -xpf ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
    sync
    sudo umount /tmp/sdc2
    sudo rm -rf /tmp/sdc2

    return 0
}

 

