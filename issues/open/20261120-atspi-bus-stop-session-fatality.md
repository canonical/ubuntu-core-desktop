# At-spi bus death kills the whole graphical session (gdm parks on the greeter)

## Impact / Priority

The accessibility bus is a SUPPORT service — its death should
degrade the a11y features (the reader stops working), not take
the desktop down. The current coupling means any at-spi component
crash or stop (the a11y snap's lifecycle operations — the T41
test was exactly the a11y snap's refresh/revert scenario)
produces a full session fatality: the user loses their work and
the session cannot recover without a reboot.

## Context

Written 2026-11-20. Found during the Ubuntu Core Desktop a11y
lifecycle testing (the T41 finding N4 — the full evidence in the
T41 lifecycle report's C8/C9 sections and the spike todo's
2026-11-19 T41 entry in
`20261110-thin-line-a11y-snapped-provider-spike.md`).

## The defect

Stopping the at-spi bus (org.a11y.Bus — the accessibility bus
launcher/service) MID-SESSION killed the entire test VM's
graphical session: gnome-shell and the session died, gdm parked
on the greeter, and NO re-autologin occurred (the T41 note: "the
D8 cascade has a session-fatality tail").

## The mechanism (to investigate)

Which component reacts fatally to the bus death: gnome-shell
(the AT-SPI connection loss → the abort?), mutter (the at-spi
device listeners?), or the gnome-session manager (the dependency
chain: the a11y bus as a session target dependency → the
cascade)? The T41 evidence: the session died within seconds of
the bus stop — the dependency-chain failure (the gnome-session
target's Requires/BindsTo on the a11y bus unit?) is the prime
suspect.

## Tasks

1. THE MECHANISM: reproduce (the disposable VM: stop
   org.a11y.Bus.service mid-session, watch what dies in order —
   the journal + systemctl --user list-jobs during the cascade)
   and identify the fatal dependency (the unit chain or the
   process monitoring the bus).
2. UPSTREAM-FIRST: the gnome-session/mutter/at-spi2-core repos
   for the dependency design (should the a11y bus be a session
   dependency at all? — stock GNOME treats it as optional) and
   any existing crash-on-bus-death handling.
3. THE FIX PROPOSAL: decouple the session from the a11y bus (the
   a11y features degrade when the bus dies: the AT-SPI clients
   get the clean "no bus" errors, orca stops gracefully, the
   session survives) — the unit-level fix (drop the dependency
   from the session targets) or the process-level (the clients
   tolerate the bus loss).
4. SUBMIT upstream per the attribution with the cascade
   evidence.

## Status

- [2026-11-20] Todo created. NOT STARTED. The T41 repro recipe
  (the bus stop mid-session) + the disposable-VM harness exist
  in the T41 deliverable; the incident was on the g72-era
  snapd — re-verify on the current lineage (g80) before
  filing.
