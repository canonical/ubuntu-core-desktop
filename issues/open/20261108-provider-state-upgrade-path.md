# Decide and document the provider-state upgrade path (or wont-do)

## Impact / Priority

PRIORITY: Medium, and decision-shaped rather than bug-shaped. The
honest current state: the thin-variant images are FRESH-INSTALL-ONLY
by design — there is no tested upgrade path from a populated fat-base
installation to a thin-variant one, and the provider snaps move
long-lived state into $SNAP_COMMON. What a real user upgrading an
existing installation would observe if we shipped an upgrade without
this work: their account metadata caches (AccountsService user
avatars/templates), enrolled fingerprints, thunderbolt device
enrollment, and any daemon-local state silently reset — fingerprint
login stops working until re-enrollment, trusted-device prompts
reappear, account pictures/customization vanish. No DATA partition
user files are affected (homes are untouched). Whether this matters
depends entirely on whether anyone actually upgrades in-place vs
re-imaging — unknown for this project's user population; that
uncertainty is the first thing to resolve.

## Background

Flagged by the final independent review (finding 7): AccountsService,
fprintd, and bolt now keep state under /var/snap/<snap>/common/
($SNAP_COMMON) instead of the historical host locations
(/var/lib/AccountsService, /var/lib/fprint, bolt's state). On a fresh
install that is correct and self-contained; on an in-place upgrade
from a fat image the old state is orphaned.

## Work items

1. Decision: does this project support in-place upgrade from
   fat-base images to thin-variant images at all? (If the deployment
   model is re-image/reflash, record WONT-DO with that justification
   and close.) The base-swap work item's original scope treated images
   as fresh-built; confirm with the project owner.
2. If upgrades are in scope: for each provider snap, add a one-shot
   migration at install/first-run: if $SNAP_COMMON is empty and the
   legacy host path exists and is readable, copy/migrate it
   (AccountsService: /var/lib/AccountsService incl. user icons;
   fprintd: /var/lib/fprint enrollment DB — binary format, verify
   version compat; bolt: its state dir). Gate behind idempotency
   markers; test on a converted image.
3. Also decide the BASE-side question: upgrading the base snap from
   core26-desktop(fat) to core26-desktop(thin) in place — same snap
   name and (by design) same assertion shape, so snapd will offer the
   "refresh"; whether the writable-layer state (extrausers, seeded
   /etc) survives that flip cleanly needs one test boot before
   declaring upgrade support.
4. Document the decision in the main base-swap work item and (if
   upgrades are supported) in the image release notes.

## Notes

- The provider snaps' layout declarations make $SNAP_COMMON the
  system-visible path; migration must run as root early (install
  hook or a first-boot unit), not lazily on first daemon start, to
  avoid the daemon creating fresh state that blocks migration.
- fprintd enrollment data is the most safety-relevant (biometric
  templates); if migration is lossy, prefer forcing re-enrollment
  over a half-migrated DB.
