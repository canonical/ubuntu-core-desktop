# KDE screen lock/unlock is broken for extrausers accounts (eg "testuser")

Date: 2026-10-13

## Impact / Priority

Any password-authenticated account that exists only in extrausers (not
/etc/passwd), such as one created through the plasma-setup first-boot
wizard, cannot unlock the screen: typing the correct password at the KDE
lock screen always results in "Unlocking failed", so the user has to log
out and back in to regain the session. Login, logout and locking
themselves work. No priority was stated in the original note. Impact
derived from the original note's described symptoms.

## SUMMARY / CURRENT STATE

Written 2026-10-13, handed off mid-investigation. Read this whole file
before touching anything -- a huge number of theories have already been
tried and ruled out below; don't repeat them.

Context: this is part of implementing a KDE equivalent of GNOME's no-ISO
first-boot account creation wizard ("plasma-setup") on Ubuntu Core
Desktop. See `20261013-kde-use-plasma-setup.md` for the original task
and the (mostly complete) wizard work.

Within that work, end-to-end verification was required: create an
account via the wizard, log in, log out, lock the screen, unlock the
screen. Login/logout/lock all now work. **Screen unlock does not work**
for a password-authenticated extrausers account (eg "testuser", created
via the plasma-setup wizard, who only exists in /var/lib/extrausers/*,
not /etc/passwd). Typing the correct password at the KDE lock screen
always results in "Unlocking failed".

This has turned into a deep, not-yet-solved bug in how PAM resolves the
user when invoked from inside a confined desktop-session snap. Three
separate *real* bugs were found and fixed along the way (details below)
but the final unlock failure persists even with all three fixes applied
and live-tested. The root cause of the *remaining* failure is still
unknown as of this handoff.

## WHAT WORKS

- plasma-setup wizard: full account creation flow (see
  `20261013-kde-use-plasma-setup.md` for its history).
- Login via SDDM with the new extrausers account + typed password: WORKS.
- Logout: WORKS.
- Locking the screen (Super+L): WORKS, shows the lock screen correctly.
- **Unlocking the screen with the correct password: FAILS** ("Unlocking
  failed" every time), for every account we've tried that only exists in
  extrausers (not /etc/passwd).

## HOW TO REPRODUCE / TEST ENVIRONMENT

A QEMU VM is (at last check) still running with this exact bug live and
reproducible, with hours of forensic state already set up in it. Unless
it has been shut down since, prefer continuing with it before trying a
fresh build -- see "VM access" below. If it's gone, see "NEXT STEPS" for
how to get back to this exact point.

- VM disk: ubuntu-core-desktop build/pc.img (or kde/build/pc.img;
  check `ps aux | grep qemu-system` for the actual `-drive file=...` in
  use).
- Launched with a serial console and a VNC display (see the
  qemu-system-x86_64 command line via `ps aux | grep qemu` for the
  exact invocation already running).
- Serial console access (gives a root shell): pipe commands into the
  serial socket, eg (substitute the socket path from the qemu command
  line):
    (echo 'some command'; printf '\r'; sleep 2) | timeout 10 socat - \
      UNIX-CONNECT:<serial-socket-path> | cat -v
  (a root shell is already logged in on the serial console; no login
  prompt needed)
- GUI access/automation: `vncdotool -s <vnc-display> <command>` (capture,
  type, key, etc). Useful commands used throughout this investigation:
    vncdotool -s <vnc-display> capture /tmp/screenshot.png  # then view it
    vncdotool -s <vnc-display> key super-l                  # lock screen
    vncdotool -s <vnc-display> type 'verifypass1'           # type password
    vncdotool -s <vnc-display> key enter                    # submit
- Test account: username "testuser", password "verifypass1" (extrausers
  only, created via the plasma-setup wizard flow during this
  investigation).
- No network inside the VM -- you cannot `scp`/`apt-get install` anything
  onto the VM directly. To get a file onto the VM, base64-encode it on
  the host and paste it through the serial console with a
  `cat > file << 'EOF' / base64 -d` heredoc (see transcripts below for
  the exact pattern used). strace, gcc, python3, busybox are NOT
  available inside the VM -- only coreutils, perl (no /usr/bin/perl! see
  below), and the base system.

**IMPORTANT CORRECTION mid-investigation**: much of the early diagnostic
work in this investigation used
`nsenter --mount=/proc/<kscreenlocker_worker_pid>/ns/mnt -- ...`
believing this fully entered the confined snap's view of the filesystem.
Late in the investigation it was discovered that **/usr/bin/perl does
NOT exist inside that real mount namespace** (it's part of the minimal
core rootfs, not bundled), yet earlier test steps used `perl`
successfully "inside that namespace" -- meaning some of those earlier
tests were NOT actually running inside the real confined mount
namespace (likely silently falling through to the host/outer root
namespace's binaries, or PID reuse meant the nsenter'd namespace had
changed). **Treat any test result obtained via nsenter+perl earlier in
this investigation as suspect/unverified.** Tests redone late in the
investigation using binaries confirmed present in the real namespace
(getent, id, a copied+chowned ELF) are more trustworthy. See "FULL
CHRONOLOGICAL LOG OF THEORIES TRIED" below for which is which.

## THE THREE REAL BUGS FOUND AND FIXED

(All believed correct, not all individually suficient -- see below.)

1. **kde-kauth / pam-unix-chkpwd snapd interface AppArmor gaps** (fixed,
   confirmed via total absence of "DENIED" AppArmor log lines during
   lock/unlock, across multiple retries):
   File: ubuntu-core-desktop-snapd interfaces/builtin/
         pam_unix_chkpwd.go (+ pam_unix_chkpwd_test.go)
   This is a brand new custom snapd interface (not upstream). It grants:
     - `/usr/sbin/unix_chkpwd Px,` (transition into the unix-chkpwd
       AppArmor profile)
     - `/usr/sbin/pam_extrausers_chkpwd Ux,` (fully unconfined -- this
       helper has no upstream AppArmor profile of its own and needs
       setgid-root-like trust, same tier as the kde-kauth helper)
     - `/run/faillock/ rw,` + `/run/faillock/** rwk,` (pam_faillock
       tally-file state dir, needed the first time anything calls PAM
       after boot from a confined caller)
     - `/usr/lib/core/lockout-not-enabled.sh ix,` +
       `/etc/writable/account-locked.enable r,` (a pam_exec check run on
       every auth attempt)
   This interface is wired up in:
     - ubuntu-core-desktop build.sh (added "kde-kauth",
       "pam-unix-chkpwd" to the `simple_plugs` list, uncommitted diff
       present now -- see "CURRENT UNCOMMITTED DIFFS" below)
     - plasma-desktop-session snap/snapcraft.yaml (added
       `pam-unix-chkpwd` to the kwin-wayland app's plugs + top-level
       plugs stanza, uncommitted diff present now)
   STATUS: confirmed via live AppArmor-profile patch + reload on the
   running VM (inserted the 4 new rules into the live
   /var/lib/snapd/apparmor/profiles/... profile text for
   snap.plasma-desktop-session.plasma-kwin-wayland, then
   `apparmor_parser -r`). After this, `journalctl -k | grep DENIED`
   returns NOTHING during lock/unlock attempts, across many retries.
   This part of the problem is solved. NOT YET baked into a real build
   (the live patch doesn't persist) -- the .go source change is correct
   and ready, snapd just needs rebuilding+the image rebuilt to pick it
   up for real.

2. **unix_chkpwd / pam_extrausers_chkpwd shipped setgid-root instead of
   setgid-shadow** (fixed in source, confirmed via live bind-mount test
   that it's necessary, but ALSO confirmed NOT sufficient alone):
   File: core-base-desktop hooks/010-fixup-permissions.chroot
   (diff already present, see below). Adds:
     chown root:shadow usr/sbin/unix_chkpwd usr/sbin/pam_extrausers_chkpwd
     chmod 2755 usr/sbin/unix_chkpwd usr/sbin/pam_extrausers_chkpwd
   Root cause: our build's staged rootfs ships these two helpers as
   `-rwxr-sr-x root root` (setgid root) instead of the Debian-standard
   `-rwxr-sr-x root shadow` (setgid shadow). Setgid-root confers no
   useful privilege for reading a root:shadow, mode-640 file
   (/etc/shadow or /var/lib/extrausers/shadow) -- the helper needs to be
   setgid *shadow* specifically to pass the kernel's group-permission
   check on that file.
   STATUS: Live-tested via nsenter-scoped bind mounts of rechowned
   copies of the two binaries over the originals, inside the real
   kscreenlocker_worker mount namespace. The group fix measurably took
   effect (verified via `ls -la` showing root:shadow through
   /proc/<pid>/root/usr/sbin/...) but **unlock still failed afterwards,
   with the exact same "check pass; user unknown" log lines as before**.
   So this fix is believed necessary (matches upstream Debian packaging
   expectations) but is NOT sufficient by itself to fix unlock. Not yet
   tested *in combination* with fix #3 below (couldn't -- #3 requires a
   read-only base-snap file that can't be live-patched; see "NEXT
   STEPS").

3. **unix-chkpwd AppArmor profile missing /var/lib/extrausers/passwd
   read access** (fixed in source, NOT live-tested due to a read-only
   filesystem, likely correct but unconfirmed):
   File: core-base-desktop static/etc/apparmor.d/unix-chkpwd (new
   file, full content shown in "CURRENT UNCOMMITTED DIFFS" below)
   This is a full copy of the upstream unix-chkpwd AppArmor profile
   (which already granted `/var/lib/extrausers/shadow r,`, presumably
   added by someone on this project previously, with a "TODO: we might
   want to move these into an abstraction for pam_extrausers.so"
   comment already in place) with `/var/lib/extrausers/passwd r,` and
   `/var/lib/extrausers/group r,` ADDED (these were missing).
   Reasoning: `unix_chkpwd` (NOT `pam_extrausers_chkpwd`, which is fully
   unconfined via its Ux rule -- see #1) transitions into this named
   AppArmor profile (`Px,` rule in fix #1), so IT specifically could be
   blocked from reading /var/lib/extrausers/passwd by AppArmor even if
   the file is otherwise readable, which would make its own internal
   getpwnam()-equivalent NSS resolution fail.
   STATUS: **NOT live-tested.** /etc/apparmor.d/unix-chkpwd on the
   running VM is on a read-only base-snap filesystem; `chown`/`sed -i`/
   `touch` all fail with "Read-only file system" when attempted
   directly on the live VM. This fix can only take effect via a real
   image rebuild (static/* is `cp -a`'d verbatim into the built rootfs
   by core-base-desktop's Makefile -- confirmed by reading the
   Makefile, not just assumed).
   IMPORTANT: this fix targets `unix_chkpwd` specifically. Recall that
   `unix_chkpwd` is NOT the module expected to actually succeed for an
   extrausers-only user (pam_unix.so/unix_chkpwd correctly fails with
   "user unknown" for such a user as harmless, expected behavterh --
   see "PAM AUTH STACK" below) -- `pam_extrausers.so`/
   `pam_extrausers_chkpwd` is the one that's SUPPOSED to succeed, and it
   runs fully unconfined (Ux) so this specific AppArmor fix does not
   directly touch it. This fix is still probably correct/worth keeping
   for `unix_chkpwd`'s own correctness, but won't by itself explain or
   fix why `pam_extrausers_chkpwd` fails.

## A SECOND, INDEPENDENT BUG FOUND VIA READING UPSTREAM SOURCE

(Not yet fixed, and not yet needed to be fixed to validate the main
bug, but WILL matter once the main bug is fixed.)

Confirmed via `journalctl -k`/`-S -1min` grep for "seccomp"/"audit"
during real unlock attempts:
    audit[PID]: SYSCALL ... subj=unconfined pid=NNNNN comm="pam_extrausers_"
      exe="/usr/sbin/pam_extrausers_chkpwd" ... syscall=41 ...
    pam_extrausers_chkpwd[NNNNN]: audit_open() failed: Operation not permitted
syscall 41 is `socket()`. This is `_audit_log()`'s call to libaudit's
`audit_open()` (which opens an AF_NETLINK socket), being blocked by the
**snap's own seccomp-bpf filter** (NOT AppArmor -- seccomp filters are
inherited across execve() unconditionally, unlike AppArmor profiles
which can "transition" via Ux/Px, so this persists even though
pam_extrausers_chkpwd's AppArmor subject is confirmed `unconfined`).

Read the actual upstream source for this (see "USEFUL REFERENCE:
UPSTREAM SOURCE" below) -- in modules/pam_extrausers/unix_chkpwd.c,
`_audit_log()`:
    audit_fd = audit_open();
    if (audit_fd < 0) {
        if (errno == EINVAL || errno == EPROTONOSUPPORT ||
            errno == EAFNOSUPPORT)
            return PAM_SUCCESS;   /* gracefully treated as "no audit support" */
        helper_log_err(LOG_CRIT, "audit_open() failed: %m");
        return PAM_AUTH_ERR;      /* <-- hit on EPERM from our seccomp filter */
    }
This function is called both on the auth FAILURE path (harmless, result
already failed anyway) AND on the SUCCESS path:
    } else {
        if (getuid() != 0) {
            return _audit_log(AUDIT_USER_AUTH, user, PAM_SUCCESS);
        ...
**This means: even once the primary "user unknown" bug is fixed, a
CORRECT password will still cause the overall helper to return
PAM_AUTH_ERR**, because `_audit_log()`'s failure on EPERM (not one of
the three gracefully-handled errno values) overrides the otherwise-
successful result. This needs a second interface fix: either allow the
`socket(AF_NETLINK, ...)` syscall needed for `audit_open()` through the
snap's seccomp policy (check how seccomp policies are declared for this
project's snaps/interfaces -- likely needs a snapd interface/seccomp
snippet addition, not just AppArmor), or find/set an environment or
compile option that disables libaudit calls from this helper, or patch
around it. NOT YET ATTEMPTED. Needs investigation into this project's
seccomp interface definition mechanism (likely also in
ubuntu-core-desktop-snapd/interfaces/builtin, possibly needs an addition
to pam_unix_chkpwd.go's `connectedPlugSecComp` equivalent, if snapd's
`commonInterface` struct supports that field -- check other interfaces
in that repo for the naming/pattern).

## THE UNRESOLVED MYSTERY (this is the actual blocker)

Despite fixes #1-#3 above, screen unlock with testuser/verifypass1
STILL fails, and the journal STILL shows:
    pam_extrausers_chkpwd[NNNNN]: check pass; user unknown
    pam_extrausers_chkpwd[NNNNN]: password check failed for user (testuser)
(and the analogous unix_chkpwd lines, which are expected/harmless as
explained above).

"check pass; user unknown" comes from `helper_verify_password()` in
modules/pam_extrausers/passverify.c, logged whenever `get_pwd_hash()`
can't resolve the passwd entry. Read the actual code (full copy fetched
via `apt-get source pam` on the HOST, not the VM -- see "USEFUL
REFERENCE" below) -- confirmed:
  - `get_account_info()` calls `pam_modutil_getpwnam(pamh, name)`, and
  - in HELPER_COMPILE mode (ie the standalone `unix_chkpwd` /
    `pam_extrausers_chkpwd` binaries, as opposed to the PAM .so itself),
    `pam_modutil_getpwnam(h,n)` is literally `#define`d to plain
    `getpwnam(n)` -- i.e. this really is just a normal glibc NSS lookup,
    no custom/bypassing logic, no hidden extrausers-specific parsing (a
    custom `_unix_getpwnam()` function DOES exist in this codebase that
    bypasses NSS and reads /var/lib/extrausers/passwd by hand via
    `fopen()`+`fgets()`, but it is used elsewhere in the PAM module, NOT
    by the HELPER_COMPILE binaries -- confirmed by reading the macro
    definitions, this was an early false lead, ruled out).
  - Before that, `user` itself is resolved (when the real caller uid
    isn't 0, which is our case: uid 1000) via
    `user = getuidname(getuid())`, and `getuidname()` is ALSO just a
    thin wrapper around plain `getpwuid(uid)`.

So the ONLY NSS calls involved are vanilla `getpwuid(1000)` and
`getpwnam("testuser")`, both going through the standard
`/etc/nsswitch.conf` -> `files extrausers` (currently: `passwd: files
systemd extrausers`, confirmed current content on the VM) -> loading
`libnss_extrausers.so.2` -> reading `/var/lib/extrausers/passwd`.

Every attempt to reproduce this exact lookup externally **succeeds**:
  - `getent passwd testuser` as uid 1000, inside the real
    kscreenlocker_worker mount namespace (confirmed via nsenter, a
    binary confirmed PRESENT in that namespace, not an earlier
    perl-based test) -- SUCCEEDS, finds testuser.
  - `getent passwd 1000` (uid-based reverse lookup, ie the
    `getpwuid()`-equivalent) -- SUCCEEDS, finds testuser.
  - Both of the above again with a **completely empty environment**
    (`env -i`), to match the real helper's `execve(CHKPWD_HELPER, args,
    envp)` call where `envp` is a hardcoded `{NULL}` (confirmed by
    reading the source -- this really is how upstream invokes it, not a
    bug in itself) -- STILL SUCCEEDS.
  - A copy of `/usr/bin/id` (confirmed present in the real namespace),
    rechowned to `root:shadow` + `chmod 2755` to force the kernel to set
    AT_SECURE for it (same mechanism that applies to the real
    unix_chkpwd/pam_extrausers_chkpwd binaries, which ARE genuinely
    setgid after fix #2), run as uid 1000 via the same nsenter+setpriv
    harness -- STILL correctly resolves the uid to "testuser" via its
    own internal getpwuid() call. This rules out AT_SECURE-triggered NSS
    module restrictions as the cause.
  - Confirmed via the real audit log (`subj=unconfined` on the
    `pam_extrausers_chkpwd` process during a REAL failing unlock
    attempt, not a synthetic reproduction) that AppArmor really is fully
    unconfined for it, consistent with fix #1's Ux rule. Not an AppArmor
    confinement issue.
  - Confirmed via the real audit log that only ONE seccomp denial
    occurs during a real attempt (syscall 41/socket, the audit_open()
    issue described above) -- no other blocked syscalls, so seccomp is
    not blocking some other part of the NSS resolution chain (eg no
    blocked `openat()` for /var/lib/extrausers/passwd, which would
    otherwise be a very plausible silent-NSS-module-failure
    explanation).
  - Confirmed the kscreenlocker_worker process is in the ROOT user
    namespace (uid_map "0 0 4294967295", same as the top-level VM root
    shell) -- not in some UID-remapped user namespace that could cause
    getuid()-based lookups to resolve differently than expected.
  - Confirmed `libnss-extrausers`'s actual source (fetched via
    `apt-get source libnss-extrausers` on the HOST) has **no**
    `getenv()` calls at all -- so the empty-environment execve() can't
    be breaking it via some missing env-var dependency either.

Despite every external reproduction succeeding, the REAL
`pam_extrausers_chkpwd` process, invoked for real via a real unlock
attempt through the real PAM stack inside the real kscreenlocker_worker
process, still logs "check pass; user unknown" -- meaning its internal
`getpwnam("testuser")` call is genuinely returning NULL in a context
nobody has yet been able to faithfully reproduce manually.

Working hypothesis for what to try next (NOT yet tried): the live VM at
this point has been patched/bind-mounted/poked at for many hours across
multiple segments of this investigation (nsswitch.conf overlays,
binary replacements, AppArmor profile edits, multiple kscreenlocker_worker
process generations). It is increasingly likely that **the live VM's
state is itself confounded/inconsistent** in some way that doesn't
affect the specific things that have been directly inspected, and that
continued forensics on this same long-lived VM has hit diminishing
returns. The most likely next productive step is a **clean rebuild +
fresh boot** with fixes #1-#3 applied, re-testing unlock from a known-
clean state, rather than continuing to live-patch this VM. See "NEXT
STEPS".

## PAM AUTH STACK (for reference)

/etc/pam.d/common-auth (current content on the VM, matches
core-base-desktop/static/etc/pam.d/common-auth presumably -- diff that
file against this if investigating further):
    auth [success=1 default=ignore] pam_exec.so quiet /usr/lib/core/lockout-not-enabled.sh
    auth requisite pam_faillock.so preauth
    auth [success=4 authinfo_unavail=ignore default=bad] pam_extrausers.so nodelay nullok try_first_pass debug
    auth [success=3 default=ignore] pam_unix.so nullok try_first_pass
    auth [success=1 default=ignore] pam_exec.so quiet /usr/lib/core/lockout-not-enabled.sh
    auth [default=ignore] pam_faillock.so authfail
    auth requisite pam_deny.so
    auth required pam_permit.so
    auth [success=1 default=ignore] pam_exec.so quiet /usr/lib/core/lockout-not-enabled.sh
    auth sufficient pam_faillock.so authsucc
Because testuser only exists via extrausers (not /etc/passwd),
`pam_extrausers.so`/`pam_extrausers_chkpwd` is THE module that is
supposed to actually authenticate it; `pam_unix.so`/`unix_chkpwd`
failing with "user unknown" for this same user is EXPECTED/harmless
(it's not supposed to find this user at all, since it's an
extrausers-only account) -- don't mistake unix_chkpwd's failure logs
for the bug; focus entirely on why pam_extrausers_chkpwd fails.
Current /etc/nsswitch.conf relevant lines (confirmed live on VM):
    passwd:         files systemd extrausers
    group:          files [SUCCESS=merge] extrausers systemd
    shadow:         files systemd extrausers
(Already tried and ruled out: temporarily removing "systemd" from the
passwd/shadow lines, to rule out nss_systemd/blocked-socket interference
with the lookup chain -- unlock still failed identically with "systemd"
removed, so this isn't the nss_systemd module interfering.)

unix_chkpwd/pam_extrausers_chkpwd both **refuse direct manual
invocation** regardless of caller uid (tested as both root and 1000):
    This binary is not designed for running in this way
    -- the system administrator has been informed
(then sleeps 10s and exits). This is a deliberate guard in the real
source (`isatty(STDIN_FILENO) || argc != 3` check in unix_chkpwd.c's
main()) -- there is no way to manually invoke the real helper with a
controlled argv/stdin; it must be exercised via a real PAM auth attempt
(ie really locking/unlocking the screen), there is no shortcut. Attempts
to work around this by bind-mounting Perl-script "wrapper" replacements
of the binary (to log argv/stdin and call the real getpwnam internally)
were made and **never invoked at all** by the PAM stack (no wrapper log
output, no journal trace of the wrapper running) -- `pam_extrausers.so`
appears to do some kind of pre-exec sanity check on the target binary
that silently skips non-ELF (script) substitutes, even with the
executable bit and setgid bit both correctly set. The exact nature of
this check was never identified (not investigated further - low
priority, since it blocks a workaround, not an understanding, of the
actual bug).

## CURRENT UNCOMMITTED DIFFS (as of this handoff)

(NOTHING has been committed yet across any of these four repos; do that
as part of finishing this work, with real commit messages, once
verified.)

### core-base-desktop

Modified: hooks/010-fixup-permissions.chroot (appends this block):
    # Fixup ownership of the unix_chkpwd/pam_extrausers_chkpwd privilege
    # separation helpers. Upstream, these ship setgid "shadow" (mode 2755)
    # so pam_unix/pam_extrausers can exec them to verify a password without
    # the *caller* needing read access to /etc/shadow or
    # /var/lib/extrausers/shadow (both root:shadow, mode 640) itself -- the
    # helper's own setgid-shadow privilege covers that. Our staging process
    # leaves them setgid "root" instead, which grants no extra access to a
    # group-"shadow" file, so getspnam() silently fails for any caller that
    # isn't already root. This is invisible from login (SDDM/GDM run as
    # root and never need the helper's privilege), but breaks any PAM check
    # made by a confined, unprivileged process -- e.g. kscreenlocker_worker
    # verifying the password during screen unlock.
    chown root:shadow usr/sbin/unix_chkpwd usr/sbin/pam_extrausers_chkpwd
    chmod 2755 usr/sbin/unix_chkpwd usr/sbin/pam_extrausers_chkpwd

New file: static/etc/apparmor.d/unix-chkpwd (full content):
    # Override of the upstream unix-chkpwd profile: the stock profile already
    # anticipated pam_extrausers.so needing /var/lib/extrausers/shadow (see the
    # upstream TODO comment below) but never added read access to
    # /var/lib/extrausers/passwd. Without it, unix_chkpwd/pam_extrausers_chkpwd
    # can't resolve the username via NSS (libnss_extrausers), so every password
    # check fails with "user unknown" -- harmless from an unconfined caller
    # (e.g. SDDM/GDM greeters running as root, which read /etc/shadow directly
    # and never need to exec this helper), but fatal for PAM checks made from
    # confined, unprivileged processes such as kscreenlocker_worker during
    # screen unlock.
    profile unix-chkpwd /{,usr/}{,s}bin/unix_chkpwd flags=(attach_disconnected.path=/att/unix-chkpwd/) {
      include <abstractions/base>
      include <abstractions/nameservice>

      # Temporarily needed until fd delegation lands
      # Also needed while delegation from unconfined is broken
      include <abstractions/consoles>

      # To write records to the kernel auditing log.
      capability audit_write,
      # To read shadow with 000 permissions.
      capability dac_read_search,

      network netlink raw,

      @{exec_path} mr,

      /etc/shadow r,

      # systemd userdb, used in nspawn
      /run/host/userdb/*.user r,
      /run/host/userdb/*.user-privileged r,

      # TODO: we might want to move these into an abstraction
      # for pam_extrausers.so
      /var/lib/extrausers/passwd r,
      /var/lib/extrausers/group r,
      /var/lib/extrausers/shadow r,

      # file_inherit
      owner /dev/pts/[0-9]* rw,
      owner /dev/tty[0-9]* rw,

      # disconnected paths - their non-disconnected counterpart is allowed via abstractions
      /att/unix-chkpwd/run/authd.sock rw,
      /att/unix-chkpwd/run/systemd/journal/dev-log w,
      /att/unix-chkpwd/run/systemd/userdb/io.systemd.DynamicUser rw,
      /att/unix-chkpwd/run/systemd/userdb/org.gnome.DisplayManager rw,

      include if exists <local/unix-chkpwd>
    }
(NB: static/* is `cp -a`'d verbatim into the built rootfs by this repo's
Makefile -- confirmed by reading it, not assumed -- so this file will
really take effect on rebuild.)

### ubuntu-core-desktop-snapd

New files (untracked, ready to `git add`):
  interfaces/builtin/pam_unix_chkpwd.go
  interfaces/builtin/pam_unix_chkpwd_test.go
(Full content of both captured above in "THE THREE REAL BUGS" section
#1.) Other untracked cruft in this repo from various build attempts
(`.nobackup`, `.wip-broken-devicemgmt/`, `cache-loc=.aa-cache`, stray
.deb/.buildinfo/.changes files, `list.txt`, `progress.txt`, `task.txt`,
`release-tools/test/test_create_release_tickets.py`) -- these look like
leftover build artifacts/scratch files from the snapd rebuild done in a
prior segment to produce a patched snapd.snap for live AppArmor-profile
validation. Review and clean these up (`git clean -n` first) before
committing; almost certainly none of them belong in a commit except the
two pam_unix_chkpwd.go files.

### ubuntu-core-desktop

Modified: build.sh (two separate diffs):
  1. Added "kde-kauth", "pam-unix-chkpwd" to the `simple_plugs` list
     (around line 276-278) -- wires both new snapd interfaces into every
     relevant snap's plug list.
  2. A pre-existing but partially-revised chunk of the extrausers
     account-creation code path (around line 719-734 in current state):
     fixes the comment that used to incorrectly describe chpasswd as
     already extrausers-aware (it's not -- only usermod/passwd really
     are, via ucd-ppa patch 1010, not chpasswd's separate/weaker 1017
     patch which only falls back to extrausers if /etc/passwd can't be
     *locked*, not if the user isn't *found* there), and adds a
     chpasswd-replacement shim (mirroring the existing useradd shim
     pattern already in this file) that reimplements chpasswd's job on
     top of `usermod -p` (which IS correctly extrausers-aware) instead
     of the real chpasswd binary. This fixes a DIFFERENT bug from the
     screen-unlock issue (this one was about newly created accounts
     having an unusable/locked password at all) -- this fix is believed
     complete and already validated as part of getting login to work at
     all earlier in this investigation (see git history / earlier
     checkpoints for that confirmation). Not directly related to the
     unlock bug, just hasn't been committed yet either.
Untracked cruft also present (`.qemu-core-desktop-kde26.lock`,
`AGENTS.md`, `build.ci/`, `fuse-poc/`, several `gdm-shell-*-test.conf`
files, `kde/`, `seed.manifest`, `strace_6.19+ds-0ubuntu5_amd64.deb`) --
review before committing, likely mostly build scratch/output plus the
strace .deb downloaded this segment (see "NEXT STEPS" item 2a,
ultimately not used -- can be deleted).

### plasma-desktop-session

Modified: snap/snapcraft.yaml:
  - Added `pam-unix-chkpwd` to the kwin-wayland (kscreenlocker) app's
    plugs list, with a comment explaining why.
  - Added `pam-unix-chkpwd: null` to the top-level `plugs:` stanza.
(it's a small, self-contained 9-line addition.)

## USEFUL REFERENCE: UPSTREAM SOURCE (fetch again if needed)

(Not part of any repo here; fetched fresh via apt on the HOST machine,
not the VM.)
    mkdir -p /tmp/pamsrc && cd /tmp/pamsrc && apt-get source pam
    # look at: pam-1.7.0/debian/patches/extrausers.patch
    # this is the Ubuntu-maintained patch that adds the entire
    # pam_extrausers module (modules/pam_extrausers/*.c), including
    # unix_chkpwd.c (the actual helper binary's main()), passverify.c
    # (get_account_info/get_pwd_hash/helper_verify_password), and
    # support.c (_unix_run_helper_binary, the PARENT side that forks+
    # execs the helper with an empty environment).
For libnss-extrausers:
    mkdir -p /tmp/nsssrc && cd /tmp/nsssrc && apt-get source libnss-extrausers
    # confirmed: no getenv() calls anywhere in this module.
(Both of these commands were run on the HOST machine, which has a
working apt/network setup, NOT the VM, which has none. If working from
the VM only, you'll need to fetch these on a machine with network
access and transfer the relevant files in via the serial-console
base64 trick described above.)

## NEXT STEPS

1. Decide whether to keep debugging the live VM or do a clean rebuild.
   Recommendation: **do a clean rebuild** at this point (see
   ubuntu-core-desktop's build.sh and the kde/ build scripts for the
   new binary-based KDE build system) incorporating fixes #1-#3 above,
   boot it fresh, recreate the testuser account via the real
   plasma-setup wizard flow (not shortcuts), and re-test lock/unlock
   from a known-clean state. This also indirectly re-validates a few
   other things (stale-autologin behaviour, the real wizard flow
   end-to-end) that were only ever checked on this same long-lived,
   heavily-patched VM.
2. If unlock STILL fails after a clean rebuild with fixes #1-#3: the
   mystery is real and environmental, not VM-state confusion. Next best
   diagnostic avenues, roughly in order of promise:
   a. Get `strace` onto the fresh VM to directly observe the real
      helper's syscalls during a real unlock attempt. A `strace` .deb
      (strace_6.19+ds-0ubuntu5_amd64) was downloaded into the
      ubuntu-core-desktop tree this segment (via `apt-get download
      strace` on the host) but was never actually gotten onto the VM or
      tested -- it's dynamically linked against
      libtinfo/libunwind/liblzma which may or may not already be
      present on the target rootfs; check with `ldd` against a copy of
      the target rootfs, or look into a statically-linked strace build,
      before spending time on the transfer-via-base64-serial dance.
      Being able to `strace -f -p <kscreenlocker_worker_pid>` (ptrace
      follows forks) across a real unlock attempt would likely settle
      this immediately.
   b. Try to directly compare the COMPLETE set of credentials/resource
      limits of the real exec'd child (captured via a tight polling
      loop reading /proc/<pid>/status, /proc/<pid>/limits,
      /proc/<pid>/environ while actually triggering an unlock via
      vncdotool in parallel) against the manual nsenter+setpriv
      reproduction. A first attempt at this polling approach this
      segment failed to catch the (very short-lived, <50ms) process in
      time with a naive shell for-loop; a faster polling mechanism
      (eg a tighter loop, or using inotify on /proc, or using `pidof`/
      `ps --ppid` filtered more precisely to catch it mid-exec) is
      needed if this route is pursued. The one piece of info this would
      add beyond what's already captured via audit-log `subj=`/`uid=`/
      `gid=`/`ses=` fields (which ARE already confirmed identical to the
      manual repro) would be: full environ (already structurally known
      to be empty per source reading, but worth independently
      confirming on the real process), and resource limits (RLIMIT_*),
      which have NOT been compared at all yet.
   c. Re-read `_unix_run_helper_binary()` in support.c (already partly
      quoted above) end to end once more, very carefully, for anything
      else it does between fork() and execve() that hasn't been
      accounted for yet -- eg the exact fd-closing loop, signal handler
      resets, or SELinux-conditional code paths that might behave
      differently when `WITH_SELINUX` is compiled in vs not (check
      whether this project's actual compiled pam package has
      `WITH_SELINUX` defined -- if so, some of the `is_selinux_enabled()`
      conditional codepaths in get_account_info()/lckpwdf.-c might be
      doing something relevant that wasn't considered, since this
      investigation assumed SELinux is irrelevant on an AppArmor-based
      system but never actually checked whether the binary was built
      with SELinux support compiled in and what it does if so).
   d. Consider whether the password-reading side (not the user-
      resolution side) could somehow be the actual proximate cause and
      the "user unknown" message is a RED HERRING in some way not yet
      understood -- eg re-verify, with fresh eyes, that the "check
      pass; user unknown" log line really can ONLY come from pwd==NULL
      in get_pwd_hash() and not from some other code path that happens
      to share that exact log string (the grep done this segment found
      it in exactly 2 places in the whole patch, both guarded by a
      pwd/salt NULL check, so this is believed solid, but worth a
      second pair of eyes before spending more time elsewhere).
3. Once the actual root cause of the "user unknown" mystery is found
   and fixed, ALSO apply the seccomp/audit_open fix described above
   (needed for the SUCCESS path to work at all), before considering
   this done.
4. Full rebuild with ALL fixes (the 3 done + whatever resolves the
   mystery + the seccomp/audit fix), fresh boot, full re-verification:
   create account via wizard -> login -> logout -> lock -> **unlock**.
5. Commit all pending changes across the four repos listed above (none
   are committed yet), with clear commit messages given how much
   investigation went into each one -- consider linking back to this
   file from the commit messages for posterity.
6. Update `20261013-kde-use-plasma-setup.md` with the final resolution
   once genuinely verified end-to-end.
7. Clean up stray debug artifacts: /root/chkpwd-fix/ on the VM (wrapper
   scripts, rechowned binary copies, poller scripts, log files -- none
   of this persists through a rebuild anyway, but worth remembering it's
   there if continuing on the SAME VM rather than rebuilding), and the
   various untracked scratch files listed under "CURRENT UNCOMMITTED
   DIFFS" above in ubuntu-core-desktop and ubuntu-core-desktop-snapd.
   Kill the QEMU VM when truly finished with it.

## A NOTE ON WHY THIS TOOK SO LONG

(For whoever picks this up, and for calibrating expectations.)

This looked like it should be a simple "fix one AppArmor rule" job
based on the first symptom found. It turned into three real,
independent, confirmed packaging/interface bugs (AppArmor gaps,
wrong setgid group, missing AppArmor file-read rule) stacked on top of
a fourth, still-unresolved mystery, plus a fifth latent bug (seccomp
blocking audit_open) discovered along the way that hasn't even
mattered yet because the fourth issue is still blocking before it. Each
theory required careful, slow, live-namespace forensic work (because
the helper binaries refuse direct invocation and because the VM has no
strace/gcc/network) to either confirm or rule out, and "rule out" was
genuinely the outcome for most of them. Please take the "already ruled
out" list above seriously and don't re-spend time on it -- but equally,
don't assume the 3 fixes made are wrong just because unlock still
fails; they are independently justified and almost certainly still
needed, just not sufficient alone.

## RESOLUTION (2026-10-13/14)

FIXED and verified end-to-end. The final mystery was NOT VM-state
confusion -- a clean rebuild reproduced it exactly. The root cause:

**The plasma-desktop-session snap declared `base: core26`, not
`base: core26-desktop`.** Confined snap apps run against their BASE
snap's rootfs: kscreenlocker_worker's PAM stack therefore exec'd the
chkpwd helpers from plain core26's /usr, which still ships them
setgid ROOT (the pre-fix-#2 state). core26-desktop -- where fixes #2
and #3 landed -- was only used as the SYSTEM rootfs, never as the
session apps' base. Proven by catching the short-lived helper with a
static /proc poller during a real failing unlock: the real helper ran
with `Gid: 1000 0 0 0` (egid=0 = setgid root applied, useless), so
getspnam() hit EACCES on the root:shadow extrausers shadow file.

Two further red herrings died here:
- "check pass; user unknown" is logged for ANY get_pwd_hash() failure
  -- including PAM_AUTHINFO_UNAVAIL from the unreadable shadow entry
  (next-steps item 2d was right; getpwnam() itself always succeeded).
- The seccomp/audit_open issue WAS real and blocked the success path,
  but had nothing to do with the "user unknown" failure.

FIXES (all verified on a clean rebuild):
1. snapd pam-unix-chkpwd interface: added connectedPlugSecComp
   `socket AF_NETLINK - NETLINK_AUDIT` (upstream handles the non-root
   send-EPERM case itself; only socket creation needed allowing).
   Commit: ubuntu-core-desktop-snapd 47162a2e69 (branch dev).
2. plasma-desktop-session: base switched to core26-desktop (built
   against a core26 placeholder + post-pack meta/snap.yaml patch, since
   snapcraft rejects unknown base names; local snapcraft pack + CI
   build-github.sh). This made the setgid-shadow helpers and the
   unix-chkpwd profile fixes actually visible to the confined session.
   Commit: fe296ef.
3. plasma-desktop-session: dropped the /usr/share/X11/xkb,
   /usr/share/glvnd/egl_vendor.d, /usr/lib/*/gbm and /usr/lib/*/dri
   layout symlinks -- core26-desktop ships real content there and a
   layout cannot replace existing base content ("existing symbolic
   link in the way" from snap-update-ns aborted every session app).
   Commit: fe296ef.
4. plasma-desktop-session: base /usr,/lib paths moved LAST in
   LD_LIBRARY_PATH -- core26-desktop ships libwayland-server 0.24
   while libkwin needs 0.26 (kf6 content snap); base-first ordering
   crashed kwin_wayland on wl_global_set_withdrawn_listener and
   dropped every autologin to the greeter. Commit: fe296ef.
5. core-base-desktop static/etc/apparmor.d/unix-chkpwd: added the
   standard header (abi/5.0, include <tunables/global>, @{exec_path}
   definition). Without it the profile failed to parse at boot
   ("Failed to find declaration for: @{PROC}"), apparmor.service
   failed as a unit, and the profile was never loaded -- so
   unix_chkpwd's Px exec was denied with "profile transition not
   found" even after fix #3 shipped the file. Commit: 90ed36a.

VERIFICATION: fresh pc.img from the image build, booted with the simple
reproducer (autologin your_username/x via cloud-init -- NO wizard).
Three consecutive Super+L lock -> type password -> unlock cycles all
succeeded; the real helper observed running egid=42 (shadow); journal
shows zero chkpwd errors during unlock (silent success path; no
audit_open EPERM). apparmor.service now active with unix-chkpwd
loaded. SDDM autologin/login and the desktop itself unaffected.

NOT DONE / FOLLOW-UPS:
- The plasma-setup wizard flow (no-user image -> create account ->
  login -> logout -> lock -> unlock) is still to be re-verified with
  these fixes; tracked in `20261013-kde-use-plasma-setup.md` (per
  instruction, simplest reproducer first).
- Quirk observed (pre-existing, unrelated): after
  `loginctl terminate-session` of the autologin session, sddm does not
  respawn the greeter until `systemctl restart sddm`. Not investigated.
- Diagnostics technique that cracked it: a small static /proc-polling
  C program to catch the <100ms chkpwd helper and dump its
  /proc/PID/status (uid/gid/NPP/seccomp) mid-flight -- the reusable
  method and gotchas (strace suppresses setgid via ptrace and its
  close() loop slows the helper 1000x; comm is truncated to 15 chars;
  some coreutils reject unknown argv[0] names; /tmp is nosuid so
  setgid tests there are invalid).
