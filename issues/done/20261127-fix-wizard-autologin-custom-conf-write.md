# Wizard autologin fails after PR92: accountsservice profile lacks the write grants

Date: 2026-11-27

## Impact / Priority

HIGH. The first-boot wizard's "log in automatically" checkbox made
CreateUser fail with "failed to set autologin: Permission denied" and
roll back the account: the wizard hung forever on the account-creation
spinner. 100% reproducible on every fresh nouser image built from
desktop/26 tips. This is the gap the PR92 verification comment
(core-base-desktop#92, issuecomment-7103678800) already surfaced: the
mount is necessary but the accountsservice profile grants were missing.

## Root cause (from the VM journal)

PR92 bind-mounts /etc/gdm3 from writable system data, so
g_file_set_contents' temp+rename works. But the factory seed keeps
custom.conf as the /etc/writable symlink, and AppArmor mediates the
RESOLVED path, while the accountsservice interface policy granted only
"/etc/gdm3/custom.conf r":

    AVC DENIED open profile="snap.accountsservice.accounts-daemon"
      name="/etc/writable/gdm3/custom.conf" requested_mask="r"

(the daemon's config read through the symlink). With the read granted,
the write still failed until the temp-file create was granted too:

    AVC DENIED operation="mknod"
      profile="snap.accountsservice.accounts-daemon"
      name="/etc/gdm3/custom.conf.GXK4Y3" requested_mask="c"

## Fix (snapd fork, desktop/26)

ubuntu-core-desktop-snapd PR #46 grants the live-verified set from the
PR92 verification comment:

    /etc/writable/gdm3/custom.conf r,
    /etc/gdm3/ rw,
    /etc/gdm3/custom.conf rw,
    /etc/gdm3/custom.conf.* rw,

The rename replaces the symlink with a real file inside the PR92 bind,
so subsequent writes only need the /etc/gdm3 grants. No base change
needed: the factory template keeps the symlink as designed (a real-file
seed variant was tried first and withdrawn as unnecessary once the
profile grants exist).

## Verification

End to end on a nouser image built with the policy-fixed snapd and the
PRISTINE upstream base (symlink kept, no base change):
build/policy-test. Wizard completes with "Require my password to log
in" unchecked (autologin requested), account created, GDM autologs the
new user. snapd interface suite passes.
