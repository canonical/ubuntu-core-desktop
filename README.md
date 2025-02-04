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
      --memory 2048 --vcpus 2 --boot uefi --os-variant ubuntu24.04 \
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
      -serial telnet:localhost:4321,server,nowait \
      -audio driver=pipewire,model=hda
```

This command line connects the inner port 22 to the localhost port 8022, to allow to
access SSH. Also connects the serial port to the localhost port 4321, allowing to
access through a virtual serial terminal using

    telnet localhost 4321

## Other Repositories

Most of the code used to construct the image is now managed in other
repositories. Namely:

| Snap | Repo | Recipe | Notes |
| ---- | ---- | ------ | ----- |
| `core24-desktop` | [core-base-desktop:24](https://github.com/canonical/core-base-desktop/tree/24) | [via launchpad](https://launchpad.net/~desktop-snappers/ubuntu-core-desktop/+snap/core24-desktop) | base snap, forked from `core24` to integrate GDM graphical login |
| `pc-desktop` | [pc-amd64-gadget-desktop:24](https://github.com/canonical/pc-amd64-gadget-desktop/tree/24) | [via launchpad](https://launchpad.net/~ubuntu-desktop/pc-gadget-desktop/+snap/pc-amd64-gadget-desktop-core24) | gadget snap, forked from `pc`, using `core24-desktop` as a base |
| `ubuntu-desktop-session` | [ubuntu-desktop-session-snap:24](https://github.com/canonical/ubuntu-desktop-session-snap/tree/24) | [via launchpad](https://launchpad.net/~ubuntu-desktop/+snap/ubuntu-desktop-session-snap-core24) | provides the confined desktop session |
| `snapd` | [ubuntu-core-desktop-snapd:master](https://github.com/canonical/ubuntu-core-desktop-snapd) | [via launchpad](https://launchpad.net/~snappy-dev/+snap/ubuntu-core-desktop-snapd) | a branch of snapd with additional changes not yet merged to mainline |

<details>
<summary>Core 22 Repositories</summary>

| Snap | Repo | Recipe | Notes |
| ---- | ---- | ------ | ----- |
| `core22-desktop` | [core-base-desktop:22](https://github.com/canonical/core-base-desktop/tree/22) | [via launchpad](https://launchpad.net/~ubuntu-desktop/+snap/core22-desktop) | base snap, forked from `core22` to integrate GDM graphical login |
| `pc-desktop` | [pc-amd64-gadget-desktop:22](https://github.com/canonical/pc-amd64-gadget-desktop/tree/22) | [via launchpad](https://launchpad.net/~ubuntu-desktop/pc-gadget-desktop/+snap/pc-amd64-gadget-desktop-core22) | gadget snap, forked from `pc`, using `core22-desktop` as a base |
| `pi-desktop` | [pi-desktop](https://github.com/canonical/pi-desktop) | [via launchpad](https://launchpad.net/~desktop-snappers/+snap/pi-desktop) | Pi gadget snap, forked from `pi`, using `core22-desktop` as a base |
| `ubuntu-desktop-session` | [ubuntu-desktop-session-snap:22](https://github.com/canonical/ubuntu-desktop-session-snap/tree/22) | [via launchpad](https://launchpad.net/~ubuntu-desktop/+snap/ubuntu-desktop-session-snap-core22) | provides the confined desktop session |
| `snapd` | [ubuntu-core-desktop-snapd](https://github.com/canonical/ubuntu-core-desktop-snapd) | [via ~snappy-dev](https://launchpad.net/~snappy-dev/+snap/ubuntu-core-desktop-snapd) | a branch of snapd with additional changes not yet merged to mainline |

</details>

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

## Self-signing the -dangerous model for testings

To do local testings with other sources than the current ones, it may be useful
to modify the `.model` files (for example, to make them point to `edge`). But
since these files must be signed, it must be done correctly.

First, you need a developer account in snapcraft.io. This process is detailed
here:

<https://snapcraft.io/docs/creating-your-developer-account>

After configuring the account, log in with snapcraft (`snapcraft login`) and
get your user ID (`snapcraft whoami`). Also, get your signature name with the
command `snap keys`.

Edit `ubuntu-core-desktop-XX-YY-dangerous.json` file, and put your ID both in
`authority-id` and `brand-id`.

Now, create the new `.model` file with the command:

`snap sign -k SIGNATURE-NAME ubuntu-core-desktop-XX-YY-dangerous.json > output.model`

Replacing `SIGNATURE-NAME`, `XX`, `YY` and `output.model` with the right values.
