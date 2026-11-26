# Fix KDE screen lock: AppArmor denials crash KWin instead of the greeter

## Impact / Priority

Medium. The desktop itself works (boot, SDDM login, Plasma renders;
verified 2026-10-08 on the stock-core26-based session candidate built
that morning), but any screen-lock attempt does not lock: the greeter
dies, takes KWin down with it, and the session restarts -- so the
desktop simply reappears. Lock/unlock is a core session feature
(`20261001-remove-kde-core26-desktop-dependency.md` Step 17 lists it),
and its failure mode (compositor death) is worse than a cosmetic miss.

## Why it is only surfacing now

Screen lock was never re-verified after the content split and base
switch: the 20261001 dependency-removal resolution explicitly skipped
the acceptance matrix ("no ... polkit acceptance matrix was run"). Its
known-issues list records plasma-powerdevil (session-bus dbus_bind) and
plasma-polkit-agent (/proc/<pid>/cgroup denial, libxcb-cursor0 history)
but not screen lock -- this note is the first capture of the lock
signature on the split stack. Not caused by the 2026-10-07/08 build
system work (shallow clones, SDK staging, retry, base plumbing); the
per-app AppArmor profiles were untouched.

## Observed signature (2026-10-08)

Candidate image with `plasma-desktop-session` 20261008+git8f10f1f, base:
core26.

Trigger: lock attempt (user-initiated). kscreenlocker_greet runs as a
child of the kwin Wayland compositor and inherits profile
`snap.plasma-desktop-session.plasma-kwin-wayland`:

- apparmor DENIED open, class=file, requested_mask="r":
    /usr/share/fontconfig/conf.avail/
    /usr/share/fonts/
    /usr/share/fonts/truetype/
    /usr/local/share/fonts/
  (fontconfig scanning the base-provided font tree)
- USER_AVC apparmor DENIED dbus_method_call on the system bus, from the
  same profile:
    /org/freedesktop/login1, org.freedesktop.login1.Manager,
    members CanPowerOff and CanReboot (lock screen power buttons)
- then: "Failed to acquire watch file descriptor" (EACCES on an openat;
  exact path not yet identified -- capture it with a full kernel AVC
  dump on a fresh attempt during the fix)
- then: "The Wayland connection broke. Did the Wayland compositor die?"
- kwin-wayland service exits and restarts; user manager tears the
  session down; desktop reappears unlocked. journalctl
  _SYSTEMD_USER_UNIT="snap.plasma-desktop-session.*" shows no other
  service failures.

## Scope / Hypotheses

The greeter needs legitimate policy, not content: the fonts ARE present
(base-provided on stock core26); this is an AppArmor gap, not a missing
file. Two independent denial classes to resolve:

1. File reads for the greeter under the plasma-kwin-wayland profile
   (font/fontconfig trees; plus identify the "watch file descriptor"
   EACCES path).
2. System-bus logind access for the lock screen's power controls.
   Decide between an interface plug (login-session-control? or a
   dedicated logind-observe style plug) and explicit dbus rules -- note
   `20261001-remove-kde-core26-desktop-dependency.md` records a
   separate known plasma-powerdevil dbus_bind issue on the session bus;
   keep the two fixes distinct.

Also decide whether kscreenlocker_greet should keep running under the
kwin-wayland profile (it inherits it as a compositor child) or deserves
its own routed app/profile like the other session components -- the
routing design (one profile per Plasma component) is the repo's
established model, but the greeter is launched by KWin itself, so a
separate profile may require a launcher indirection. Document whichever
is chosen.

## Fix plan

One commit in plasma-desktop-session (policy fixes are their own commit
per the task rules; do not fold into content or build changes):

1. Reproduce on the candidate image; capture the COMPLETE denial set on
   one lock attempt (kernel AVC log + journalctl --user-unit),
   including the un-identified EACCES openat path.
2. Add the minimal profile/permission fix for the font reads and the
   logind member calls (or plug wiring) in snapcraft.yaml's
   plasma-kwin-wayland app.
3. Rebuild the session snap, the image (the image build,
   `build.sh --desktop kde`), boot, and verify the full lock path:
   trigger lock (Meta+L and `loginctl lock-session`), kscreenlocker_greet
   renders the lock UI, power buttons enumerate, authentication unlocks,
   desktop returns intact (no kwin restart in the journal), second lock
   works.
4. Record remaining/accepted denials; do not broaden the profile to mask
   unrelated failures (task rule: never solve a missing content path by
   broadening AppArmor).

## Related reading

- `20261001-remove-kde-core26-desktop-dependency.md`
  (routing model, known-issues list, skipped acceptance matrix)
- kscreenlocker_greet rendered correctly on the pre-split stack
  (recorded in the project documentation).
- The KDE gadget connections / session architecture are recorded in the
  project documentation.

## Resolution (2026-10-13)

Resolved by the screen-lock rework tracked in
`20261013-fix-kde-screen-unlock.md` (plasma-desktop-session base
switched to core26-desktop so confined PAM runs against the fixed
chkpwd helpers - fe296ef; pam-unix-chkpwd wired for kwin-wayland -
52269e6/b7d53c2; base /usr,/lib paths moved last in LD_LIBRARY_PATH -
fe296ef/57f8615).

Acceptance per this note's Fix plan step 3 verified end-to-end on a
fresh image (2026-10-13): lock engages, kscreenlocker greeter renders
and stays alive, password prompt appears, unlock works (3 consecutive
cycles), desktop returns intact with no kwin restart in the journal -
the 2026-10-08 denial signature (font reads / logind CanPowerOff /
watch-fd EACCES killing kwin) no longer occurs. The logind side is
visibly wired (login-session-control plug on kwin-wayland in
snap/snapcraft.yaml); the individual commit that cleared the font-read
class was not pinpointed (the signature disappeared across the
base-switch rework) - noted here rather than re-derived.
