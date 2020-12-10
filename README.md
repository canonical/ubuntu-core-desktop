# GDM on Ubuntu Core

This directory contains an image of Ubuntu Core 20 with the GDM
display manager loaded into the boot file system.  It can be launched
in a Qemu virtual machine by following these instructions:

1. Download and decompress the two image files and place them in the
   same directory.

2. Add an image as a VM launchable from GNOME Boxes or virt-manager:
    ```
    # Delete VM if already registered
    virsh --connect qemu:///session undefine --nvram core-desktop
    virt-install --connect qemu:///session --name core-desktop \
      --memory 2048 --vcpus 2 --boot uefi --os-variant ubuntu20.04 \
      --video virtio,accel3d=yes --graphics spice \
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

## Testing a confined desktop session

The image includes a `ubuntu-desktop-session` snap, but it is not
added to the list of available sessions in GDM by default.  It can be
added by running the following command (either on the serial console,
or from the unconfined graphical session):

    sudo /snap/ubuntu-desktop-session/current/setup.sh

This will add an "Ubuntu (confined)" option to the session picker.
