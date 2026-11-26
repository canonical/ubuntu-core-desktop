# Check snapped services for leftover pre-snap systemd unit files

## Impact / Priority

Leftover systemd unit files for pre-snap versions of the now-snapped
services could conflict with the snapped units at runtime. The original
note recorded no concrete user-visible failure, so no priority was
assessed. Impact derived from the original note's symptoms.

For all services that are now snapped, check for existing systemd unit
files for the pre-snapped version. These can conflict at runtime.

## Resolution (2026-11-15)

Completed the audit; the method and full findings were recorded in the
audit write-up.

Result: the system-service side is already clean. No pre-snap unit file
or D-Bus activation file remains in the base for accountsservice, avahi,
bluez, bolt, fprintd, geoclue, network-manager, udisks2, upower, provd or
pipewire/wireplumber; live ps/busctl on a booted image shows one provider
instance each. systemd-networkd + wpa_supplicant coexist with the NM snap
by design (NM takes the interface over; the base supplicant is what NM
uses; no duplicate supplicant).

Fixed the two real leftovers, both user-session side:

- core-base-desktop f16b8bb: org.gnome.keyring.SystemPrompter now execs
  the session snap's gcr-prompter instead of the removed
  /usr/libexec/gcr-prompter.
- gnome-desktop-runtime 92ff590: stop shipping the pre-snap
  pipewire/pipewire-pulse/wireplumber/filter-chain user units, which the
  session wrapper exposed to the user manager (snap.pipewire.* are the
  authoritative units).

Verified by rebuilding the base/content snaps and a full image, then
booting it: SystemPrompter file is correct, user.control has no pipewire
units (only snap.pipewire.*), audio daemons run, no new failed units.

Remaining (recorded in the audit write-up, not unit-vs-snap conflicts):
localsearch-3 still fails 203/EXEC (needs the route-through/gap pass),
glib-pacrunner fails on missing libpxbackend-1.0.so, gnome-keyring unit
files are disabled/inert.
