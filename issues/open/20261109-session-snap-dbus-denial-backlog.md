# Session-snap D-Bus/AppArmor denial backlog (non-a11y)

## Impact / Priority

Priority: Medium. Nothing user-visible is known to break from these
today (the apps run; the calls fail and the features degrade), but
they are confinement debt and muddy future denial triage — every new
investigation has to filter around them.

## Context

Written 2026-11-09, spun out of the accessibility work
(`20261109-bring-accessibility-up-to-regular-ubuntu-desktop-levels.md`,
T6b task) so the a11y todo stays focused. These are pre-fix live
denials observed on the running Core Desktop test VM that are NOT
needed for the a11y pipeline and were deliberately left unfixed.

Source: the broad denial sweep (a read-only journalctl pass on boot 0,
2026-11-09): 44 denied dbus sends + 9 signal/binds across session
apps, 13 distinct members.

## Items

1. org.gnome.SessionManager RegisterClient + Properties.GetAll
   denials from 7 OTHER gsd-* apps (besides gsd-a11y-settings, which
   is now granted via the per-tag snippet in snapd fork commit
   66e8b80e01) + gnome-shell screensaver/notifications + portal
   apps. Every gsd plugin registering with the session manager hits
   this; only a11y-settings was granted so far.
   Fix shape: extend the per-tag approach (either one snippet per
   app tag, or generalise RegisterClient/GetAll into the base
   connected-plug snippet for apps that plug systemd-user-control).
   Needs a scope decision: granting these app-wide changes the
   confinement story for ALL plugs of that interface.

2. gsd-sharing: StopUnit denials (x2) — it manages its own user
   unit like a11y-settings does; same per-tag treatment would work.

3. gsd-power: Set/GetManagedObjects/Get denials.

4. xdg-desktop-portal-gnome: org.gnome.Shell signal receives + 5
   file-access denials (details captured in the denial sweep
   report).

5. Expected post-a11y-fix (known, deferred): the user-session
   orca-autostart exec path — confined gnome-session execs
   /usr/bin/orca fine (template ixr rule) but the shebang
   interpreter /usr/lib/python/python3 is outside the template's
   interpreter allowlist (hook 034 deliberately relocated base
   python away from snaps). Primary orca start paths are unaffected
   (gsd -> systemd -> unconfined orca). If T7 shows orca reliably
   starting via gsd alone, this stays a cosmetic journal denial;
   the pre-analyzed fix is a narrow per-tag ixr rule for the two
   spawning apps (gnome-session, gsd-a11y-settings), NOT a
   template-wide rule (would undo hook 034's isolation design).

## Verification

Re-run the sweep post-a11y-fix (T7 does an a11y-scoped DENIED grep;
this backlog needs the full unscoped version) and confirm which
denials remain. Do not chase any denial that the a11y work's new
rules happen to cover.
