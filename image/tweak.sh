#!/bin/bash
#
mkdir -p $PWD/output/mnt
mount -o loop,offset=$(expr 512 \* $(fdisk -l output/installer-amd64.img |grep img3 | awk '{print $2}')) output/installer-amd64.img $PWD/output/mnt
mkdir -p $PWD/output/mnt/cdrom/casper
mv $PWD/output/mnt/{pc.img.xz,install-sources.yaml} $PWD/output/mnt/cdrom/casper/ && sync && sleep 30
umount $PWD/output/mnt
rmdir $PWD/output/mnt
