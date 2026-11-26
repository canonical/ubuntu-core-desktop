# Use the Snap Store udisks2 snap instead of building it locally

## Impact / Priority

Building udisks2 locally duplicated the already-published Snap Store
snap (same content, verified), so the image carried a redundant custom
build that had to be rebuilt and patched by hand instead of tracking
the store's updates. No user-visible failure is recorded in the note;
impact derived from the original note's described symptoms.

Proposal: replace our local build of udisks2 with the existing Snap
Store 26/stable build.

- remove the udisks2 component build from the GNOME aggregate build

- in the image build (`build.sh`), drop the local udisks2 snap input
  and add udisks2 to `ubuntu-core-desktop-kde-26-amd64-dangerous.json`

Check whether anything else would break; if not, try it. To build an
image, run the image build (`build.sh --desktop gnome`) and boot it,
then verify and ssh in as root (no password needed).

## Resolution (2026-10-08)

Done. Pre-checked the store `udisks2` 26/stable (2.10.91-1, rev 126,
published 2026-09-30 by Canonical): meta/snap.yaml is identical to the
local snapcraft.yaml (slots udisks2/udisks2-dbus, plugs
udisks2-client/polkit, same apps/layouts, meta/polkit policy present,
core26 base) and its udisksd binary contains the /proc/1/mountinfo fix
(strings match our locally patched build) - the gate (that the store
snap must already carry the proc-mountinfo fix) has passed.

Changes:

- The GNOME aggregate build: the udisks2-snap component build was
  removed (7 components now), header comments updated.
- The image build (`build.sh`): removed the udisks2 --snap input line
  (GNOME case).
- udisks2 (26/stable, id KTyDAsgNZg4u9UBJ63MHn6q12fmUjOfn) added to
  BOTH model jsons. NOTE: the original note only named the KDE json,
  but the GNOME model also needed the entry - udisks2 reached GNOME
  images only via --snap, so dropping that without a model entry would
  have silently removed udisks2 from GNOME images.

Verified end-to-end on a fresh GNOME image boot (image build, QEMU
boot, ssh root):

- snap list: udisks2 2.10.91-1 rev 126 26/stable canonical**; no local
  snap shipped; gadget-seeded connections identical to the local-build
  setup (session:udisks2 -> udisks2:udisks2, polkit/hardware-observe/
  mount-observe/block-devices -> system, udisks2-client self-connect).
- udisksd D-Bus-activates on demand, runs snap.udisks2.udisksd
  (enforce); udisksctl status lists vda/vdb/sr0.
- proc-mountinfo verified at runtime: a loop device mounted OUTSIDE
  udisksd appeared in `udisksctl dump` MountPoints within seconds (the
  confined daemon reads host mounts via /proc/1/mountinfo).
- Confined gvfs-udisks2-volume-monitor activates on demand, (enforce),
  0 restarts; its org.gtk.Private.RemoteVolumeMonitor.List (called from
  the confined gnome-shell profile) returns the UDisks2-backed
  drives/volumes. No denials in normal operation; its profile correctly
  rejects unexpected calls from unconfined peers (matches
  `20260928-investigate-udisks2-volume-monitor-confinement.md`).
- Remaining real-user confirmation: GUI check of Files/volume listing
  on screen (`gio mount` in a `snap run --shell` harness is
  unreliable).
- KDE images now ship the udisks2 snap but nothing connects to it yet
  (no udisks2 wiring in the KDE gadget/session) - dormant until KDE
  volume-monitor work lands.
- Nothing committed at the time; working-tree changes in the aggregate
  build scripts and in `ubuntu-core-desktop` (both model jsons).
