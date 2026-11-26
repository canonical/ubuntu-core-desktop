# Investigate and narrow UDisks2 access for the GVFS volume monitor

## Impact / Priority

High (security design gate before requesting a targeted UDisks2
auto-connect assertion). The user-visible capability is
removable-storage integration in Files: devices should appear, mount,
unlock when encrypted, and eject safely. The current Snapd permission
allows the confined monitor to call the broad UDisks2 D-Bus API, and
some active-session operations on non-system devices are permitted by
the installed PolicyKit defaults without an authentication prompt. No
exploit or unauthorized operation has been demonstrated. The actual
risk depends on which methods GVFS invokes, which methods the app can
reach, and UDisks2's per-operation authorization; investigate those
with a real removable device and method-level tests rather than
inferring impact from the interface name. The end goal is a narrowed
permission set, not approval to keep the current broad API access.

## Context

The current desktop image seeds an explicit connection from the
`ubuntu-desktop-session:udisks2` plug to `system:udisks2`. The plug is
attached only to the `gvfs-udisks2-volume-monitor` app in the session
snap. The host's `gvfs-udisks2-volume-monitor.service` is overridden to
launch that confined app; it is a D-Bus client of the host UDisks2
daemon, not a UDisks2 daemon running inside the snap.

Snapd's built-in `udisks2` plug policy currently allows
`org.freedesktop.UDisks2.*` D-Bus interfaces, plus broad Properties,
ObjectManager, and introspection access. It does not currently expose a
Snapcraft option or store-assertion field for limiting allowed D-Bus
members. The base declaration still has `deny-auto-connection: true`;
the image connection is explicitly seeded by the gadget. The local
development Snapd change now adds the implicit Core system slot only
for model grade `dangerous`; signed, secured, and grade-unset Core
models do not get that slot. This gate applies to all dangerous-grade
Core models, not specifically to the Core Desktop variant. The
pre-existing Classic behavior is unchanged. The base declaration still
denies auto-connection. Never enable UDisks2 auto-connect for all
snaps. Any eventual auto-connect permission must be a targeted Security
Team/store assertion for the reviewed snap and its app-scoped plug.
Development images can continue to use the explicit gadget connection.

The VM's installed UDisks2 PolicyKit policy has operation-specific
actions. For active sessions, defaults include `yes` for ordinary
filesystem mount, encrypted unlock, `modify-device`, and some SMART
update/query operations; system-device variants and operations such as
`open-device`, secure erase, and several SMART tests require
administrator authentication. No matching local UDisks-specific
PolicyKit overrides were found. These are policy defaults, not proof of
which methods this monitor invokes or whether a particular device is
classified as a system device.

## Dangerous-model image verification — 2026-09-28

Rebuilt the local Snapd snap and GNOME image with the dangerous-grade
slot gate, then booted the image. `snap model --verbose` reported model
`ubuntu-core-desktop-26-amd64-dangerous`, grade `dangerous`;
`snap connections ubuntu-desktop-session` showed `udisks2` connected to
`:udisks2` with status `gadget`. The monitor unit was active under
`snap.ubuntu-desktop-session.gvfs-udisks2-volume-monitor (enforce)`
with zero restarts. `gio mount -l`, run under the confined GNOME Shell
profile, listed the VM's VirtIO disks, `cidata`, floppy, and DVD as
UDisks2-backed volumes. No relevant UDisks/GVFS AppArmor denials
appeared in the fresh boot journal after the test.

This verifies the allowed dangerous-model image path only. There was no
physical USB device, and no signed/secured image was booted; unit tests
verify that signed, secured, and grade-unset Core models do not receive
the implicit UDisks2 slot.

## Work

1. Trace and document the monitor's actual UDisks2 D-Bus calls under
   its confined profile for device discovery/change notifications,
   mounting, encrypted unlock/lock, unmount, and eject. Include normal
   startup and device removal/error paths. Use a real removable device
   where possible; the earlier confined VM test enumerated virtual QEMU
   disks only.
2. Map each required method and property access to the UDisks2
   authorization action and relevant device classification. Verify
   behavior against the installed UDisks2 implementation and PolicyKit
   rules; do not infer method authorization solely from action names.
3. Implement and test the narrowest practical AppArmor D-Bus policy for
   the required flows. If tightening the shared built-in `udisks2`
   interface would break unrelated consumers, add a dedicated
   volume-monitor interface instead. Do not treat the existing broad
   API permission as an acceptable end state. Test both required calls
   and intentionally denied high-impact calls from the confined
   monitor.
4. Keep blanket auto-connection denied. Prepare a targeted Security
   Team/store assertion request only for the reviewed snap and its
   app-scoped UDisks2 plug; an assertion may authorize that connection
   but must not be treated as a substitute for narrowing the D-Bus
   permissions. Test that unrelated snaps cannot auto-connect.
5. Confirm whether limiting the slot to dangerous-grade Core models is
   the intended boundary, or whether it should be narrower still (for
   example, limited to Core Desktop dangerous models). Do not treat
   `--dangerous` installation of an app as authorization to connect
   it.
6. Document the security-review-ready architecture, including the
   approved API subset, exact publisher/snap/plug scope of any
   requested assertion, and why each retained permission is necessary.

## Acceptance criteria

- Files can discover, mount, browse, unmount, and safely eject real
  removable storage from the confined desktop session; encrypted-volume
  behavior is tested if supported by the product.
- The justified D-Bus methods and required property/signal access are
  documented and the resulting AppArmor profile is narrowed to that
  set.
- A confined monitor is denied methods outside the approved set,
  including high-impact device operations not required for volume
  monitoring; tests distinguish AppArmor denials from PolicyKit
  authorization results. Any retained wildcard must be narrowly scoped
  and individually justified.
- The monitor has no direct raw-device access unless a separate,
  justified requirement is identified and tested.
- UDisks2 is never configured to auto-connect for all snaps. Any
  approved auto-connect assertion is limited to the reviewed snap/plug,
  and unrelated snaps cannot connect automatically. Development images
  may retain the explicit, app-scoped gadget connection.
- The Snapd interface and VM tests cover the final policy, including
  regressions in the required GVFS workflows.

## Resolution (established in later work; note appended on import)

Access was narrowed by moving the UDisks2 daemon to the provider snap
rather than the implicit Core system slot: the session snap's
`udisks2` plug connects to the provider snap's own `udisks2:udisks2`
slot via the gadget, app-scoped to `gvfs-udisks2-volume-monitor`; the
implicit dangerous-grade `:udisks2` system slot is no longer used; and
the base declaration still denies automatic connections. The snapd
interface and VM tests cover the final policy, including regressions
in the required GVFS workflows.
