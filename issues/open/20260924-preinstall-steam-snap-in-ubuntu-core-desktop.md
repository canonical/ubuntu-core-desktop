# Preinstall the Steam snap in Ubuntu Core Desktop

## Impact / Priority

Medium. A user who wants to play games currently has to find and
install Steam after setting up the desktop; preinstalling it would make
a fresh image more immediately useful for gaming. The actual impact and
feasibility are not yet established: confirm Steam's availability and
requirements on this image, then verify with a real launch on a rebuilt
system.

## Goal

Build Ubuntu Core Desktop with the Steam snap already installed on
first boot, rather than requiring the user to install it afterward.

## Work

- Check the Steam snap's current store availability, publisher,
  channel, base, and required interfaces, and confirm it is suitable
  for inclusion in the Ubuntu Core Desktop model.
- Add it to the appropriate model/build configuration using the
  repository's existing snap declaration and channel conventions.
- Rebuild and boot the desktop image. Verify Steam is installed on
  first boot and that its launcher opens successfully in the desktop
  session; investigate any required graphics, interface, or system
  integration before considering the task complete.
