# GDM on Ubuntu Core

This directory contains an image of Ubuntu Core 22 with the GDM
display manager loaded into the boot file system.  It can be launched
in a Qemu virtual machine by following these instructions:

1. Download and decompress the two image files and place them in the
   same directory.

2. Add an image as a VM launchable from GNOME Boxes or virt-manager:
    ```
    # Delete VM if already registered
    virsh --connect qemu:///session undefine --nvram core-desktop
    virt-install --connect qemu:///session --name core-desktop \
      --memory 2048 --vcpus 2 --boot uefi --os-variant ubuntu22.04 \
      --video virtio,accel3d=no --graphics spice \
      --import --disk path=$(pwd)/pc.img,format=raw
    ```
    (We use the virt-install because the GNOME Boxes seems to create a
    legacy BIOS VM when adding the image).

3. Let the VM boot and and automatically restart once as part of the
   setup process.  Once it settles, you can close the virt-viewer
   window and manage the VM with GNOME Boxes.

4. Follow the `gnome-initial-setup` wizard to create a user, and
   you'll be dropped into an unconfined desktop session.

At present, the wizard fails to make the created user an
administrator, limiting what is possible.  For now, I've left the root
account open with a blank password as a stop-gap measure.

It is also possible to launch the image outside of GNOME Boxes or
virt-manager with a command like the following:

```
    qemu-system-x86_64 -smp 2 -m 2048 -machine accel=kvm \
      -display gtk,gl=on \
      -net nic,model=virtio -net user,hostfwd=tcp::8022-:22 \
      -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,unit=0,readonly=on \
      -drive file=pc.img,cache=none,format=raw,id=main,if=none \
      -device virtio-blk-pci,drive=main,bootindex=1 \
      -device ac97 -audiodev pa,id=ac97
```

## Other Repositories

Most of the code used to construct the image is now managed in other
repositories. Namely:

| Snap | Repo | Recipe | Notes |
| ---- | ---- | ------ | ----- |
| `core22-desktop` | [core-base-desktop](https://github.com/canonical/core-base-desktop) | [via snapcraft.io](https://launchpad.net/~build.snapcraft.io/+snap/676555fa9c47346f6822f38f1cb28436) | base snap, forked from `core22` to integrate GDM graphical login |
| `pc-desktop` | [pc-amd64-gadget-desktop](https://github.com/canonical/pc-amd64-gadget-desktop) | [via snapcraft.io](https://launchpad.net/~build.snapcraft.io/+snap/b2fb84822ada14656220661309721e44) | gadget snap, forked from `pc`, using `core22-desktop` as a base |
| `ubuntu-desktop-session` | [ubuntu-desktop-session-snap](https://github.com/canonical/ubuntu-desktop-session-snap) | [via snapcraft.io](https://launchpad.net/~build.snapcraft.io/+snap/5053979ddb01a83fd292502a5ed3a3b4) | provides the confined desktop session |
| `snapd` | [ubuntu-core-desktop-snapd](https://github.com/canonical/ubuntu-core-desktop-snapd) | [via ~snappy-dev](https://launchpad.net/~snappy-dev/+snap/ubuntu-core-desktop-snapd) | a branch of snapd with additional changes not yet merged to mainline |

In addition, the base snap uses packages from the [desktop-snappers
core-desktop
PPA](https://launchpad.net/~desktop-snappers/+archive/ubuntu/core-desktop). This
is mostly to backport features we need that are not in jammy-updates.

## Extracting the snaps from the image

The built image is a normal hard disk image, which means that it is possible to get
the partition list with:

    fdisk -lu pc.img

This will show a list like this one:

    Disk pc2.img: 12 GiB, 12884901888 bytes, 25165824 sectors
    Units: sectors of 1 * 512 = 512 bytes
    Sector size (logical/physical): 512 bytes / 512 bytes
    I/O size (minimum/optimal): 512 bytes / 512 bytes
    Disklabel type: gpt
    Disk identifier: 6E3A867F-8F44-4880-BA2C-FABA633C36E6

    Device     Start     End Sectors  Size Type
    pc.img1    2048    4095    2048    1M BIOS boot
    pc.img2    4096 7172095 7168000  3.4G EFI System

After running the system the first time, other partitions will be added
for the system, the user data...

Now, using kpartx we can create loop devices for each of those partitions:

    sudo kpartx -av pc-img

Two loop devices, /dev/mapper/loopXXX/p1 and /dev/mapper/loopXXX/p2, will
be available. We want to mount the second one, which is the one that contains
the EFI system and the base snaps:

    sudo mount /dev/mapper/loopXXX/p2 /mnt

And now we can go to */mnt/snaps*, and there are all the base snaps.

# ISO image

To generate an ISO image with the installer, just run `make` and then
run the `sudo create_iso.sh` script.