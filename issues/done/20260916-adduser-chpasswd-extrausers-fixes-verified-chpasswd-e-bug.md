# adduser and chpasswd +ucd1 fixes verified; chpasswd -e extrausers bug

Status: adduser fix confirmed good. chpasswd fix confirmed INCOMPLETE -
needs a source patch. Live workaround in place on test VM only; nothing
persisted into any build yet.

## Impact / Priority

High. While testing the wizard's "Create your account" step end-to-end,
account creation and password setting were both broken on the first-boot
wizard path: adduser's supplementary-group assignment always failed, and
the password step failed every time, so a user could not be created and
reach the desktop without live hand-patched binaries.

## Context

Continuation of ubuntu-desktop-init.snap wizard testing on the desktop26
test VM, following on from the locale/keyboard/network fixes (see
`20260915-provd-locale-supported-file-missing-wizard-hang.md` and
siblings). Once those were fixed, the wizard reached the "Create your
account" step, which exposed two more, unrelated, pre-existing bugs in
how account creation/password-setting cooperates with Ubuntu Core's
"extrausers" mechanism (accounts not stored in /etc/passwd but in
/var/lib/extrausers/{passwd,shadow,group,gshadow}).

~/git/ucd-ppa (and its byte-identical twin
~/git/noble-ppa-to-resolute-build-dir - confirmed identical via
`diff -rq` and `du -sh`, safe to delete one) already contains a rebuild
plan and pre-built .debs for fixing exactly this class of bug when
moving the old noble-built PPA to a resolute-native rebuild. See
~/git/ucd-ppa/status.txt.

## Bug 1: adduser calls usermod --extrausers, which does not exist

/usr/sbin/usermod on this image has NO --extrausers flag (confirmed via
--help; only useradd/groupadd support it). Stock adduser (the perl
wrapper script) calls "usermod --extrausers -a -G <group> <user>" when
adding a new user to its supplementary groups (sudo, adm, cdrom, dip,
plugdev, users, ...). This always fails:

    adduser[NNNNN]: Calling usermod with --extrausers is unsupported. Please
    raise a bug if you want to see this fixed.

Fix (already built, in ucd-ppa): adduser_3.153ubuntu1+ucd1_all.deb
removes the --extrausers flag from adduser's call to usermod entirely
and just calls plain "usermod -a -G <group> <user>". This works because
the extrausers patches already make the underlying passwd/group I/O
nsswitch/extrausers-aware regardless of the usermod CLI flags used -
usermod itself doesn't need to know about extrausers explicitly for
-a -G to work correctly against /var/lib/extrausers/{group,gshadow}.

Verified this session: extracted adduser/deluser from the .deb (ar+tar
on the host, since the VM has no `ar`), transferred via netcat,
installed as /usr/sbin/adduser and /usr/sbin/deluser. Wizard's "create
user" step (which calls accounts-daemon -> adduser under the hood) now
completes successfully through all supplementary group memberships
(sudo, adm, cdrom, dip, plugdev, users). CONFIRMED WORKING.

## Bug 2: chpasswd's extrausers support only works via the PAM path, not via -e

accounts-daemon's SetPassword D-Bus call always shells out to
"chpasswd -e" with a single "user:<hash>" line (the hash it already
computed itself, e.g. yescrypt $y$...). Even after installing the +ucd1
chpasswd (extracted from passwd_4.17.4-2ubuntu3+ucd1_amd64.deb), this
call still failed every time:

    accounts-daemon[NNNNN]: chpasswd: line 1: user 'user4' does not exist
    accounts-daemon[NNNNN]: chpasswd: error detected, changes ignored
    ... GrpcError: failed to set password: running '/usr/sbin/chpasswd'
        failed: Child process exited with code 1

This looked at first like an environment/sandboxing problem (accounts-
daemon.service runs with ProtectSystem=strict, which does create a
private mount-namespace snapshot at service start - see "side finding"
below - and that red herring cost some time). But it reproduces
identically when chpasswd -e is run manually, standalone, as root,
completely outside of accounts-daemon's sandbox:

    # works: chpasswd (no -e) - goes via PAM (do_pam_passwd_non_interactive),
    # which uses pam_extrausers.so and succeeds:
    echo user8:somepassword | chpasswd
    -> pam_extrausers(chpasswd:chauthtok): password changed for user8

    # fails: chpasswd -e (or -m/-c/-P, i.e. any flag that disables PAM) -
    # goes via the raw open_files()/pw_locate() path and fails:
    printf 'user8:$y$...\n' | chpasswd -e
    -> chpasswd: line 1: user 'user8' does not exist

Root cause (confirmed by reading src/chpasswd.c in
~/git/ucd-ppa/shadow-4.17.4): chpasswd's main() only takes the PAM path
when none of md5flg/eflg/cflg/prefix are set:

    if (md5flg || eflg || cflg || prefix[0]) {
        use_pam = false;
    }

