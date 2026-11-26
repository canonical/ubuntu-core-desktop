# Project principles for Ubuntu Core Desktop

Standing project-management/architecture principles (not tied to any
specific bug or task). Use these to evaluate any future design choice
for this project.

- Stay as close as possible to upstream Ubuntu Core. Prefer stock
  snapcraft/snapd mechanisms (e.g. content interface) over custom
  workarounds (e.g. a custom "core26-desktop" base string); ideally the
  system boots from a real, unmodified core26/coreNN base.
- Prefer a staged approach: make the smallest change that can be
  independently verified before moving to the next change. Avoid plans
  that require many simultaneous changes across packages to all be
  correct before anything can be tested.
- Compatibility with the existing non-Core Ubuntu desktop and its GNOME
  snaps (e.g. gnome-calculator) matters — don't require existing,
  already-working GNOME snap applications to be modified/rewritten to run
  on Core Desktop.
- We hold the source for all involved packages (including snapd), so we
  are free to modify them if truly required — but the bar for deviating
  from upstream sources should be high; minimize divergence.
- End goal: a real, modern, immutable, confined Ubuntu desktop (in the
  spirit of Fedora Silverblue), not a tech demo — it needs to be genuinely
  usable, not just a proof of concept.
- The system won't be literally immutable for the user — a future
  Toolbx/Podman-style mutable CLI environment is expected eventually.
  This isn't being built now, but current design choices should avoid
  foreclosing it later (e.g. don't assume /home or /var are so
  fully snap-owned that a future toolbox container couldn't get a normal
  bind-mount into them).
