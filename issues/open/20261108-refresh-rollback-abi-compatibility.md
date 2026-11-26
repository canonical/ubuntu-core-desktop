# Define and test refresh/rollback ABI compatibility of snap-path dependencies

## Impact / Priority

PRIORITY: High if/when images are used beyond fresh-install testing —
currently UNTESTED, and that is the honest headline: no refresh or
rollback has ever been exercised on the thin-variant images. What a
real user would eventually observe if this is broken: after a snap
refresh (e.g. gnome-desktop-runtime or kf6-core26 updating), the
greeter fails to start or the session breaks on next login — because
host-side content (loader-path symlinks, unit-routing symlinks, launch
wrappers, GL data links baked into the base) points at
/snap/<snap>/current, and `current` flips during refresh; a revision
that renames/removes a library the base's symlinks or binaries depend
on (e.g. mutter-18, a linked SONAME) breaks the boot path with no
automatic recovery. Severity: potential no-login state after a routine
refresh — but the probability is unknown until tested, which is
exactly what this item must pin down (the original todo's final gate
listed "reboot + snap refresh across the new base" and it was never
run).

## Background

The final independent review flagged this (finding 8): the base's
payload resolves /snap/gnome-desktop-runtime/current and
/snap/kf6-core26/current from host binaries, symlinks, unit files, and
GL discovery independently; a refresh removing a needed path breaks
the greeter; exec-vs-dlopen can mix revisions mid-flip. Related known
noise: the images are dangerous-model with locally-built snaps, so
`snap refresh` against the store currently no-ops with warnings —
which is WHY refresh never got tested organically.

## Work items

1. Define the ABI contract: which paths under /snap/<content-or-
   runtime>/current the base's payload depends on (enumerate: the
   995-hook lib-closure symlinks, gbm/dri/glvnd links, launch
   wrappers' exec targets, the keyring wrapper, mutter/gnome-shell
   paths, kf6 xkb/GL for KDE). Write it down as the compatibility
   surface any refresh of those snaps must preserve.
2. Test refresh locally: refresh the content snaps to a NEW locally
   built revision (same content, different revision — the flip
   mechanics are what's under test), through a full refresh + reboot +
   greeter/login cycle on both desktops.
3. Test the breaking case deliberately: refresh to a revision that
   removes/renames a contract path (simulate by building a runtime
   snap with a moved library) — verify the failure mode is
   diagnosable (not a silent hang) and whether rollback
   (snap revert) recovers the greeter.
4. If the failure mode is bad (no-login, no recovery): design
   mitigation — e.g. refresh-apparmor-style pre-checks, a first-boot
   doctor unit that validates the contract and falls back, or pinning
   refreshes of the runtime snaps via refresh-appawareness/holds until
   the contract is upstreamed into the snaps' own interface
   declarations.
5. Fold the results into the upstream variant PR's documentation
   (the contract is part of what desktop/26 ships).

## Notes

- `snap refresh --list` working from the confined terminal (the
  snapd-socket plug fix) is a prerequisite tool for these tests.
- The same contract question applies to the PROVIDER snaps' $SNAP
  state, but those are self-contained (their own $SNAP paths) — only
  the base-baked absolute paths are in scope here.
