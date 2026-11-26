# orca crash-loops on any broken at-spi state instead of degrading gracefully

Date: 2026-11-20

Found during the Ubuntu Core Desktop a11y lifecycle testing (the T41
finding N3 — the full evidence is in the T41 C8/C9 write-up; also
recorded as the a11y spike todo's [2026-11-19] T41 entry).

## Impact / Priority

The screen reader is the primary a11y surface: a crash LOOP (vs a
graceful degradation) means the user gets no reader AND the system
burns CPU on the restart cycle, with gdm potentially parking the
session (the T41 N4 companion finding — the bus death took the
whole session down). The robust reader degrades: it announces the
failure (the accessible "screen reader cannot start" state) and
retries with backoff, keeping the system usable.

## The defect

orca (the screen reader) crash-loops with SIGSEGV against ANY
broken at-spi state — the crash follows the BUS STATE, not the snap
revision: x1 (the known-good revision) crashed identically to x2
when the at-spi environment was broken. One broken at-spi component
(the registry, the bus launcher, a denied connection) makes orca
die in a restart loop instead of degrading.

## Tasks

1. UPSTREAM-FIRST: search orca's GitLab (GNOME/orca) for the
   at-spi connection failure handling and the crash-loop reports;
   also check the at-spi2-core side (the registry crash handling
   in the clients).
2. CHARACTERIZE THE CRASH: capture the SEGV backtrace from the
   broken-state repro (the T41 recipe: the broken at-spi env —
   the denied registry connection, the dead bus launcher; the gdb
   attach or the coredump config — the T41 incident had no
   coredump generated: check the systemd-coredump storage config
   first).
3. THE FIX: the graceful degradation in orca (the at-spi
   connection failure → the bounded retry with the backoff + the
   accessible failure announcement, not the SIGSEGV loop); if the
   crash is in the at-spi/pyatspi bindings, the fix may belong in
   at-spi2-core (the binding's error handling) — attribute
   correctly after the backtrace.
4. SUBMIT upstream (GNOME/orca or at-spi2-core per the
   attribution) with the repro + the backtrace.

## Status

[2026-11-20] Issue created. NOT STARTED. The T41 recipe + the
broken-state harness exist in the T41 write-up; the current snapd
(g80) narrows the receives — verify the crash still reproduces on
the current lineage before filing (the T41 incident was on the
g72-era snapd).
