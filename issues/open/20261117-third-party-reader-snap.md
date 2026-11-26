# Third-party reader snap: investigate and integrate (beyond the one-reader pin)

## Impact / Priority

Accessibility is currently locked to exactly ONE reader snap
(ubuntu-desktop-a11y): a third-party screen reader cannot hold
the reader role, because AppArmor policy has no "labels holding a
reader grant" expression — a third-party reader snap is denied at
exactly the desktop-legacy-shared read surfaces. Owner ruling
(2026-11-17, wave-2 review): the one-reader pin is accepted for
now, but investigating/integrating a third-party reader is its
own work item.

Impact derived from the original note's described symptoms.

## Context

Written 2026-11-17. Owner ruling during the wave-2 review: the
one-reader pin (T43 decision point 2) is ACCEPTED FOR NOW, but a
todo is requested to investigate and integrate a THIRD-PARTY
reader snap — i.e. let a reader other than our
ubuntu-desktop-a11y hold the reader role.

## The current state (why it is pinned)

- The reader-role policy (snapd fork desktop/26, commits
  2a24f790b7/d91bacfbbb, T43) gates reader-only interfaces by
  KERNEL-LABEL logic: "reader-ROLE-only interfaces accepted from
  any peer because only reader profiles carry those sends" —
  this works precisely because exactly ONE snap
  (ubuntu-desktop-a11y) carries the reader sends.
- The desktop-legacy-shared READ surfaces are received only from
  {snap.ubuntu-desktop-a11y.*, unconfined} — a THIRD-party
  reader snap is denied at exactly those surfaces, because
  AppArmor has no "labels holding a reader grant" expression:
  the policy cannot say "any label that connected the reader
  plug".
- The one-reader model is enforced by D9's build-time assertion
  (4939fa6: one-provider assertion) + the connected-slot
  snippet structure.

## What a third-party reader needs

1. Label publication: a mechanism by which snapd publishes "the
   set of labels holding a reader grant" into the provider's
   (and consumers') profiles at connect/disconnect time — i.e.
   upstream snapd label plumbing (the T29 review's stated
   requirement).
2. The reader-role plug contract generalized: what a
   third-party snap must implement to be a reader (the sends:
   the reader-only interface set — the four tree-read surfaces
   are READS on the provider side; the reader SENDS are the
   method-call interfaces).
3. Policy generation: the provider profile's receive rules and
   the consumer profiles' rules must regenerate from the
   granted-label set on every connection change (dynamic
   profile updates).
4. Verification: a second reader snap (a minimal test reader)
   exercising the full flow: connect, join the bus, read
   trees, speak — plus the must-deny probes (a non-reader snap
   must still be denied everywhere).

## Tasks

1. UPSTREAM-FIRST: search snapd upstream for existing
   mechanisms (label publication, interface-connected-label
   sets, dynamic profile regeneration on connect) and any prior
   art (e.g. how other interfaces with role-like semantics
   handle multiple providers/consumers).
2. DESIGN: the minimal snapd mechanism (candidates: a
   snap-declaration-driven label list in the provider profile;
   a new interface refinement; an apparmor feature "label
   sets"). Identify the smallest upstream-able change.
3. TEST READER: build a minimal second-reader snap (a stub
   that performs the reader sends) to prove the mechanism
   end-to-end on a disposable bake.
4. INTEGRATION: the a11y snap + the interface policy updates +
   the one-provider assertion relaxation (D9's build-time
   assertion must become role-aware instead of
   snap-count-aware).
5. GATES: the full reader flow set + must-deny re-probes on a
   disposable bake with TWO readers connected.

## Status

- [2026-11-17] Todo created. NOT STARTED. Blocked on upstream
  snapd label plumbing (task 1 decides whether this is a
  fork-side patch or an upstream proposal — same channel as the
  accessibility-provider series). The one-reader pin stands
  until this lands.
