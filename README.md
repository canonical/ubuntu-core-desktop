# GDM on Ubuntu Core

This directory contains an image of Ubuntu Core 20 with the GDM
display manager loaded into the boot file system.  It can be launched
in a Qemu virtual machine by following these instructions:

1. Download and decompress the two image files and place them in the
   same directory.

2. Start a virtual machine with the following command:
```
    qemu-system-x86_64 -smp 2 -m 2048 -machine accel=kvm \
      -device virtio-vga,virgl=on -display gtk,gl=on \
      -net nic,model=virtio -net user,hostfwd=tcp::8022-:22 \
      -drive file=/usr/share/OVMF/OVMF_CODE.fd,if=pflash,format=raw,unit=0,readonly=on \
      -drive file=pc.img,cache=none,format=raw,id=main,if=none \
      -drive file=assertions.img,format=raw,id=assertions,if=none,readonly=on \
      -device virtio-blk-pci,drive=main,bootindex=1 \
      -device nec-usb-xhci,id=xhci \
      -device usb-storage,bus=xhci.0,removable=on,drive=assertions
```
3. Let the VM boot and and automatically restart once as part of the
   seeding process.  The GDM greeter will appear during this process,
   but you won't be able to log in.

4. After the reboot, wait for the GDM login screen to appear again.
   Try logging in with the username "ubuntu" and password "ubuntu".
   If it fails, wait 30 seconds and try again (it is loading the user
   account from the assertions image).

This will dump you in a minimal X session with an xterm.  A user
instance of systemd will be running, along with a D-Bus session bus
managed by that instance.

The "/usr/share/wayland-sessions" directory is writable, and should
allow the launch of a fully confined desktop session from the display
manager.

## Testing a confined desktop session

The image includes a `confined-desktop` snap, but it is not added to
the list of available sessions in GDM by default.  It can be added by
running the following command (either on the serial console, or from
the unconfined graphical session):

    sudo /snap/confined-desktop/current/setup.sh

This will add an "Ubuntu (confined)" option to the session picker.
