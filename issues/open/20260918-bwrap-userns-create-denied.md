# bwrap/userns_create denied inside the confined session

## Impact / Priority

Medium-High, but currently UNKNOWN BLAST RADIUS -- needs someone to
identify which real app/feature actually calls `bwrap` (bubblewrap)
inside this confined session before its true user impact can be
assessed. Flagging as a priority to investigate specifically *because*
it's unknown, not because it's confirmed to be causing a specific
visible symptom yet.

What `bwrap`/user-namespace sandboxing is used for in a normal GNOME
desktop: Flatpak apps use it for their own internal sandboxing, and a
growing number of GNOME/Flatpak-adjacent tools (some portal backends,
some sandboxed helper processes, xdg-desktop-portal's document portal
in some configurations) also use it. If any snap-packaged or
Flatpak-installed app on this image relies on `bwrap` to create its own
inner sandbox, that specific app will fail outright or silently degrade
to a less-sandboxed mode -- this is not "the desktop is broken", it is
"a specific class of app that uses double-sandboxing won't work", which
could range from invisible (if nothing on this image currently uses
bwrap) to "this specific app never launches" (if something does).
Concretely worth checking on this image: does the confined session's
Firefox (via App Center) or any other snap use `bwrap` for its own
content-process sandboxing? A "yes" here would make this a real,
user-visible "the browser renders pages but crashes/misbehaves in a way
tied to sandboxing" or "certain sites/features silently run
unsandboxed" bug, not just a log line.

## Context

Originally flagged as one of several "narrower gaps, not architectural
blockers" in `20260915-followup-confined-session-apparmor-gaps.md` (now
closed out/split -- see that file's 2026-09-18 update). Re-verified
live and independently reproducible: on a fresh boot of the test VM
(confined session up, `gnome-shell` confined), within the first minute
of session startup, `bwrap` itself reported "failed to find
unprivileged_userns profile" and the journal showed:

    AVC apparmor="DENIED" operation="userns_create" class="namespace"
    profile="snap.ubuntu-desktop-session.ubuntu-desktop-session"
    pid=3273 comm="bwrap" requested="userns_create" denied="userns_create"
    execpath="/usr/bin/bwrap"

This fires automatically during normal session startup (not triggered
by any deliberate user action in this test), so whatever calls `bwrap`
here does so unconditionally early in the session -- worth finding out
what that caller is (check the parent process of the `bwrap` pid, or
correlate the timestamp against the session-startup unit sequence) as
the first investigation step, since that will directly answer the
"what does this actually break" question above.

## Next steps

1. Identify the actual caller of `bwrap` during session startup
   (`ps`/`pstree` around the denial's timestamp, or re-run with
   `journalctl` correlation) -- this is the single most useful next
   fact, since it turns this from "a denial exists" into "here is
   specifically what breaks".
2. Once the caller is known, determine whether it degrades gracefully
   (falls back to no sandboxing, logs a warning, keeps working) or
   fails outright (crashes, refuses to start, silently does nothing) --
   this determines the real priority.
3. If a fix is needed: this is the same class of gap as the
   `unprivileged_userns` AppArmor profile requirement seen on modern
   Ubuntu/Debian kernels with restricted unprivileged user namespaces
   (`kernel.apparmor_restrict_unprivileged_userns=1`) -- likely needs
   either an AppArmor policy addition granting `userns_create` to the
   `ubuntu-desktop-session` snap profile (with appropriate
   nested-profile restrictions so it isn't a full sandbox-escape hole),
   or a snapd interface addition, whichever the actual calling app's
   needs dictate. Check whether upstream `bubblewrap`/`flatpak`
   packaging on regular (non-Core) Ubuntu ships a matching AppArmor
   profile allow-list for this exact scenario, as a reference.

## Validation

1. Confirm the caller and its concrete failure mode from step 1-2
   above.
2. If a fix is applied, confirm the specific denial disappears from
   `journalctl -b 0` on a fresh reboot, and the caller's feature that
   depends on `bwrap` actually works end-to-end (not just "no denial
   logged").
