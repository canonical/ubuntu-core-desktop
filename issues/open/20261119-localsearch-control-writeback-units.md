# localsearch-control-3/writeback-3: missing unit redirects (203/EXEC)

## Impact / Priority

Priority: Low. The main indexing works (search in Files, recents).
The gaps: the index control interface (clients managing/refreshing
the index) and the metadata writeback (changes written back into
files) fail when activated. Low frequency (on-demand activation),
but a functional gap for anything using those D-Bus APIs.

## Context

Written 2026-11-19. NOT accessibility-related: this is the GNOME
file-search indexer (LocalSearch) infrastructure — a general
desktop-session issue on the Ubuntu Core Desktop image.

## Background

localsearch-3.service (the main indexer) died with 203/EXEC on
every boot: its unit execs /usr/libexec/localsearch-3, a binary
that only exists inside the content snap's tree, while the unit is
exec'd by the host user manager OUTSIDE the snap namespace. FIXED
in T46/T50 (the binary layout-bound into the session snap + the
base-side unit-redirect drop-in
(ExecStart=/snap/bin/ubuntu-desktop-session.localsearch-3), landed
as 0ed202e in core-base-desktop, base rebuilt 20261118+desktop,
verified live: the indexer active/running confined, zero 203s
(T58 re-verified)).

## The remaining gap

LocalSearch has two D-Bus-activated companion processes whose
units carry the SAME broken exec path:

- localsearch-control-3.service (the index-control interface)
- localsearch-writeback-3.service (writing metadata back into
  files)

The T46/T50 redirect was applied ONLY to localsearch-3.service.
When D-Bus activates the companions (on demand — e.g. a client
calls the index control interface, or a file change triggers the
writeback), they will fail with the same 203/EXEC. T58 flagged
this as a follow-up (the T58 restructure report's "F5" note;
item 3 of the T58 entry in
`20261110-thin-line-a11y-snapped-provider-spike.md`).

## Tasks

1. AUDIT: list ALL the localsearch/tracker-* user units in the
   image (systemctl --user list-unit-files as a session user, or
   the unit files in the content snap tree) + their ExecStart
   paths — identify every unit with the same broken exec shape
   (the expected: localsearch-control-3, localsearch-writeback-3;
   check also tracker-miner-fs-3.service variants and any
   others).
2. THE FIX: the same base-side unit-redirect drop-ins per unit
   (the 0ed202e pattern:
   ExecStart=/snap/bin/ubuntu-desktop-session.<binary> — the
   session snap must ship the binaries: check the session snap's
   gnome tree for the control/writeback binaries; add the
   layout binds if missing, mirroring the T46 localsearch-3
   treatment).
3. VERIFY: D-Bus-activate each unit (gdbus call / a client
   request) on a disposable VM → the units start confined, zero
   203s; the indexer + the companions coexist.
4. ALSO CHECK: the tracker-miner/rss/rss-feeder or other miner
   units that might activate on demand.

## Status

- [2026-11-19] Todo created. NOT STARTED. Low priority (the main
  indexer works; the companions activate on demand). The fix is
  mechanical (the T46/T50 pattern per unit). The base rebuild +
  the bake ride with the next base change (no dedicated bake
  needed — bundle with the next core-base-desktop push cycle).