With -e, use_pam becomes false, so it falls through to the classic
open_files()/pw_locate() flow. The 1017_extrausers_chpasswd.patch only
touches open_files():

    bool try_extrausers = strcmp (pw_dbname (), EXTRAUSERS_PASSWD_FILE) != 0 &&
                           access (EXTRAUSERS_PASSWD_FILE, F_OK) == 0;
    if (pw_lock () == 0) {
        if (try_extrausers) {
            pw_setdbname (EXTRAUSERS_PASSWD_FILE);
            spw_setdbname (EXTRAUSERS_SHADOW_FILE);
            open_files ();
            return;
        }
        ... fail ...
    }

i.e. it only switches to /var/lib/extrausers/{passwd,shadow} as a
FALLBACK when locking the normal /etc/passwd FAILS. On this image
/etc/passwd is a perfectly normal, lockable file - it's just empty of
the extrausers-only accounts - so pw_lock() on it always SUCCEEDS, the
extrausers fallback branch never triggers, and chpasswd looks the new
user up in the wrong database every time. This is a real, reproducible
bug in the patch, not an environment/sandboxing issue.

Suggested proper fix (not yet implemented/built): open_files()
shouldn't gate the extrausers fallback on whether pw_lock() *fails* -
it should instead check whether the user(s) actually being changed
exist in the classic passwd db first (or, more simply, prefer
extrausers whenever EXTRAUSERS_PASSWD_FILE exists AND getpwnam() via
the classic db doesn't find the target user), independent of PAM vs
non-PAM code path. This likely needs a small rework of chpasswd.c's
flow so the extrausers/classic decision is made per input line (or at
minimum, before giving up when the classic lookup fails), not solely
inside the pw_lock()-failure branch.

Live workaround applied this session (VM only, NOT a real fix, NOT
persisted anywhere): replaced /usr/sbin/chpasswd with a wrapper script
that detects "-e" invocations and, for users that already exist in
/var/lib/extrausers/passwd, writes the supplied hash directly into
/var/lib/extrausers/shadow itself (bypassing the broken chpasswd.real
-e path entirely); otherwise it falls back to calling the real binary
unmodified. This let the wizard's password step succeed and the whole
flow (account creation -> password -> login -> desktop) was verified
working end-to-end for the first time this session.

## Side finding: accounts-daemon.service and ProtectSystem=strict

accounts-daemon.service has ProtectSystem=strict, NoNewPrivileges=no,
PrivateTmp=no, with
ReadWritePaths=/var/lib/extrausers -/etc/gdm3/custom.conf /etc
-/var/log/lastlog -/var/log/tallylog -/var/mail and everything else
effectively read-only inside its own mount-namespace snapshot. This
snapshot is taken once, when the service (re)starts. Any live
filesystem changes made *after* accounts-daemon.service is already
running (e.g. overlay-mounting /usr/sbin to swap in a fixed
adduser/chpasswd binary) will NOT be visible to it or its children
until the service itself is restarted
(`systemctl restart accounts-daemon.service`). This isn't a bug, just a
gotcha worth remembering for any future live testing that swaps
binaries under /usr while the system is already running - and
something a real package upgrade wouldn't need to worry about, since a
fresh package install naturally happens before the service next
starts.

## Next steps

- Do NOT ship the live "-e direct shadow-write" wrapper anywhere real -
  it's a hack to unblock testing, not a fix.
- Properly patch chpasswd.c's open_files()/use_pam logic so extrausers
  works for the -e path too, rebuild passwd_4.17.4-2ubuntu3+ucd1, and
  re-verify with the wizard (accounts-daemon always calls chpasswd -e,
  so the PAM path is never exercised by the real code paths that matter
  for Ubuntu Core Desktop).
- Once the corrected .debs (adduser +ucd1 as-is; passwd +ucd1 with the
  chpasswd fix above) are confirmed, decide how they get into the
  actual desktop26 image build (this
  ucd-ppa/noble-ppa-to-resolute-build-dir rebuild effort exists
  specifically to stop depending on the old
  desktop-snappers/core-desktop noble PPA for this).
- Per user instruction this session: do NOT use the gnome-shell/
  gnome-session +ucd1 packages from the same PPA - those depend on an
  obsolete --builtin/non-systemd session-management code path that
  upstream GNOME 50.1 (resolute) has fully removed. gnome-session is
  flagged BLOCKED in ucd-ppa/status.txt for exactly this reason.
- Confirm ~/git/ucd-ppa and ~/git/noble-ppa-to-resolute-build-dir are
  safe to de-duplicate (byte-identical, 407M each) - pick one to keep
  and delete the other.

## Resolution (established in later work; note appended on import)

The fix path landed by vendoring the UCD-PPA builds in
`core-base-desktop`: `passwd_4.17.4-2ubuntu3+ucd1` (which makes
`usermod`/`chpasswd` extrausers-aware without any new flag) plus the
matching `adduser_3.153ubuntu1+ucd1` build (which drops adduser's own
`usermod --extrausers` call, a flag that never existed upstream). With
these two packages installed, plain `usermod`/`chpasswd` work against
the extrausers database transparently — check which passwd/adduser
build an image carries before assuming the tool is broken.
