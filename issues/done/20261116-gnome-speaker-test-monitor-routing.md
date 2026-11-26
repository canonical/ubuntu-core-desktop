# "Test speakers" dialog silent: libcanberra backend invisible when confined

Date: 2026-11-16

## Impact / Priority

PRIORITY: Low -- no audio playback functionality is lost. A real user
can play sound from apps in the VM fine (verified end-to-end with
audible tones on host headphones, 2026-11-16). What a user actually
observes: in Settings -> Sound -> "Test speakers", clicking each
speaker button produces NO sound, which reads as "the VM's sound is
broken" even though it isn't -- a misleading diagnostic dead end rather
than a lost feature. Anyone debugging VM audio this way wastes time on
the false negative (this session's author did exactly that).

## Scope (resolved 2026-11-16)

The SAME dialog in a regular non-Core Ubuntu 26.04 VM (g-c-c 1:50.3
deb) WORKS. The Core VM's Settings is g-c-c 1:46.7 from the
gnome-desktop-runtime content snap, but the speaker-test button code is
byte-for-byte identical between 46.7 and 50.3 (diffed
cc-speaker-test-button.c; only clang-format churn), and libpipewire is
1.6.2 on both. So this is NOT a version issue: it is the confined
packaging of libcanberra's backend modules in our stack.

Status: ROOT CAUSE IDENTIFIED (2026-11-16), fix drafted, not yet
implemented.

## Root cause (all verified live on 2026-11-16)

- Every dialog click logs in the guest journal:
    gnome-control-center[7664]: Failed to play sound: No such driver
  That is libcanberra CA_ERROR_NODRIVER: no backend module could be
  dlopen()ed. The tone is NEVER generated -- nothing is ever routed
  anywhere, so this was never a PipeWire routing problem.
- The speaker test plays via GSound -> libcanberra through the Pulse
  compat socket (GSOUND_ATTR_CANBERRA_FORCE_CHANNEL=front-left etc.).
- libcanberra loads backend modules (libcanberra-pulse.so,
  libcanberra-alsa.so) from its COMPILED-IN absolute path
  /usr/lib/<triplet>/libcanberra-0.30. Inside the confined session
  namespace that path does not exist (checked via
  /proc/<pid-of-g-c-c>/root/usr/lib/x86_64-linux-gnu/: no canberra
  entries). libcanberra.so.0 itself loads fine because it is found via
  LD_LIBRARY_PATH into the content mount.
- The modules DO ship: the content provider snap gnome-desktop-runtime
  (the session's connected provider; NOT gnome-46-2404, which is a
  different/unrelated content snap) stages libcanberra-pulse
  (gnome-desktop-runtime snap/snapcraft.yaml stage-packages) and
  the files are visible in the namespace at
  $SNAP/gnome/usr/lib/<triplet>/libcanberra-0.30/ (verified via
  /proc/7664/root/...). Only the absolute path mapping is missing.
- Red herring documented for posterity: wpctl status during the dialog
  shows "GNOME Settings" streams input_FL < Generic Analog:monitor_FL
  [active]. The WORKING stock VM shows the exact same shape (plus a
  capture_FL one) -- these are the sound panel's level meters, normal
  on any desktop, and irrelevant to the test tone.

## Proposed fix

In ubuntu-desktop-session-snap snapcraft.yaml layout section, mirror
the existing tinysparql-3.0 pattern (same class of problem: hard-coded
absolute module/data dir):

    /usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/libcanberra-0.30:
      bind: $SNAP/gnome/usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/libcanberra-0.30

Then: rebuild the session snap, rebuild the image (build.sh), retest
the dialog (expect audible front-left/front-right tones through the
QEMU PipeWire passthrough; the journal error should disappear).

## Next steps

1. Apply the layout, rebuild, retest (see above).
2. If the dialog is then audible, record the durable fact (confined
   content snaps + compiled-in absolute module paths = layout-bind
   requirement; same shape as the tinysparql fix) in the project
   notes.
3. Interim documentation point for testers: verify VM audio with
   `pw-play <file>` or any real app, NOT the Settings dialog.

## Resolution (2026-11-16)

Fixed by ubuntu-desktop-session-snap commit 16b7e2c ("Layout the
libcanberra module dir for canberra playback"): a layout bind
/usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/libcanberra-0.30 ->
$SNAP/gnome/usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/libcanberra-0.30.
Session snap rebuilt (20261116+git16b7e2c; note the snapcraft
version-string is cached in part state -- a metadata-only change needs
`snapcraft clean ubuntu-desktop-session` before repacking or the
embedded git rev goes stale and ubuntu-core-desktop's image build rev
check refuses it), image rebuilt, VM rebooted: the Test speakers
dialog is now AUDIBLE through the QEMU PipeWire passthrough (confirmed
by ear, 2026-11-16) and the guest journal has zero "Failed to play
sound" entries since boot. The durable fact was recorded in the
project notes (confined content snaps + compiled-in absolute module
paths = layout-bind requirement; same shape as the tinysparql fix).
