# Global socket activation from real XDG_RUNTIME_DIR (SD193)

## Impact / Priority

Low. Not currently blocking anything — no concrete failing case has
been hit yet. This is a speculative snapd feature request carried
forward from the original design docs; investigation needed to
determine whether it's actually required or whether the described
workaround is sufficient.

## Context

Extracted from `proposed-plan.md`'s "Stage 4 - Parking lot" (explicitly
deferred there). Reference: `splitting-the-core-desktop-base-snap.md`'s
"SD193 - Global socket activation".

Some services need socket activation from sockets located in global
folders (like the real, host XDG_RUNTIME_DIR) rather than a
snap-private one. The original design doc describes a workaround (a
one-shot daemon that symlinks from the global folder into the
snap-specific one) as "ugly" and states that proper snapd support for
this would be desirable.

## Next steps (not started)

- Wait until Stage 2/3 of the base-splitting work (see
  `20260922-split-core26-desktop-base-snap.md`, particularly the
  pipewire/xdg-desktop-portal split in Stage 3C) hits a concrete case
  that actually needs this, rather than pursuing it speculatively.
- If/when a concrete case is hit: evaluate whether the existing
  symlink-based workaround is acceptable long-term before proposing a
  new snapd feature — a real snapd change should only be pursued if
  the workaround proves genuinely unworkable in practice.
