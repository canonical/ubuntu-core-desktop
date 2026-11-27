# Stale desktop-provision dir blocks provd socket bind on GDM restart

Status: Root cause confirmed, reproducible every time. Workaround known
(manual rm -rf before each GDM restart). Not fixed at the source.

## Impact / Priority

Every restart of gdm.service breaks the first-boot wizard until
/run/gnome-initial-setup/desktop-provision is manually removed: the
wizard silently fails to start or hangs immediately. Hit on every
single GDM restart during wizard testing.

Impact derived from the original note's symptoms.

## Context

While repeatedly restarting gdm.service during ubuntu-desktop-init.snap
wizard testing on the desktop26 test VM this session (dozens of
iterations diagnosing locale/keyboard/network/user-creation/password
bugs - see the other 20260916/20260915 work items from the same testing
run), every single GDM restart needed this manual cleanup step first,
or the wizard would silently fail to start / hang immediately:

    rm -rf /run/gnome-initial-setup/desktop-provision
    systemctl restart gdm.service

This is DIFFERENT from the previously-documented bug in
`20260915-ubuntu-desktop-init-missing-run-gnome-initial-setup-dir.md`
(which was about /run/gnome-initial-setup itself needing to exist/be
mode 1777). This bug is about a subdirectory left behind *inside* that
directory by the previous wizard attempt.

## Diagnosis

Each time gdm.service (re)starts, it allocates a fresh dynamic system
user for the initial-setup session (gnome-initial-setup-N, with N
incrementing each time). provd, running as that dynamic user, creates
/run/gnome-initial-setup/desktop-provision (mode 0755) on first use, to
hold its gRPC socket (init.socket) and related files, owned by that
session's uid.

provd never cleans this directory up on exit/session teardown. The next
GDM restart allocates a *different* dynamic uid for the new
gnome-initial-setup-N session. The new provd instance tries to create/
bind its socket in the same /run/gnome-initial-setup/desktop-provision
path, but since it's mode 0755 and owned by the *previous* attempt's
uid, the new (different-uid) provd process gets "permission denied"
trying to bind there, and the wizard fails to come up at all (or hangs
immediately, depending on exactly which step in provd's startup it
gets stuck at).

This is a real, reproducible bug in provd's session cleanup/directory
handling - it should either:
  - clean up desktop-provision on session end/socket close, or
  - create the directory with a mode/ownership that tolerates a
    different uid on each run (e.g. mode 1777 like the parent, or
    recreate it fresh each time rather than reusing whatever's there),
    or
  - use a uid-namespaced subdirectory name so collisions can't happen.

Workaround used throughout this session (every single retest, dozens of
times):

    rm -rf /run/gnome-initial-setup/desktop-provision
    systemctl restart gdm.service

## Next steps

- File/track this against canonical/ubuntu-desktop-provision (provd) -
  likely in the same area of code as the daemon startup/socket-binding
  logic under /run/gnome-initial-setup.
- Consider whether the parent directory's earlier fix (mode 1777, per
  `20260915-ubuntu-desktop-init-missing-run-gnome-initial-setup-dir.md`)
  should be extended so provd itself is responsible for recreating
  desktop-provision cleanly on each startup, rather than assuming the
  directory it left behind can be reused by a differently-uid'd
  instance next time.

## Update (2026-11-27): path and pre-creation changed; ownership case open

The directory moved and provd is now pre-created, so parts of the
diagnosis above are out of date but the bug is not clearly gone:

- The socket directory is no longer `/run/gnome-initial-setup/
  desktop-provision`: it is `%h/desktop-provision` under the wizard
  session home (`/run/gdm3/home/gnome-initial-setup/desktop-provision`
  on this GDM), per the base's
  `snap.provd.provd.service.d/70-wizard-only.conf`.
- That same drop-in adds `ExecStartPre=/usr/bin/mkdir -p
  %h/desktop-provision` (core-base-desktop commit 2770945), which fixes
  the "bind fails with ENOENT because provd starts before anything
  creates the dir" class - not this file's failure.
- `mkdir -p` does NOT fix the reported failure: a dir left behind by the
  previous session's uid with mode 0755 still yields EACCES when the new
  uid binds in it, and `mkdir -p` silently succeeds on an existing dir.
- Open question to settle first: whether GDM wipes `/run/gdm3/home/...`
  between initial-setup sessions on this image. If it does, this bug is
  gone; if it does not, the stale-ownership failure should still
  reproduce on the next GDM restart and provd needs the ownership/mode
  fix listed above (1777 or a uid-namespaced path).

Do not re-derive the old journal; reproduce on the current image and
record which uid owns the dir before the failing restart.
