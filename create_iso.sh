#!/bin/sh

# Process obtained from https://itnext.io/how-to-create-a-custom-ubuntu-live-from-scratch-dd3b3f213f81

# we expect a .xz compressed image (see below where we decompress it)
ORIGINAL_DISK_IMAGE=$1
DISK_IMAGE=$PWD/output/disk.img

# where to mount the disk image
CHROOT=$PWD/output/mnt

cp -a ${ORIGINAL_DISK_IMAGE} ${DISK_IMAGE}

cd output
# decompress the image
xz -v -d ${DISK_IMAGE}
cd ..

mkdir -p $CHROOT
# since we know that the partition with the data is the third one, we use awk to extract the start sector
sudo mount -o loop,offset=$(expr 512 \* $(fdisk -l ${DISK_IMAGE} |grep img3 | awk '{print $2}')) ${DISK_IMAGE} $CHROOT

# we prepare the chroot environment to ensure that everything works inside..
sudo mount -o bind /dev ${CHROOT}/dev
sudo mount -o bind /dev/pts ${CHROOT}/dev/pts
sudo mount -o bind /proc ${CHROOT}/proc
sudo mount -o bind /sys ${CHROOT}/sys
sudo mount -o bind /run ${CHROOT}/run
# install the required packages
sudo chroot ${CHROOT} apt install -y casper
# and, if needed, open a bash shell to do manual checks
# chroot ${CHROOT} /bin/bash
sudo umount ${CHROOT}/run
sudo umount ${CHROOT}/sys
sudo umount ${CHROOT}/proc
sudo umount ${CHROOT}/dev/pts
sudo umount ${CHROOT}/dev

rm -rf $PWD/image2

mkdir -p $PWD/image2/casper
mkdir -p $PWD/image2/isolinux
mkdir -p $PWD/image2/install

mv $CHROOT/cdrom/casper/* $PWD/image2/casper/

sudo cp $CHROOT/boot/vmlinuz-**-**-generic image2/casper/vmlinuz
sudo cp $CHROOT/boot/initrd.img-**-**-generic image2/casper/initrd

touch image2/ubuntu

cat <<EOF > image2/isolinux/grub.cfg

search --set=root --file /ubuntu

insmod all_video

set default="0"
set timeout=3

menuentry "Install Ubuntu Core Desktop" {
   linux /casper/vmlinuz boot=casper quiet splash ---
   initrd /casper/initrd
}
EOF

sudo mksquashfs $CHROOT image2/casper/filesystem.squashfs

printf $(sudo du -sx --block-size=1 $CHROOT | cut -f1) > image2/casper/filesystem.size

# we are done with the original disk image
sudo umount ${CHROOT}/sys/firmware/efi/efivars
sudo umount ${CHROOT}/sys
sudo umount ${CHROOT}
rmdir ${CHROOT}

cd $PWD/image2

grub-mkstandalone \
   --format=x86_64-efi \
   --output=isolinux/bootx64.efi \
   --locales="" \
   --fonts="" \
   "boot/grub/grub.cfg=isolinux/grub.cfg"

(
   cd isolinux && \
   dd if=/dev/zero of=efiboot.img bs=1M count=10 && \
   sudo mkfs.vfat efiboot.img && \
   LC_CTYPE=C mmd -i efiboot.img efi efi/boot && \
   LC_CTYPE=C mcopy -i efiboot.img ./bootx64.efi ::efi/boot/
)

grub-mkstandalone \
   --format=i386-pc \
   --output=isolinux/core.img \
   --install-modules="linux16 linux normal iso9660 biosdisk memdisk search tar ls" \
   --modules="linux16 linux normal iso9660 biosdisk search" \
   --locales="" \
   --fonts="" \
   "boot/grub/grub.cfg=isolinux/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img isolinux/core.img > isolinux/bios.img

sudo /bin/bash -c "(find . -type f -print0 | xargs -0 md5sum | grep -v "\./md5sum.txt" > md5sum.txt)"

sudo xorriso \
   -as mkisofs \
   -iso-level 3 \
   -full-iso9660-filenames \
   -volid "Ubuntu Core Desktop" \
   -output ${DISK_IMAGE%.*}.iso \
   -eltorito-boot boot/grub/bios.img \
      -no-emul-boot \
      -boot-load-size 4 \
      -boot-info-table \
      --eltorito-catalog boot/grub/boot.cat \
      --grub2-boot-info \
      --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
   -eltorito-alt-boot \
      -e EFI/efiboot.img \
      -no-emul-boot \
   -append_partition 2 0xef isolinux/efiboot.img \
   -m "isolinux/efiboot.img" \
   -m "isolinux/bios.img" \
   -graft-points \
      "/EFI/efiboot.img=isolinux/efiboot.img" \
      "/boot/grub/bios.img=isolinux/bios.img" \
      "."

cd ..
mv ${DISK_IMAGE%.*}.iso ${ORIGINAL_DISK_IMAGE%.*}.iso
