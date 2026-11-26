# Support multiple desktop session snaps (greedy plugging / UD086)

## Impact / Priority

Low. Not currently blocking anything — this only matters once GNOME and
KDE desktop sessions both need to coexist installed on the same system
and be switchable at the login screen. A real user today only ever has
one desktop session snap installed, so there is no observed end-user
impact yet; investigation needed once a second desktop session (KDE) is
actually being shipped alongside GNOME to determine what actually
breaks without this.

## Context

Extracted from `proposed-plan.md`'s "Stage 4 - Parking lot" (explicitly
deferred there, not needed yet). Reference:
`splitting-the-core-desktop-base-snap.md`'s own pointer, "UD086 -
Supporting multiple desktop sessions on Core Desktop".

When multiple desktop-session snaps are installed side by side (e.g.
ubuntu-desktop-session for GNOME and a KDE equivalent), each needs to
be able to plug shared content/interfaces (e.g. a content-interface
GNOME/KDE runtime snap, or a display-manager-facing session-registration
mechanism) without the connections being ambiguous or requiring manual
per-snap wiring. This likely needs snapd's "greedy plugging" support
(auto-connecting a plug to any suitable slot without requiring an exact
1:1 declared pairing) to work correctly across more than one desktop
session snap at once.

## Next steps (not started)

- Once Stage 2/3 of the base-splitting todo (see
  `20260922-split-core26-desktop-base-snap.md`) has both a GNOME and a
  KDE session snap installable side by side, actually try installing
  both and switching between them at the GDM greeter. Only investigate
  snapd changes if this reproduces a concrete failure — don't design a
  solution to a problem that hasn't been confirmed yet.
