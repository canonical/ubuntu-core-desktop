# Migrate the build.sh gadget-connections list into the store gadget

## Impact / Priority

High - this gates the signed-model roadmap rather than being a live
user-facing bug. A grade: signed image built from today's connections
would fail first boot outright: stock upstream snapd rejects name-based
gadget connection endpoints during gadget validation, and gadget
validation failure is fatal at seed. Today's dangerous dev images are
unaffected; the priority comes from blocking phases 3-4 of
`20261009-build-and-publish-on-the-snap-store.md` (signed models +
store-only image build).

Date: 2026-10-29
Related: `20261009-build-and-publish-on-the-snap-store.md` and
`20260915-app-center-installed-snaps-need-desktop-interface-connections.md`
(runtime-installed apps are out of scope here: gadget connections only
apply during seeding/remodeling)

## Current state

- The dev images' full connection list lives in build.sh
  (gnome_gadget_connections/kde_gadget_connections), patched into the
  unsquashed local gadget's gadget.yaml at image build, with snap-NAME
  endpoints because dangerous local snaps have no snap-ids.
- Name-based endpoints exist only via the fork's snapd commit
  e7cc2628e6 "Support name-based gadget connection endpoints" (branch
  desktop/26). NOT upstream: upstream snapd's parseSnapIDColonName
  accepts <snap-id>|system only (verified against a freshly fetched
  upstream/master on 2026-10-29).
- The real store gadget (pc-amd64-gadget-desktop/gadget.yaml:78-115)
  already carries a snap-ID-keyed connections stanza - the production
  mechanism exists - but its list is stale vs build.sh: no pipewire or
  audio entries, no portal dbus, no snap-store/firefox entries, and
  session:upower-observe still targets the implicit system slot, which
  no longer exists since Stage 3B moved upowerd out of the base
  (core26-desktop has no /usr/libexec/upowerd, so upower-observe's
  ImplicitOnCore=IsExecutable("/usr/libexec/upowerd") is false and the
  connection is silently skipped as "ignoring missing slot").
- On dangerous images every connection passes policy only because
  unasserted snaps have no snap-declarations and snapd's connect
  checker skips policy entirely in that case (overlord/ifacestate/
  helpers.go: "installed with dangerous, so the security check should
  be skipped").

## Blockers for grade: signed

1. Snap-name endpoints require the fork-only snapd patch; stock snapd
   fails gadget validation (fatal at seed). Production must use
   snap-ids (which exist once snaps are store-published) or the patch
   must be upstreamed.
2. Policy enforcement starts: every gadget connection is evaluated
   under connection policy, and several are base-declaration-denied by
   default for app-provided slots on UC: wayland/x11
   deny-connection{on-classic:false} (builtin/wayland.go, x11.go),
   pipewire and pulseaudio deny-connection + deny-auto-connection
   (builtin/pipewire.go, pulseaudio.go), and desktop even
   deny-installation{slot-snap-type:app} (builtin/desktop.go). Each
   needs allow grants in the involved snaps' store snap-declarations
   (session snap slots; pipewire audio slots), and it is unverified
   whether Firefox's existing store declaration permits connecting to
   app-provided wayland/x11 slots at all.
3. The list lives in the wrong artifact: a signed build consumes the
   store-signed pc-desktop gadget; build.sh cannot patch it (and the
   publish todo's phase 4 drops the local gadget input entirely).

## Constraint (explicit project requirement)

The dangerous dev fast-path MUST keep working throughout and after the
migration - it is the local testing loop (rebuild the image with
`build.sh`, boot it in the test VM). Nothing here removes build.sh's
dev patching; the migration adds the production path and converges
both onto a single list.

## Plan (staged; each step independently verifiable)

1. Make pc-amd64-gadget-desktop/gadget.yaml the single source of truth:
   add all current build.sh connections (GNOME + KDE), snap-ID-keyed
   (ids already exist for ubuntu-desktop-session
   LVkazk0JLrL0ivuHRlv3wp3bK1nAgwtN, pipewire, udisks2, upower,
   network-manager, bluez; add the rest as the store-publish work item
   lands them). Fix the dead upower-observe entry (-> upower:upower)
   while there. Reconcile the KDE system:pipewire / system:pulseaudio
   entries (likely silent no-ops on UC - decide whether KDE adopts the
   pipewire snap).
2. Derive the dev path from the gadget instead of maintaining a
   duplicate: build.sh already unsquashes the gadget - read its
   connections stanza and rewrite snap-id endpoints to snap-name
   endpoints for locally built snaps lacking ids (the mapping is
   known; the dev snapd supports name endpoints via e7cc2628e6).
   Store-installed snaps (network-manager, bluez, ...) keep their ids.
   If this proves awkward, keep the duplicate list but add a build-time
   check that fails when it drifts from the gadget (drift already
   happened once).
3. Declaration/policy audit, per connection, against the real store
   snap-declarations (feeds the publish todo's phase 3; grants are
   store-team tickets, not code): session snap slot grants
   (desktop/wayland/x11/...), pipewire audio slot grants, and the
   Firefox plug-declaration check from blocker 2.
4. Optional/parallel: upstream e7cc2628e6. Not required if production
   uses snap-ids, but it removes the fork-only behavior the dev path
   depends on and keeps the fork divergence shrinking.

## Validation

Every step must pass BOTH:
- Dangerous dev build: rebuild the image (`build.sh` gnome|kde) and
  boot it; `snap connections <session snap>` shows the identical
  connection set as before the change (diff against the pre-migration
  list).
- Signed-model image: boots to GDM/SDDM with all connections applied;
  snapd logs show no "ignoring missing" gadget-connection lines for
  plugs/slots that exist in the model, and no connection policy
  denials.
