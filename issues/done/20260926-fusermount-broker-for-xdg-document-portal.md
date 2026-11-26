# FUSE-mount broker + fusermount3 shim for confined xdg-document-portal

## Impact / Priority

Medium-High. This is the real fix for the ~25-27s
autologin black-screen delay documented in
`20260925-autologin-portal-login-delay.md`. That delay is caused by
xdg-document-portal being unable to create its FUSE mount at
/run/user/<uid>/snap.<name>/doc/ because the confined snap process has
no real Linux capabilities and Ubuntu Core's rootfs makes fusermount3's
SUID bit useless. A prior attempt (snapd `fuse-support` interface +
AppArmor mount-rule patch) was implemented, built into a full image, and
verified on a genuinely clean boot to NOT work: the AppArmor
"capability sys_admin" rule does not grant a real capability bit
(confirmed via direct /proc/<pid>/status inspection showing
CapEff/CapPrm == 0), so the mount still fails with "Permission denied",
and the resulting rapid crash-loop reproduces the same ~25s delay via
dbus-daemon's own service_start_timeout=25000ms instead of via the
portal's internal hang. See the full back-and-forth discussion that led
to this plan.

## Background

Why fuse-support doesn't work (confirmed empirically this session):
- fuse-support's AppArmor policy DOES correctly grant real access to
  /dev/fuse (a udev device-cgroup tag `KERNEL=="fuse"` plus an AppArmor
  `/dev/fuse rw,` path rule) -- opening the device node works fine.
- But actually attaching a FUSE filesystem to the VFS mount tree
  requires calling mount(2) (or the newer fsopen()/fsmount() pair), and
  that syscall is gated by the kernel on the *real* CAP_SYS_ADMIN
  capability bit in the calling process's credentials -- not by
  AppArmor.
- AppArmor's `capability sys_admin` rule is a MAC (mandatory access
  control) rule: it only permits the LSM hook to pass IF the process
  already holds the capability via a normal Unix mechanism (real root,
  setuid exec, file capabilities, or inherited ambient capabilities).
  It cannot manufacture the capability out of nothing.
- snap-confine itself has real file capabilities (via getcap, because
  its containing bind mount /snap/snapd/x3 -> /usr/lib/snapd is
  `ro,nodev` but NOT `nosuid`), which is how it can build the sandbox
  at all -- but it does not pass CAP_SYS_ADMIN through into the final,
  unprivileged application process. That process ends up with a
  genuinely empty capability set (verified: CapEff:0000000000000000,
  CapPrm: same).
- fusermount3's SUID bit is defeated by the same problem in reverse:
  the rootfs where /usr/bin/fusermount3 lives doesn't reliably give it
  real privilege either in this confined execution context, so the
  fallback also fails with "Permission denied".

