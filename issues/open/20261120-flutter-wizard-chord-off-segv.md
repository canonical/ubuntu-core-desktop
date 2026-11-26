# gnome-initial-setup: screen reader toggle OFF segfaults the wizard UI

Date: 2026-11-20

Found during the Ubuntu Core Desktop a11y gate-8 session (the T52
residual — the verbatim SEGV evidence was captured in the T52
wizard-shell-confinement session and recorded as the a11y spike
todo's [2026-11-18] T52 entry).

## Impact / Priority

A blind user testing whether the reader works will toggle it OFF at
some point — and crash the installer. The crash loop back to the
initial-setup shell makes the first-boot flow unreliable for exactly
the users the a11y stack exists for.

Impact derived from the original note's symptoms.

## The defect

In the first-boot wizard (gnome-initial-setup with the Flutter-based
Ubuntu Core Desktop wizard UI), toggling the screen reader OFF (the
Super+Alt+S chord, or the a11y state change that reaches the
Flutter semantics tree) SEGFAULTS the wizard UI: the verbatim SEGV
was captured in the T52 session (the wizard UI dies, the session
crash-loops back to the initial-setup shell).

## The trigger chain (observed live)

The chord-ON direction works (the screen reader starts, the a11y
icon appears, orca speaks). The chord-OFF direction (the reader
toggling off while the wizard UI is the focused surface) hits the
Flutter semantics-tree update path and segfaults — the a11y state
change (the AT-SPI events from orca shutting down) reaches the
Flutter engine's semantics handling and crashes it.

## Tasks

1. UPSTREAM-FIRST: identify the wizard UI's repo (the Ubuntu Core
   Desktop Flutter installer — ubuntu-desktop-flutter/
   ubuntu-desktop-provision's Flutter tree) and search for the
   existing a11y/semantics crash issues (the Flutter engine's
   semantics tree disposal on the AT-SPI events is a known crash
   class).
2. REPRO MINIMALLY: the wizard + the chord off + the verbatim
   SEGV (the T52 recipe: the disposable VM, the chord via
   vncdotool, the backtrace from the journal/coredump).
3. THE BACKTRACE: capture the coredump/backtrace (the T52 incident
   had "without generating a coredump" for the gnome-shell case —
   the Flutter process's coredump handling may need the systemd-
   coredump config; capture via the direct gdb attach on the
   repro).
4. THE FIX: likely in the Flutter engine's semantics handling or
   the wizard's integration (the semantics-tree disposal on the
   AT-SPI events); if the engine fix is too heavy, the wizard-side
   guard (the semantics listeners lifecycle) may be the practical
   patch.
5. SUBMIT upstream with the verbatim SEGV + the repro recipe.

## Status

[2026-11-20] Issue created. NOT STARTED. The T52 write-up has the
verbatim incident; the repro harness (the disposable VM + the chord
recipes) exists in the T52/T51 write-ups.
