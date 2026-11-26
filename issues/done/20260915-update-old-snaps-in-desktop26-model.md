# Update old snaps in the Ubuntu Core Desktop 26 model

Date: 2026-09-15

## Impact / Priority

Image-hygiene work on the Core 26 model: the model had carried the
24-era identity, and several snaps (snap-store, network-manager, avahi,
bluez) seeded from stale channels while the unused `core24-desktop`
base was needlessly installed in the image, so rebuilt images shipped
older revisions than the current stable ones. Impact derived from the
original note's described symptoms. No priority level was stated in the
original note.

## Context

Investigated the model file
`ubuntu-core-desktop-26-amd64-dangerous.json` and the live test VMs:

    Ubuntu 24: the Core 24 test VM
    Ubuntu 26: the Core 26 test VM

The 26 model JSON previously contained the 24 model name and display
name, despite declaring core26-desktop as its root base. This was
corrected and committed as d97789c (Fix Ubuntu Core Desktop 26 model
identity). The 26 VM is running pc-desktop 26 and a locally built
ubuntu-desktop-session based on core26-desktop; rebuild the image to
bake in the corrected signed model.

Firefox is not installed on either VM. The model marks it as optional,
so its absence is expected. If Firefox must be present in the image,
remove presence: optional and use the latest/stable channel.

## Current dependency findings

The previously investigated removals are resolved or moot:

- console-conf, Firefox, and core22 were removed from the model in
  commits 07f87ce, b6ab1b3, and 7832197.
- core24 cannot be removed: gnome-46-2404, mesa-2404, avahi, bluez,
  network-manager, and snap-store all declare base: core24 on the live
  VM.

core24-desktop is different: on the 26 VM no installed snap uses it as
its base. The desktop session uses core26-desktop. It should be removed
from the 26 model unless a future snap explicitly needs it.

## Required work

Completed:

- Removed core24-desktop from the 26 model.
- Rebuilt the image and booted it in a test VM.
- Verified the rebuilt VM reports the Ubuntu Core Desktop 26 model,
  does not install core24-desktop, and starts snapd and GDM cleanly.

Completed:

- Updated snap-store from latest/stable/ubuntu-24.04 to 2/stable
  (revision 1390).
- Added the official Canonical gnome-46-2404 provider required by that
  Snap Store revision.
- Added the official Canonical mesa-2404 provider required by Snap
  Store's gpu-2404 plug.
- Rebuilt and boot-tested the image. The VM reports the 26 model, has
  snap-store 1390 with gnome-46-2404 and gpu-2404 connected, and starts
  snapd and GDM.

Completed:

- Updated network-manager, avahi, and bluez to 26/stable in the model.
- Rebuilt and booted the image. The installed revisions track
  26/stable, there are no channel-specific snapd failures, and
  GDM/GNOME starts normally; the known confined-session AppArmor/D-Bus
  warnings remain.
- Committed as ee64866 (Update desktop26 service channels).

Blocked:

1. Wait for 26/stable publication of pc-desktop and
   ubuntu-desktop-session. pc-desktop currently publishes only through
   24/stable, and ubuntu-desktop-session is likewise not yet published
   for Core 26. Do not change those model entries until the channels
   exist.

## GNOME 42 migration note

ubuntu-desktop-init revision 133 is the only remaining gnome-42-2204
consumer. No newer published ubuntu-desktop-init revision is currently
available; latest/candidate remains revision 133 and still declares the
gnome-42-2204 content plug. This is historical context for the existing
ubuntu-desktop-init snap, not an additional open item for this
channel-bump task.

## VM evidence

Ubuntu 24 (the Core 24 test VM):

- core24-desktop root base
- ubuntu-desktop-session revision 40 from 24/stable
- Firefox absent
- core22 and core24 installed

Ubuntu 26 (the Core 26 test VM):

- core26-desktop root base
- ubuntu-desktop-session local x1 revision, based on core26-desktop
- core24-desktop installed but unused as a snap base
- Firefox absent
- core22 and core24 installed for the dependent application snaps
- GNOME Shell session is running; remaining AppArmor/D-Bus warnings are
  the known confined-session gaps documented in the project notes
