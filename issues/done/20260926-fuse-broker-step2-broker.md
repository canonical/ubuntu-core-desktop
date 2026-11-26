# FUSE-mount broker: production implementation, verified on the VM

## Impact / Priority

No user-facing impact of its own — Step 2 of the fusermount-broker plan
shipped the production `xdg-fuse-broker` (core-base-desktop, branch
26-dev) and verified it end-to-end under real systemd socket activation;
it is the privileged component that performs the FUSE mount on behalf of
the confined xdg-document-portal. Impact derived from the original
note's described symptoms.

## Context

The production privileged broker now lives in core-base-desktop and was
verified end-to-end on the core26-desktop test VM using the real systemd
units and the real socket-activation path (not just the manual
fallback). Step 1's POC design carried over unchanged; the work here was
turning it into a shipped, hardened, socket-activated service.

## Where the code lives (core-base-desktop, branch 26-dev)

- fuse-broker/go.mod            module xdg-fuse-broker, go 1.21
- fuse-broker/main.go           entrypoint; slog to stderr; systemd
                                socket activation (LISTEN_PID/LISTEN_FDS,
                                fd 3) with a fallback that creates
                                /run/xdg-fuse-broker.sock (0666) for
                                manual runs; accept loop -> broker.handle
- fuse-broker/broker.go         protocol + mount/unmount logic (below)
- fuse-broker/broker_test.go    unit tests (all pass)
- static/usr/lib/systemd/system/xdg-fuse-broker.socket
- static/usr/lib/systemd/system/xdg-fuse-broker.service
- static/usr/lib/systemd/system/sockets.target.wants/xdg-fuse-broker.socket
- snapcraft.yaml                new `fuse-broker` part; added to the
                                `hooks` part's `after:` list

## Protocol (client -> broker, one request per connection)

    [cmd byte][uid uint32 BE][subpath len uint16 BE][subpath bytes]
    cmd 'M' = mount, 'U' = unmount. Reply: 1 status byte ('0' ok, '1' error)
    followed by an error message on failure; on success for 'M' the live
    FUSE fd is passed back via SCM_RIGHTS.

## Security model (all verified)

- The client sends only a uid and a subpath; the broker builds the
  mount path itself as /run/user/<uid>/<subpath>. The subpath is
  checked against a hard allowlist (snap.ubuntu-desktop-session/doc)
  and must be a clean relative path (no leading '/', no '..', no
  empty/double-slash components). Absolute paths, traversal, unknown
  subpaths and empty subpaths are all rejected (unit-tested).
- SO_PEERCRED is read off the socket and the peer's uid must equal the
  requested uid. Verified: a uid-1000 client asking for uid 0 is
  rejected ("peer uid 1000 does not match requested uid 0"); a
  uid-65534 (nobody) client asking for uid 1000 is rejected too. This
  is why the socket can safely be mode 0666.
- mount() does a pre-emptive MNT_DETACH of any stale mount at the
  target (ignoring "not mounted"), MkdirAll's the mountpoint, opens
  /dev/fuse, then mount(2) with MS_NOSUID|MS_NODEV and
  "fd=N,rootmode=40000,user_id=<uid>,group_id=<gid>".
- unmount() does a real umount first, falling back to lazy (MNT_DETACH).

## Verified on the VM (real systemd, real socket activation)

- xdg-fuse-broker.socket comes up "active (listening)" with the socket
  file srw-rw-rw- root:root at /run/xdg-fuse-broker.sock; the service
  is NOT started until the first connect (correct socket activation).
- First connect starts the service; the mount request succeeds and the
  mount appears in the HOST mount namespace:

      xdg-document-portal on /run/user/1000/snap.ubuntu-desktop-session/doc
      type fuse (rw,nosuid,nodev,relatime,user_id=1000,group_id=1000)

- The confined snap sees it too (snap run --shell
  ubuntu-desktop-session.xdg-document-portal):

      ... /run/user/1000/snap.ubuntu-desktop-session/doc ... master:711
      - fuse xdg-document-portal rw,user_id=1000,group_id=1000

  (stat returns ENOSYS because the test client is a stub, as expected).
- Crash recovery: kill -9 the client, re-request -> broker logs
  "cleared stale mount" and the remount succeeds.
- Unmount request ('U') removes the mount.

## Critical finding: the service MUST stay in the host mount namespace

The first hardened unit used ProtectSystem=strict + ProtectHome=true +
PrivateTmp=true. Every one of those options implies a private mount
namespace, and the FUSE mount then landed ONLY in the service's own
namespace — invisible to the host and to the confined snap, silently
breaking the whole mechanism (the mount "succeeded" but nothing could
see it). Confirmed by comparing /proc/<pid>/ns/mnt: with those options
the service had a different mnt ns from PID 1; after removing them the
service shares PID 1's mnt ns and the mount propagates.

=> xdg-fuse-broker.service must NOT use ProtectSystem=, ProtectHome=,
PrivateTmp= or PrivateMounts=. This is documented in a comment in the
unit file so nobody "hardens" it back into a broken state.

## Two more unit-file findings

- ProtectHome=true also hides /run/user entirely (it is bind-mounted
  from /run/user/<uid>), so even the mountpoint mkdir fails with
  EROFS/ENOENT. Another reason it must not be used.
- mount(2)/umount(2) are in the @mount syscall group, which is NOT
  part of @system-service. With SystemCallFilter=@system-service alone
  the mount failed with EPERM. The unit now uses
  SystemCallFilter=@system-service @mount.

## Remaining hardening that IS kept (and verified compatible)

CapabilityBoundingSet/AmbientCapabilities=CAP_SYS_ADMIN CAP_DAC_OVERRIDE,
NoNewPrivileges=true, RestrictAddressFamilies=AF_UNIX,
RestrictNamespaces=true, LockPersonality=true,
MemoryDenyWriteExecute=true, SystemCallFilter=@system-service @mount,
SystemCallErrorNumber=EPERM.

## Build/packaging note

The `fuse-broker` snapcraft part installs into
${CRAFT_PART_INSTALL}/base/usr/bin/xdg-fuse-broker (the base/ tree is
flattened to the snap root by the `hooks` part). It needs
`override-prime: # No files from this step in prime` or its base/ tree
leaks into prime. The full snap has NOT yet been rebuilt with this fix;
verification above used the fast path (scp the Go binary to the VM and
run it under the real units), per the agreed iteration strategy.

Step 2 verification: PASSED (code + units + socket activation + security
model + namespace propagation). Next: Step 3 (fusermount3-replacing shim
in ubuntu-desktop-session-snap) and Step 4 (AppArmor interface in
ubuntu-core-desktop-snapd, scoped to the broker socket path only).
