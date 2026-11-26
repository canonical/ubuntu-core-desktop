# Request snapd host-namespace mount support for xdg-fuse-broker

## Impact / Priority

PRIORITY: Low — architectural cleanliness, no current functional gap.
xdg-fuse-broker works correctly today as a privileged host binary
baked into the core26-desktop variant (the xdg-document-portal FUSE
mounts it creates propagate to every snap; verified live during the
base-swap project). The impact of NOT doing this work: the broker
remains one of the irreducible custom-base payloads — it can never
become a confined provider snap, so the desktop base can never be pure
stock core26 while the document-portal flow exists in its current
design. No user observes anything either way; this is developer/
maintainer debt.

## Background (from the base-swap recon and the final review)

- The broker mounts xdg-document-portal's FUSE filesystem at
  /run/user/<uid>/doc with peer-uid verification, handing the live
  /dev/fuse fd to the portal via SCM_RIGHTS through a fusermount3
  shim; mounts must originate in the HOST namespace to be visible to
  every snap (mountinfo proves the shared/master propagation).
- snap-confine makes snap namespaces MS_REC|MS_SLAVE
  (mount-support.c:519-520): a snap-daemon broker's mounts would be
  visible to no one. The snapd fork has no mount-propagation helpers.
- The design is deliberate (core-base-desktop commit 828e730, in-tree
  fuse-broker/ source); xdg-document-portal has no non-FUSE backend.

## Work items

1. Open a discussion/issue with snapd upstream (forum
   (snapcraft.io/forum) first per snapd contribution norms, then
   github.com/canonical/snapd if warranted) describing the use case:
   a snap daemon that must create mounts visible in the host namespace
   (FUSE broker for document portal), and asking for a supported
   mechanism (e.g. a privileged interface granting host-ns mount
   execution, or a snapd-provided helper that performs the mount on
   the daemon's behalf with the fd handoff).
2. Include the security framing already worked out (the
   CAP_SYS_ADMIN-to-snap path was rejected by threat model; the
   broker's allowlist + peer-uid checks are the confinement that
   matters).
3. If/when upstream grows support: migrate the broker out of the
   variant into a snap (the recon's gate design applies: units+wants,
   shared:/master: mountinfo assertion, portal /dev/fuse fd, confined
   app file-open E2E, and a tripwire that the unit never gains
   PrivateMounts/ProtectSystem/ProtectHome).
4. Until then: this is the documented reason xdg-fuse-broker stays in
   the variant (Stage A decision table §0).

## Notes

- This is the "revisit trigger" recorded in the main base-swap work
  item.
- Coordinate with the fuse-support/fuse-device interface maintainers —
  the existing fuse-device AppArmor rule (EACCES->EPERM shim
  fallback trigger) came from this same design.
