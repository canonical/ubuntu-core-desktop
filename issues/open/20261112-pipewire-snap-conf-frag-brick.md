# Pipewire snap: user config fragment can brick the session audio daemon

## Impact / Priority

A normal desktop user operating INSIDE their own session has no
day-one impact (their own context works; this only bites when a
config drop-in is added — e.g. following pipewire documentation
examples that reference null-sink, which is exactly what happened
here). The blast radius is large when it bites: total session
audio loss + a crash loop, from a user-writable file, with an
error message (missing module) that does not self-explain the
ifexists/no-fail escape hatch.

Priority per the note's status log: low-medium (no
normal-desktop-user impact until a config drop-in is added; the
blast radius is total-session-audio-loss when it bites).

## Context

Written 2026-11-12. Found during the accessibility gate-8 audio
work (T31 — the full evidence in the T31 RTP-audio report). The
finding surfaced while implementing the (now-parked) guest-side
RTP audio route for the Ubuntu Core Desktop thin line, but it is
a GENERAL pipewire-snap behavior, not a11y-specific.

## The finding (reproduced)

Verbatim evidence in the T31 report, section "PIPEWIRE SNAP
FINDING". On Ubuntu Core 26 with the pipewire snap (pipewire
1.6.2-1ubuntu1.2, revision x1 at the time), a user-writable
pipewire config drop-in at

    ~/snap/pipewire/x1/.config/pipewire/pipewire.conf.d/<name>.conf

(SNAP_USER_DATA path — the snap HONORS user drop-ins, proven by
the crash itself) containing a `context.modules` entry that loads
a module the snap does not ship — observed:
libpipewire-module-null-sink.so — puts the session audio daemon
into a permanent systemd restart loop:

    could not load mandatory module "libpipewire-module-null-sink":
    No such file or directory
    failed to create context
    -> snap run exit 254, Restart=always (reproduced x3 in ~2s)

Recovery: remove the fragment (verified).

Two distinct defects are stacked here:

1. THE SNAP DOES NOT SHIP libpipewire-module-null-sink.so.
   Upstream pipewire 1.x ships it in the standard install; the
   distro host deb (the Ubuntu 26.04 pipewire package) lacks it
   too per T31's check — i.e. the snap matches the deb, but the
   module referenced in common pipewire documentation/examples is
   absent from both. Whoever is wrong (upstream packaging vs
   docs), the gap is real and undocumented.
2. MANDATORY-MODULE FAILURE IS FATAL BY DEFAULT. A
   `context.modules` entry without `flags = [ ifexists, no-fail ]`
   aborts the whole context ("failed to create context") rather
   than skipping the missing module. Combined with (1) and the
   snap's Restart=always, a ONE-LINE user config typo bricks ALL
   session audio (and the restart loop journals at a high rate).

## Investigation tasks (before reporting)

1. CHECK UPSTREAM FIRST:
   - pipewire upstream
     (gitlab.freedesktop.org/pipewire/pipewire): is
     libpipewire-module-null-sink supposed to ship in 1.x
     installs? Search issues for "null-sink not found",
     "mandatory module", "ifexists no-fail".
   - The Ubuntu pipewire package (26.04): does the deb ship it
     (dpkg -L pipewire | grep null-sink on a deb-based system)?
     T31 checked and found it absent — confirm and note the
     version.
   - The snap (canonical/pipewire-snap repo): issues about
     missing modules / config-brick crash loops; check whether
     the snap intentionally trims modules.
2. Decide the report target(s):
   a. pipewire upstream: documentation gap (examples referencing
      null-sink without noting availability) and/or the
      fail-fatal-by-default behavior for missing modules — is
      `flags = [ ifexists, no-fail ]` the sanctioned escape
      hatch, and should the error message hint at it?
   b. The pipewire SNAP (canonical): ship null-sink (match
      upstream 1.x shape) and/or harden the snap against user
      config bricks (e.g. a watchdog note in the snap docs; at
      minimum document the recovery path).
   c. Possibly both: the module gap (snap/deb packaging) and
      the fatal-default behavior (pipewire core) are separate
      reports.
3. Reproduction package: the exact fragment, the snap revision,
   the verbatim journal lines, the recovery steps (all already
   captured in the T31 deliverable — assemble, do not
   re-derive).
4. OUR OWN STACK NOTE: the parked guest-side RTP audio route
   (see
   `20261110-thin-line-a11y-snapped-provider-spike.md`, the
   2026-11-12 direction-change entry) used exactly this
   mechanism — if it is revived, its drop-in MUST avoid
   unshipped modules and use `flags = [ ifexists, no-fail ]` on
   every context.modules entry.

## Status

- [2026-11-12] Todo created from T31's finding (evidence already
  captured in the T31 report). NOT STARTED. Priority:
  low-medium (no normal-desktop-user impact until a config
  drop-in is added; the blast radius is total-session-audio-loss
  when it bites). The related FINDING 2 (snap tools unusable
  outside the session's systemd-user context) needs NO upstream
  bug — it is an operational constraint for remote testing/
  administration, to be documented as a probe recipe (systemd-run
  --user -M <uid>@.host --pipe --wait /snap/bin/pipewire.wpctl)
  rather than reported.
