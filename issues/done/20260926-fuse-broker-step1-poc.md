# FUSE-mount broker POC (Step 1 of the fusermount-broker plan) -- verified

## Impact / Priority

No user-facing impact of its own — this was the Step 1
proof-of-concept validating the privileged-broker + SCM_RIGHTS
fd-handoff design that the FUSE-mount broker work builds on (the fix
that lets the confined xdg-document-portal mount its document
directory). Impact derived from the original note's symptoms.

## Context

The privileged-broker + SCM_RIGHTS FD-handoff design for letting the
confined xdg-document-portal mount FUSE was proven end-to-end on the
core26-desktop test VM. Throwaway POC code (broker/ + client/, plain
Go, no deps) was written as a scratch prototype.

## What was proven (all on a live VM, real snap confinement)

- A root broker in the HOST mount namespace can open /dev/fuse and
  mount(2) a FUSE fs at /run/user/1000/<path> with
  fd=N,rootmode=40000,user_id=1000,group_id=1000. No nosuid/EPERM.
- It can hand the live FUSE fd to a client over a UNIX socket via
  SCM_RIGHTS, and read SO_PEERCRED (pid/uid/gid) off the same socket.
- A client running under FULL snap confinement
  (profile snap.ubuntu-desktop-session.xdg-document-portal, enforce)
  receives the fd and can use it (fcntl F_GETFL succeeds; FUSE_INIT
  round-trips). The confined process never calls mount() itself.
- MOUNT-NAMESPACE PROPAGATION WORKS: the broker's host-namespace mount
  at /run/user/1000/fuse-poc-test is automatically visible inside the
  confined snap's private mount namespace at the same path (mountinfo
  shows master:711). No nsenter/bind-mount gymnastics needed. This was
  the single biggest architectural risk and it checks out.
- A third, fully separate unconfined process sees the mount as a live
  FUSE fs (stat/ls return ENOSYS from the stub, i.e. the kernel is
  talking to our userspace server).

## Key finding for Steps 2/4: an AppArmor connect rule IS required

A plain path-based UNIX socket connect to /run/<sock> is NOT permitted
by the snap's baseline confinement. In enforce mode the confined client
got:

    apparmor="DENIED" operation="connect" class="file"
    profile="snap.ubuntu-desktop-session.xdg-document-portal"
    name="/run/fuse-poc-broker.sock" requested_mask="wr"

Setting the profile to complain mode (apparmor_parser -r -C) made the
connect succeed (logged as ALLOWED), confirming AppArmor is the only
blocker. So Step 4 must add the smallest possible rule/interface in
ubuntu-core-desktop-snapd scoped to just the broker socket path — do
NOT reintroduce capability sys_admin or /dev/fuse rw.

## Gotchas hit while building the POC (worth knowing for Steps 2/3)

- The kernel rejects the FUSE_INIT reply with EINVAL if the read buffer
  is smaller than max_write+4096. Advertise max_write=128K only if you
  read with a >=132K buffer (POC uses 1 MiB). Symptom: FUSE_INIT reply
  "succeeds" but the next read() returns EINVAL and the mount goes
  stale ("Transport endpoint not connected").
- A stale mount from a crashed client must be lazily unmounted
  (umount -l / MNT_DETACH) before re-mounting, else the new mount
  silently inherits the dead connection. Confirms the plan's
  pre-emptive MNT_DETACH requirement in Step 2.
- `snap run --shell <snap>.<app> -c "..."` is a convenient way to run a
  test binary under the exact app's confinement label without racing
  the real (crash-looping) service. The home directory and /run are
  visible inside; /run/user/1000 itself is not listable (Permission
  denied) but the specific mount path under it is reachable.

Step 1 verification: PASSED. Ready for Step 2 (production broker).
