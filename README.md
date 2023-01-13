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
      -device virtio-vga,virgl=on -display gtk,gl=on \
      -net nic,model=virtio -net user,hostfwd=tcp::8022-:22 \
      -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,unit=0,readonly=on \
      -drive file=pc.img,cache=none,format=raw,id=main,if=none \
      -device virtio-blk-pci,drive=main,bootindex=1
```

## Other Repositories

Most of the code used to construct the image is now managed in other
repositories. Namely:

* [canonical/core-base-desktop](https://github.com/canonical/core-base-desktop):
  the `core22-desktop` base snap, forked from `core22` to use as a
  boot base integrating GDM as a graphical login.
* [canonical/pc-amd64-gadget-desktop](https://github.com/canonical/pc-amd64-gadget-desktop):
  the `pc-desktop` gadget snap, forked from the regular `pc` gadget
  snap to use `core22-desktop` as its base snap and perform some
  additional setup.
* [canonical/ubuntu-desktop-session-snap](https://github.com/canonical/ubuntu-desktop-session-snap):
  the `ubuntu-desktop-session` snap that is run as the confined
  desktop session.
* [canonical/ubuntu-core-desktop-snapd](https://github.com/canonical/ubuntu-core-desktop-snapd)
  a branch of snapd containing additional features that have not yet
  been accepted upstream. Currently built as an unpublished snap, but
  should be published as a branch soon.

Most of the above snaps are being automatically published to their edge
channels through the snapcraft.io build service.
