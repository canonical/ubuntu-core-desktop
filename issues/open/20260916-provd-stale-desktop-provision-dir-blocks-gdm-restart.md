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
