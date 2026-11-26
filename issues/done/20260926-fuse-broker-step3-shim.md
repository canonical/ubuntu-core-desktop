# fusermount3-replacing client shim, verified on the VM

## Impact / Priority

No user-facing impact of its own — Step 3 of the fusermount-broker plan
implemented the fusermount3-replacing shim and verified it against the
real broker; the shim is what lets libfuse inside the confined portal
receive its FUSE fd without any privilege of its own. Impact derived
from the original note's described symptoms.

## Context

The confined xdg-document-portal snap cannot call mount(2) itself (no
CAP_SYS_ADMIN, and fusermount3's setuid mechanism is dead on the nosuid
rootfs). Step 3 replaces fusermount3 with a small Go shim that forwards
the mount request to the Step 2 privileged broker over a UNIX socket,
receives the live /dev/fuse fd via SCM_RIGHTS, and relays it back to
libfuse over the _FUSE_COMMFD socketpair using fusermount3's exact
framing.

## Where the code lives (ubuntu-desktop-session-snap, branch 26-dev)

- fusermount3-shim/go.mod        module fusermount3-shim, go 1.21
- fusermount3-shim/main.go       the shim (arg parsing, broker client,
                                 fd relay, auto-unmount wait)
- fusermount3-shim/main_test.go  unit tests (all pass)
- snap/snapcraft.yaml            new `fusermount3-shim` part; builds the
                                 binary and installs it to
                                 /usr/libexec/ubuntu-desktop-session/fusermount3
                                 (NOT on the default PATH -- see below)

## CLI contract implemented (the subset libfuse actually uses)

    mount:        fusermount3 -o <opts> -- <mountpoint>      (_FUSE_COMMFD set)
    auto-unmount: fusermount3 --auto-unmount -- <mountpoint> (_FUSE_COMMFD set)
    unmount:      fusermount3 -u -q -z -- <mountpoint>
    version:      fusermount3 --version
    help:         fusermount3 -h

## Framing (cross-checked against libfuse 3.16.2 source, not assumed)

- libfuse lib/mount.c receive_fd() reads exactly 1 byte + SCM_RIGHTS.
- libfuse util/fusermount.c send_fd() sends exactly 1 zero byte
  (sendchar = 0) plus the fd as SCM_RIGHTS in a single sendmsg.
- The shim's relayFD() does exactly this: Sendmsg(commfd, []byte{0},
  UnixRights(fuseFd), nil, 0). Verified byte-for-byte against source.

## Important gotcha: auto_unmount is a SECOND invocation

xdg-document-portal mounts with the "auto_unmount" option
(document-portal-fuse.c: "-osubtype=portal,fsname=portal,auto_unmount").
When auto_unmount is set, libfuse calls fusermount3 TWICE:

1. the normal mount call (fuse_mount_fusermount), then
2. setup_auto_unmount() -> `fusermount3 --auto-unmount -- <mnt>`, which
   must BLOCK until the _FUSE_COMMFD socketpair is closed (i.e. the
   FUSE daemon died) and only then unmount.

A shim that only handles the mount/unmount forms will fail the real
portal with `unknown option "--auto-unmount"`. The shim now implements
this: it reads the commfd until EOF, then sends 'U' to the broker.
(This was missed in the first pass and caught by re-reading libfuse
source; it is the single most important finding of Step 3.)

## Broker protocol spoken by the shim (identical to Step 2)

    [cmd byte][uid uint32 BE][subpath len uint16 BE][subpath]
    cmd 'M' = mount, 'U' = unmount. The shim derives the subpath from the
    mountpoint by stripping the /run/user/<uid>/ prefix; the broker
    re-validates it against its allowlist and rebuilds the path itself, so
    the client can never influence the /run/user/<uid> prefix.

## Verification (all passed on the core26-desktop test VM)

Harness: fuse-poc/step3harness/main.go — mimics libfuse: creates a
socketpair, passes one end to the shim via _FUSE_COMMFD, reads the
other end expecting 1 status byte + SCM_RIGHTS fd.

- Mount: harness received status byte 0x0 and a valid fd (fstat
  mode=020666 rdev=2789); `mount | grep doc` shows
  "xdg-document-portal on /run/user/1000/snap.ubuntu-desktop-session/doc
  type fuse (rw,nosuid,nodev,relatime,user_id=1000,group_id=1000)".
- Unmount: shim sent 'U', broker unmounted, mount disappeared, exit 0.
- Auto-unmount: shim blocked on commfd, harness closed its end, shim
  logged "FUSE daemon exited, unmounting", broker unmounted, exit 0.
- Confined (enforce): `snap run --shell
  ubuntu-desktop-session.xdg-document-portal` -> connect to
  /run/xdg-fuse-broker.sock fails with EACCES (AppArmor), as expected
  from Step 1. This is the Step 4 work item.
- Confined (complain): same test succeeds — mount visible, unmount
  works, exit 0. Confirms the shim itself needs no privilege and the
  only missing piece is the AppArmor connect rule.

## Harness gotcha (cost time)

A raw syscall.Socketpair() does NOT set CLOEXEC, so the harness's own
end of the socketpair leaks into the shim child. Closing the harness's
copy then never produces EOF and the auto-unmount test hangs forever.
Real libfuse closes fds[1] in the child. Fix: set FD_CLOEXEC on the
harness end before exec.

## PATH-shadowing note (for Step 4)

The shim is installed to
/usr/libexec/ubuntu-desktop-session/fusermount3, deliberately NOT as a
bare `fusermount3` on the default PATH, so it cannot shadow the system
fusermount3 for other apps in the same snap. Step 4 must make it
resolve as `fusermount3` for the xdg-document-portal app specifically
(command-chain or an explicit PATH prepend in that app's environment).
libfuse's exec_fusermount() tries FUSERMOUNT_DIR/fusermount3 first,
then execvp("fusermount3") on PATH, so a PATH prepend is sufficient.

## Fast-iteration method

Build the Go binary locally, scp it to the VM, run it directly — no
full snap rebuild. The shim and harness were staged into
/run/user/1000/snap.ubuntu-desktop-session/ so they are visible inside
the confined snap's mount namespace.
