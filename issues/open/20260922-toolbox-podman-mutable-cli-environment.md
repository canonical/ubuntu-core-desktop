# Toolbx/Podman-style mutable CLI environment

## Impact / Priority

Low (explicitly deferred, long-term goal only). No current user impact —
this is forward-looking design guidance, not a bug or a piece of work to
schedule yet.

## Context

Extracted from `proposed-plan.md`'s "Stage 4 - Parking lot" (explicitly
deferred there) and from the project's original "What we want"
principles. Ubuntu Core Desktop's user environment can't be literally
immutable in the sense of preventing any modification — users will want
a containerised, mutable CLI environment for ad-hoc package
installs/dev work, similar to Fedora Silverblue's use of Toolbx/Podman.

This is explicitly out of scope for current work. The only actionable
requirement right now is a constraint on other design decisions: don't
make choices in the base-splitting work (see
`20260922-split-core26-desktop-base-snap.md`) that would foreclose this
later — e.g. don't hardcode assumptions that /home or /var are so fully
snap-owned/immutable that a future toolbox container couldn't get a
normal bind-mount into them.

## Next steps (not started)

- No action needed until the base-splitting work (Stage 2/3) is
  substantially complete and the project is ready to think about
  user-facing mutability. When that time comes, revisit this as new
  work, evaluating Toolbx/Podman integration against whatever the
  base/session architecture looks like by then.