Prior art / why this is a known-hard, still-unsolved upstream problem:
flatpak/xdg-desktop-portal issue #695 ("Portal for FUSE support"),
opened 2022-01-21, still open with zero comments as of this writing
(https://github.com/flatpak/xdg-desktop-portal/issues/695). It
describes exactly our problem in the Flatpak sandboxing context:
fusermount requires a SUID binary that isn't available inside the
sandbox, and Flatpak's current workaround is a `flatpak-spawn --host`
wrapper that punches a full sandbox-escape hole -- explicitly called
out in the issue as "not acceptable for most apps". The issue proposes
exactly the FD-passing broker/portal pattern below, but nobody has
implemented it upstream in 4+ years. Flatpak itself has NO root-level
daemon that solves this on a standard desktop; it depends on the host
having either a working SUID fusermount or unprivileged
user-namespace FUSE mounts (Linux 4.18+, which the *host* kernel
supports without a snap/Flatpak-style confinement wrapper around it).
Ubuntu Core's snap confinement removes both of those options, so we
cannot depend on the same fallback Flatpak silently relies on -- we
have to build the broker/portal ourselves.

The chosen design (privileged broker + fusermount3-replacing shim),
proposed in the design discussion, based on the SAME mechanism
fusermount3 itself already uses internally: a privileged process opens
/dev/fuse, performs the mount(2) syscall itself (as real root, so it
holds CAP_SYS_ADMIN natively), and hands the resulting live FUSE
communication fd to the unprivileged requester over a UNIX domain
socket using SCM_RIGHTS. The unprivileged process never needs to call
mount() itself; it just reads/writes the fd it was given, which
requires no special capability. This exact pattern is how every FUSE
mount on every Linux desktop already works today (fusermount3.c does
this internally, just combined with a setuid re-exec instead of a
separate broker process), and is also how rootless containers (runc,
fuse-overlayfs) and Flatpak's own document portal proposal (#695) are
designed. It is NOT a novel/unproven mechanism.

Two open design risks were identified and already checked this session
(cheaply, without a full implementation) -- see "Findings from this
session's spike" below. Both came back favorable, so the design is now
considered lower-risk than initially assumed.

## Findings from this session's spike (already done, do not repeat)

1. Mount namespace visibility across the confinement boundary:
   Confirmed via `snap run --shell
   ubuntu-desktop-session.xdg-document-portal` that the confined
   process's mount namespace for /run/user/1000 has propagation type
   `private,slave` (verified with
   `findmnt -no PROPAGATION /run/user/1000` run *inside* the confined
   shell), while the HOST's /run/user/1000 is `shared`. A "slave" mount
   automatically receives mount/unmount propagation events from its
   "shared" master peer group. This means: if the root-level broker
   performs its mount(2) call in the HOST's (default/init) mount
   namespace at /run/user/<uid>/snap.<name>/doc/, that mount WILL
   automatically become visible inside the confined snap's private
   mount namespace at the same path, with no extra nsenter/bind-mount
   gymnastics required. This was the single biggest architectural risk
   in the design and it checks out.
   NOTE: this was checked via propagation-flag inspection, not a fully
   live FD-handoff functional test -- Step 1 below still needs to prove
   it works end-to-end with a real mount + real FD handoff, not just
   confirm the propagation flags are favorable.

2. The generic SCM_RIGHTS FD-passing mechanism itself needs no
   independent proof -- it's exactly what fusermount3 already does on
   every Linux system, and is thoroughly production-proven elsewhere
   (runc, Flatpak's xdg-dbus-proxy, etc). No time should be spent
   "proving FD-passing works" in the abstract; the real open question
   was #1 above.

3. NOT yet checked (must be addressed in Step 1's design, called out
   explicitly here because the reference implementation omits it): the
   broker MUST authenticate the identity of the connecting client
   using SO_PEERCRED (uid/gid/pid of the actual peer process on the
   UNIX socket), not just trust whatever mount-path string the client
   claims to want. Without this check, any unprivileged local process
   could ask the broker to mount a FUSE filesystem into another user's
   /run/user/<uid>/ directory, or otherwise abuse the broker as a
   confused deputy. This is a hard requirement for Step 2, not an
   optional hardening step -- it directly addresses the security
   concern that made us reject the earlier PAM/ambient-capabilities
   approach in the first place.

## Repos involved

- ubuntu-desktop-session-snap (the confined snap; snapcraft.yaml, the
  fusermount3 shim's source + build, wiring PATH/command-chain)
- core-base-desktop (best candidate location for the root-level broker
  daemon + its systemd .socket/.service units, since it's already how
  we ship/patch base-image system units, e.g. the Makefile rm -f lines
  from the previous fix)
- ubuntu-core-desktop-snapd (only needed if a new custom AppArmor
  interface is required for the confined snap to connect() to the
  broker's UNIX socket; try to avoid a new interface if an existing
  one already covers a plain path-based UNIX socket connect)
- ubuntu-core-desktop (image build/test pipeline, the image build
  scripts)

## Plan

Each step below is independently buildable/testable. Do not start a
step until the previous one's verification has passed. Steps are sized
to be taken one at a time; each carries a rough note of the judgement
it needs (multi-step systems reasoning / kernel or security judgement
/ cross-repo integration, versus mostly mechanical, well-specified
work).

### Step 1: Standalone POC: FD handoff + mount propagation end-to-end

Note: this step needs careful mount-namespace/AppArmor debugging and
correct interpretation of kernel behaviour; mistakes here are easy to
misdiagnose as later-stage bugs.

What to build:

- broker.go: minimal root-owned Go program. Opens /dev/fuse, performs
  `syscall.Mount(...)` with fd=N,rootmode=40000,user_id=<uid>,
  group_id=<gid> at a SCRATCH test path (not the real doc/ path yet --
  e.g. /run/user/1000/fuse-poc-test/), listens on a UNIX socket, and
  on each connection: reads SO_PEERCRED off the socket and logs it (to
  prove the credential-check mechanism itself works -- doesn't have
  to enforce anything yet), then sends the fd via SCM_RIGHTS.
- client.go: minimal Go program that connects to the broker's socket,
  receives the fd via SCM_RIGHTS, and then does a raw read() on it (a
  genuine FUSE_INIT request should arrive from the kernel once the
  mount is live) and writes back a minimal valid FUSE_INIT reply so
  the mount finishes initializing, OR simpler: just prove the fd is
  usable by checking `fcntl(fd, F_GETFL)` succeeds and doing one
  non-blocking read attempt without EBADF/EPERM.
- Run the broker as root in the VM's default (host) mount namespace.
- Run the client INSIDE the confined snap's mount namespace + AppArmor
  label by starting a long-lived placeholder first (e.g.
  `snap run --shell ubuntu-desktop-session.xdg-document-portal -c
  "sleep 600"` backgrounded, to avoid racing the real crash-looping
  service), grabbing its PID, and using
  `nsenter --mount=/proc/<pid>/ns/mnt --pid=/proc/<pid>/ns/pid` (or
  simply running the client binary via a copy staged somewhere
  writable and reachable from within a `snap run --shell` invocation)
  to execute client.go with that exact confinement.

Verification (must all pass before Step 2):

- The client (running under full snap AppArmor confinement, WITHOUT
  fuse-support connected and WITHOUT any custom mount AppArmor rule)
  successfully receives the fd via SCM_RIGHTS and can use it
  (read/write/fcntl succeeds; no AppArmor denial in `journalctl` or
  `dmesg | grep DENIED` for the socket connect or the fd use).
- A THIRD, fully separate, unconfined process (e.g. a plain root SSH
  shell) can `ls`/`stat` the scratch mount path and see it behaving
  like a live FUSE mount (even a trivial always-ENOSYS stub is enough
  here -- this step is about plumbing, not full FUSE protocol
  correctness).
- No `nosuid`/`Permission denied` errors anywhere in this path.
- Document the exact confinement label / connect() rule that had to
  be allowed (or confirm none was needed) for the socket connect
  itself -- this determines whether Step 2's AppArmor work is needed
  at all.

### Step 2: Implement the production root-level broker daemon in Go.

Note: this step involves systemd socket-activation, security-sensitive
code, packaging decisions.

What to build (in core-base-desktop, as a new small Go module/binary,
built via the existing core-base-desktop build tooling and installed
by its Makefile similarly to the existing rm -f cleanup lines):

- A single static Go binary, e.g. `xdg-fuse-broker`, run as a systemd
  system service via socket activation:

      xdg-fuse-broker.socket  (ListenStream=/run/xdg-fuse-broker.sock,
        SocketMode=0666 or narrower if SO_PEERCRED checking makes a
        world-writable socket acceptable -- prefer the narrowest mode
        that still lets any logged-in user's confined session connect)
      xdg-fuse-broker.service (Requires=/After=the .socket unit;
        CapabilityBoundingSet limited to just CAP_SYS_ADMIN plus
        whatever DAC bits are actually needed; ProtectSystem=strict;
        NonBlocking=true since it's socket-activated)

- Protocol: single-byte command ('M' mount / 'U' unmount) followed by
  the requester's target subpath (NOT a full arbitrary path --
  construct the real path server-side from the verified peer uid,
  e.g. always mount at
  /run/user/<peer_uid>/snap.ubuntu-desktop-session/doc/ and never
  trust a client-supplied path string directly).
- MANDATORY: on each connection, call SO_PEERCRED (via
  `unix.GetsockoptUcred` in golang.org/x/sys/unix) and verify the
  connecting uid is the uid the mount path is being constructed for.
  Reject (close connection, log) any mismatch.
- Before mounting, always perform a lazy unmount (MNT_DETACH) of the
  target path first, to clear out any stale mount left behind by a
  previous crash (xdg-document-portal receiving SIGKILL leaves a
  zombie mount otherwise) -- ignore errors from this pre-emptive
  unmount since it's expected to fail when nothing is mounted yet.
- On 'U', perform the real unmount and reply with a status byte.
- Structured logging to stderr (captured by journald) for every
  mount/unmount attempt including the peer uid/pid and outcome, so
  failures are diagnosable exactly like the original bug was
  diagnosed via journalctl this session.
- Unit tests: path-construction logic (uid -> path) and the
  SO_PEERCRED validation logic should be pure-enough functions to
  unit test without needing root or a real socket (inject a fake
  Ucred/uid pair).

Verification (must all pass before Step 3):

- `go vet` / `go build` clean; unit tests for path construction and
  peer-uid validation pass.
- Deployed into core-base-desktop, rebuilt, fresh-booted VM:
  `systemctl status xdg-fuse-broker.socket` shows listening.
- A manual test client (reuse Step 1's client.go, unmodified) can
  connect and receive a real fd for the REAL target path
  (/run/user/1000/snap.ubuntu-desktop-session/doc/), and the mount is
  visible via `mount | grep doc` on the host.
- Test the crash-recovery path explicitly: mount once, kill -9 the
  test client, attempt to mount again -- confirm the pre-emptive lazy
  unmount lets the second mount succeed instead of failing with
  "already mounted" or leaving a stale "Transport endpoint not
  connected" state.
- Test the SO_PEERCRED rejection path: attempt a mount request for a
  uid that doesn't match the actual connecting process's uid (e.g.
  run the test client via `sudo -u someotheruser`) and confirm the
  broker rejects it and logs the rejection.

### Step 3: Implement the fusermount3-replacing client shim in Go.

Note: this step must correctly reverse-engineer/match the subset of
fusermount3's CLI contract that libfuse actually depends on.

What to build (in ubuntu-desktop-session-snap, as a new Go part built
alongside the existing snap parts):

- A Go binary named `fusermount3` (careful: must NOT collide with or
  shadow the system's real fusermount3 outside this snap's own
  resolution path -- verify via `command -v`/PATH ordering inside the
  built snap, not by name collision alone).
- Mount path: read `_FUSE_COMMFD` from the environment (the fd number
  of the socketpair end libfuse already set up), parse argv for the
  target mountpoint (libfuse passes it as the last non-flag argument),
  connect to the broker's socket, send 'M' + own uid-derived
  identifier, receive the real fd via SCM_RIGHTS, then relay it to
  libfuse over the `_FUSE_COMMFD` fd using the exact protocol
  fusermount3 uses (a single `Sendmsg` with a single `0` status byte
  plus the fd as ancillary data -- confirm this framing against
  libfuse's actual util/fusermount.c and lib/mount_util.c source
  rather than trusting the reference snippet verbatim, since getting
  this byte-for-byte wrong will silently break the handshake).
- Unmount path: detect `-u` (and the `-q -z` flags libfuse passes
  alongside it) in argv, send 'U' to the broker instead, exit
  0/nonzero matching fusermount3's own exit-code conventions closely
  enough that libfuse's caller-side error handling still behaves
  sanely.
- Clear, leveled logging to stderr for every step (connect failure,
  SCM_RIGHTS receive failure, relay failure) so a broken mount is
  diagnosable the same way the original bug was.

Verification (must all pass before Step 4):

- Standalone test (no real xdg-document-portal / libfuse involved
  yet): hand-craft a socketpair() in a small test harness that mimics
  what libfuse does (one end passed to the shim via `_FUSE_COMMFD`,
  the other end read directly by the test harness), run the shim
  against Step 2's real broker, and confirm the test harness's end of
  the socketpair receives a valid fd via SCM_RIGHTS with the exact
  byte framing libfuse expects (cross-check against libfuse source).
- Confirm unmount path sends 'U' and the broker's unmount logic runs
  (visible in broker logs / `mount | grep doc` disappearing).

### Step 4: Wire the shim into the confined snap, remove fuse-support

> SUPERSEDED: this Step 4 hit a confirmed blocker (the shim was never
> spawned because a bare revert of the AppArmor mount rule turns the
> mount(2) failure into EACCES instead of EPERM, so libfuse never
> falls back to fusermount3). See the new, multi-substep plan in
> `20260926-fuse-broker-step4-shim-wiring-v2.md`, which replaces
> everything below in this Step 4 section. Steps 5 and 6 below are
> UNCHANGED and still apply after that file's steps pass.

Note: this step involves multi-repo integration; needs judgement about
snapcraft/AppArmor tradeoffs.

What to change:

- ubuntu-desktop-session-snap/snap/snapcraft.yaml: ensure the shim
  binary built in Step 3 resolves as `fusermount3` ahead of any other
  copy on PATH for the `xdg-document-portal` app specifically (e.g.
  via `command-chain` or an explicit PATH prepend in the app's
  environment) -- do NOT rely on renaming/shadowing tricks that could
  accidentally affect other apps in the same snap that might
  legitimately want the real fusermount3 semantics.
- REVERT this session's fuse-support changes that are no longer
  needed: remove `fuse-support` from xdg-document-portal's plugs in
  snapcraft.yaml, remove the gadget.yaml auto-connection added to
  pc-amd64-gadget-desktop/gadget/gadget-amd64.yaml, and revert the
  AppArmor mount-rule patch in
  ubuntu-core-desktop-snapd/interfaces/builtin/fuse_support.go (keep
  the core-base-desktop Makefile change that removes the stock
  conflicting xdg-document-portal.service/.Documents.service unit
  files -- that part of the original fix is still correct and still
  needed regardless of which mount mechanism is used).
- Determine whether the confined snap needs ANY new AppArmor allowance
  at all to `connect()` the broker's UNIX socket path (Step 1 should
  have already answered this -- if a plain path-based UNIX socket
  connect to /run/xdg-fuse-broker.sock is already permitted by the
  snap's baseline confinement, no new interface is needed; if not,
  add the smallest possible new rule/interface in
  ubuntu-core-desktop-snapd scoped ONLY to that one socket path --
  do NOT reintroduce `capability sys_admin` or `/dev/fuse rw,`, since
  the whole point of this design is that the confined process never
  needs either).
- Rebuild all touched snaps + core-base-desktop + the full image via
  the image build (`build.sh`), exactly as done earlier this session.

Verification (must all pass before Step 5):

- Fresh clean boot (new VM instance, not a live-patched one -- this
  session already demonstrated live-patch testing gives unreliable
  results due to snapd's per-snap mount namespace caching).
- `systemctl --user status
  snap.ubuntu-desktop-session.xdg-document-portal.service`
  (via `systemctl --user --machine=your_username@ ...` as done this
  session) shows the service RUNNING and STABLE (no restart loop) --
  check `systemctl ... show -p NRestarts` stays at 0 or 1, not
  climbing.
- `mount | grep doc` on the host shows the FUSE mount present at
  /run/user/1000/snap.ubuntu-desktop-session/doc/.
- No AppArmor DENIED entries in `journalctl -b | grep DENIED` related
  to xdg-document-portal, fusermount3, or the broker socket.
- `snap connections ubuntu-desktop-session | grep fuse` shows NOTHING
  (fuse-support should no longer be plugged at all) -- confirms the
  security-sensitive interface was actually removed, not just unused.

### Step 5: Full end-to-end functional + regression verification.

Note: this step needs to interpret timing evidence and design
meaningful functional checks, not just re-run the same commands.

What to verify:

- THE ORIGINAL BUG IS FIXED: fresh autologin boot, measure the gap
  between GDM starting the session and gnome-shell reaching a ready
  state via journalctl timestamps (same method used in
  `20260925-autologin-portal-login-delay.md`) -- confirm no ~25-27s
  gap and no "portal is not running: Timeout was reached" /
  "service_start_timeout=25000ms" messages anywhere in the boot log.
- THE PORTAL IS ACTUALLY FUNCTIONALLY CORRECT, not just "not
  crashing": exercise the real D-Bus API, e.g.
  `gdbus call --session --dest org.freedesktop.portal.Documents
  --object-path /org/freedesktop/portal/documents --method
  org.freedesktop.portal.Documents.GetMountPoint`, and confirm a file
  added via the portal's AddFull/Add methods is genuinely readable
  through the returned FUSE-mounted path from an unconfined process
  (proving the fd handoff didn't just "work" at the socket level but
  produces a real, usable filesystem).
- CRASH RECOVERY: `kill -9` the running xdg-document-portal process,
  confirm systemd restarts it and the broker's stale-mount recovery
  (Step 2) lets the new instance mount cleanly with no manual
  intervention and no lingering "Transport endpoint not connected"
  errors.
- LOGOUT / SESSION-END CLEANUP: log out the autologin user (or
  `loginctl terminate-user <user>`), confirm the mount and any
  broker-side per-connection state are cleaned up (systemd-logind
  tearing down /run/user/<uid>/ should take care of the mount itself
  per this session's earlier finding -- verify this is still true
  here and doesn't leave the broker in a bad state for the next
  login).
- Capture the before/after boot-timing evidence (old vs new) as the
  final proof point for the fix.

### Step 6: Documentation, cleanup, and commit.

Note: the mechanical parts (writing the design note, moving the work
item file, cleaning up VM test artifacts) need no special judgement; a
final review pass before anything is actually committed/pushed needs
multi-step systems reasoning.

What to do:

- Add a short design note (e.g. docs/fuse-broker.md or a comment block
  at the top of the broker's source) explaining the architecture for
  future maintainers: why fuse-support/AppArmor capability grants
  don't work here, how the broker+shim+SO_PEERCRED design works, and
  a pointer back to flatpak/xdg-desktop-portal#695 as prior art.
- Move `20260925-autologin-portal-login-delay.md` and this file to
  done/ once Step 5 fully passes, with a short summary of the final
  fix appended.
- Clean up any leftover POC binaries/test artifacts left on the VM
  from Steps 1-3 (scratch mount paths, test sockets, etc).
- Prepare a clear cross-repo summary of the final diff (which repos
  changed, which fuse-support-era changes were reverted, which new
  files were added) for the user to review before any git commit.
- Do not `git commit`/push without explicit user go-ahead, consistent
  with how this session's earlier (now-reverted) fuse-support attempt
  was handled.

## Resolution (2026-09-26)

Steps 1-6 all complete; see
`20260926-fuse-broker-step4-shim-wiring-v2.md` for the detailed Step 4
redo (the original Step 4(b) plan was a dead end -- deleting the mount
rule outright gives AppArmor EACCES, not the EPERM libfuse's
fusermount3 fallback requires; the mount-allow rule had to be kept,
just re-homed into a new minimal `fuse-device` interface with no
capability sys_admin).

Step 5 (full end-to-end verification) results, all on a genuinely
fresh VM boot from the final image:

- Real D-Bus functional test: a file added via
  org.freedesktop.portal.Documents.Add (real FD-passing call via
  busctl, not just GetMountPoint) was genuinely readable through the
  FUSE-mounted path with correct content.
- Crash recovery: `kill -9` on the running xdg-document-portal process
  -> systemd restarted it cleanly (NRestarts=1), broker log shows a
  clean unmount-then-remount cycle, no "Transport endpoint not
  connected", GetMountPoint worked immediately after.
- Logout cleanup: `loginctl terminate-user` cleanly unmounted the FUSE
  filesystem (confirmed in broker log) with no lingering broker-side
  state.
- Capability check: confined portal process's CapEff/CapPrm both
  0000000000000000 throughout -- no capability leak.
- IMPORTANT SCOPE NOTE: the pre-existing, separately-tracked ~25-27s
  autologin portal-startup delay
  (`20260925-autologin-portal-login-delay.md`) is STILL PRESENT after
  this fix, unchanged -- confirmed it is unrelated to
  xdg-document-portal/FUSE (it's about
  org.freedesktop.portal.Desktop/colord/graphical-session.target
  ordering). This fuse-broker work does not fix it and was never
  expected to; that file remains open, not moved to done here.

Design note added as a doc comment above `package main` in
core-base-desktop/fuse-broker/broker.go.

Final diff is NOT yet committed anywhere -- see the cross-repo summary
given to the user for what's ready to commit (per repo: which files
are core feature source, which stray/unrelated untracked files were
found but NOT touched). Awaiting explicit user go-ahead before any
`git commit`/push, per this file's own Step 6 instruction.

## Follow-up regression + fix (2026-09-26, later same day)

After the above was marked resolved, launching a *different* confined
snap (App Center / snap-store, via `snap routine desktop-launch`)
failed with:

    WARNING: cannot start document portal: Expected portal at
    "/run/user/1000/doc", got "/run/user/1000/snap.ubuntu-desktop-session/doc"
    Failed to register: Timeout was reached

Root cause: making xdg-document-portal run confined (this todo's whole
point) gives it snapd's normal per-snap-instance private
$XDG_RUNTIME_DIR (/run/user/<uid>/snap.ubuntu-desktop-session/), so
its FUSE mount landed there too -- but snapd's own generic tooling
(cmd_run.go's desktop-launch check, used by every snap plugging
`desktop`; and the `desktop` interface's own AppArmor bind-mount rule)
both hardcode the assumption that the document portal lives at the
plain global /run/user/<uid>/doc, which was only true back when the
portal ran unconfined. This is a genuine gap in this project's own
design that Step 5's verification didn't catch (it never exercised a
second, separate snap's own desktop-launch path).

Fix (three small, additive changes, no snapd core-semantics changes):

1. ubuntu-desktop-session-snap/snap/snapcraft.yaml: override
   XDG_RUNTIME_DIR back to the real, unprivatized value, scoped to
   just the xdg-document-portal app (confirmed via upstream
   document-portal-fuse.c that
   XDG_RUNTIME_DIR/g_get_user_runtime_dir() is used ONLY for the FUSE
   mount path, nowhere else in the daemon).
2. core-base-desktop/fuse-broker/broker.go: allowedSubpaths allowlist
   entry changed from "snap.ubuntu-desktop-session/doc" to "doc" (the
   broker already never trusted a client-supplied path -- it validates
   the requested subpath against this allowlist and reconstructs the
   full path server-side from the peer's real UID).
3. ubuntu-core-desktop-snapd/interfaces/builtin/fuse_device.go: the
   interface's AppArmor mount rule target updated from the old
   snap-scoped path to the global path, plus a new
   `owner /run/user/[0-9]*/doc/ rw,` rule -- needed because libfuse
   itself (running inside the confined portal process) does its own
   preflight mkdir() of the mountpoint before ever invoking
   fusermount3/the shim/broker, which was otherwise denied.
   (fuse_device_test.go updated to match.)

No fusermount3-shim or broker *logic* changes were needed; the shim's
subpathFromMountpoint() already derives the subpath generically from
whatever mountpoint libfuse actually requests.

Verified end-to-end on a genuinely fresh VM boot, all three fixes
combined (via a real rebuilt+redeployed snapd.snap, not just a live
AppArmor profile patch):

- `mount | grep doc` shows the FUSE mount at the correct global
  /run/user/1000/doc, no AppArmor denials in dmesg.
- xdg-document-portal.service starts and stays running (was
  crash-looping, status=6, before the AppArmor mkdir rule was added).
- Real FD-passing functional test (busctl ... Documents.Add hbb ...)
  returns a doc ID and the file is genuinely readable back through
  the FUSE mount with correct content.
- The original trigger (`snap routine desktop-launch` for
  snap-store_snap-store.desktop) no longer emits the "Expected portal
  at ... got ..." / "Failed to register: Timeout was reached" error.

This file's own scope (fuse-broker + document-portal confinement,
including this global-mount-path follow-up) is now considered fully
DONE. No further action pending here.
