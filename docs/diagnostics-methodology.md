# General diagnostics methodology for Ubuntu Core Desktop VMs

Reusable techniques for debugging a running Core image, independent
of any specific bug. See gdm-graphical-session.md, boot-diagnostics.md
and build-tools.md for topic-specific facts.

## A live-patched build/test container is not evidence a bug is fixed

If you fix a build or runtime bug by live-patching a running
container/VM (editing files directly in an LXD build container, a
live-mounted overlay, a manually-edited unit file, etc.) without
landing the equivalent change in the actual source/recipe
(snapcraft.yaml, override-* scripts, vendored patches, packaged unit
files, etc.), that is NOT a fix — it's just a temporary local state.
Any subsequent clean rebuild (`--clean`, a fresh container, a
reflashed image) wipes that state and silently rediscovers the exact
same bug from scratch, and a later agent/session has no way to know
it was ever "fixed" before. Always land the change in git before
considering any such issue resolved; treat a live-patched success as,
at most, confirmation of the right fix to commit, never as the
deliverable itself.

## No-SSH diagnostics via netcat reverse shell

SSH access to a test VM can be lost mid-session (e.g. sshd not yet
enabled, or broken by whatever you're testing). If you still have a
netcat root reverse-shell (nc listening/connecting to a fixed port,
piping into a shell), you can keep working, but:

- Each invocation is a fresh shell — `cd`/env vars/background jobs do
  NOT persist between calls. Always use absolute paths, and start any
  background process with an explicit backgrounding idiom the shell
  supports (nohup ... &) if you need it to outlive the connection.
- A single `nc -l` (without `-k`) only accepts one connection and
  then exits — if the listener isn't in a `while true; do ...; done`
  wrapper on the far end, a slow/long-running foreground command
  (e.g. `find /` over the whole filesystem) can end up hanging the
  pipe long enough that the connection drops and is never
  re-established, permanently losing the shell until someone restarts
  the listener from the VM's own console. Avoid unbounded/slow
  recursive commands over this kind of shell; scope `find`/`grep` to
  specific directories.
- If SSH access becomes available mid-session (e.g. the user gives
  you credentials once a user account exists), and the host has no
  `sshpass` installed and no `sudo` to install one, `expect` (often
  preinstalled) works fine as a scriptable password-entry wrapper for
  both `ssh` and `sudo -S` prompts.

## journalctl auto-discovery can go flaky after live filesystem changes

After overlay-mounting parts of the running root filesystem (see
below), plain `journalctl -b0 ...` can intermittently return "No
journal files were found" even though journald is still running and
healthy. Workaround: query the journal file directly by explicit
path:

    cat /etc/machine-id   # get the machine ID
    journalctl --file=/var/log/journal/<machine-id>/system.journal \
      --no-pager -o short-precise ...

This is more reliable than plain `journalctl` for the rest of a
session once this symptom appears — prefer it once you've seen the
flakiness once, rather than re-diagnosing it each time.

## Live-patching a read-only Ubuntu Core rootfs for testing

To test a fix to a normally-read-only path (e.g. /usr/share,
/usr/sbin, /etc) without a full rebuild/reflash, overlay-mount it
live:

    mkdir -p /run/<name>-overlay/upper /run/<name>-overlay/work
    mount -t overlay overlay -o lowerdir=<path>,upperdir=/run/<name>-overlay/upper,workdir=/run/<name>-overlay/work <path>

This is session-only (lost on reboot) and safe to layer over paths
that already have their own bind-mounts/submounts underneath (e.g.
/etc having fstab bind-mounts for /etc/hosts, /etc/machine-id,
/etc/ssh, /etc/systemd) — those submounts survive the overlay
intact. Useful for quickly testing a candidate fix (delete/add a
file, swap a binary) before committing to a real packaging change.

For a single binary/script rather than a whole directory, a
bind-mount of a replacement file over the original works too (e.g.
shimming gnome-session — see gdm-graphical-session.md for a worked
example), and is revertible with a plain `umount`.

Gotcha: some symlink-based "writable /etc" designs (symlinks under
/etc pointing into a genuinely-writable /etc/writable bind mount)
break tools that do atomic writes via
temp-file-in-same-dir-then-rename, because the atomic write targets
the symlink's own (read-only) directory, not the resolved target's
directory. If a specific writable-looking file still fails with
"Read-only file system" from an atomic-write tool, check whether it's
actually a symlink into a bind-mounted "writable" area rather than a
direct bind-mount itself.

Gotcha: a systemd service with `ProtectSystem=strict` (or similar
namespacing directives) takes a private mount-namespace snapshot at
service (re)start time. Any overlay/bind changes you make to the live
filesystem *after* that service is already running will not be
visible to it (or anything it execs) until you `systemctl restart`
that specific service. Check `systemctl show <unit> -p ReadWritePaths
-p ReadOnlyPaths -p ProtectSystem` any time a service behaves as if
it can't see a change you just made on disk — don't assume it's a
permissions or logic bug before checking this.

## Two independent D-Bus denial mechanisms — check both, don't conflate

"Rejected send message" errors can come from two unrelated places:

1. Classic D-Bus bus policy — `dbus-daemon[N]: [system] Rejected send
   message, N matched rules`, governed by
   `/usr/share/dbus-1/system.d/*.conf` files (evaluated by
   specificity/order), nothing to do with AppArmor. On this image,
   snap-packaged system services (e.g. the network-manager snap)
   sometimes don't ship the classic D-Bus policy file that the
   equivalent .deb normally provides — check for a missing
   `org.freedesktop.<Service>.conf` under
   `/usr/share/dbus-1/system.d/` before chasing AppArmor.
2. AppArmor D-Bus mediation — `audit[...]: apparmor="DENIED" ...
   operation="dbus_method_call"`. A genuinely separate mechanism.

Switching a snap's AppArmor profile to complain mode
(`apparmor_parser -r -C /var/lib/snapd/apparmor/profiles/snap.<x>.<y>`)
is a quick way to rule AppArmor in/out, but don't assume it's the
cause just because a D-Bus call is being rejected — check
dbus-daemon's own audit lines for "Rejected send message" (classic
policy) vs. kernel audit lines with `apparmor="DENIED"` (AppArmor) to
tell which mechanism is actually responsible before spending time on
a fix.

## Diagnosing what a system daemon passes to a CLI tool it shells out to

Ubuntu Core images may not have `strace`. To see exactly how a daemon
(e.g. accounts-daemon) invokes an external CLI tool (e.g. chpasswd)
when you can't add logging to the daemon itself: temporarily replace
the target binary with a wrapper shell script that logs
argv/stdin/env to a file, then execs the renamed real binary.
Gotchas:

  - If the calling service has `ProtectSystem=strict` (or similar),
    most of the filesystem — including /tmp and /var/log — may be
    read-only from that service's perspective, even though it's fine
    outside the service. Check the unit's `ReadWritePaths=` and put
    your log file somewhere on that allowlist (e.g. a scratch file in
    a directory that's already known-writable to the service).
  - To directly test whether a mount-namespace difference (vs. some
    other sandboxing) is the cause of a discrepancy between a manual
    invocation and the daemon's invocation, use
    `nsenter --target <daemon-pid> --mount -- <command>` to run the
    same command inside exactly the daemon's mount namespace, without
    needing strace at all.

## Live-stracing a snap-confined systemd --user service

Getting a working `strace` binary onto a minimal/read-only rootfs (no
dpkg/apt, can't write /usr/lib): copy a matching-arch strace binary
from a same-distro host plus its missing shared libs (commonly
libunwind-ptrace.so.0, libunwind-x86_64.so.8, libunwind.so.8) to a
scratch dir (e.g. /tmp) on the device, then
`patchelf --set-rpath <dir> --force-rpath` on the strace binary
itself so the dynamic linker finds the bundled libs unconditionally —
`LD_LIBRARY_PATH` does NOT survive through `snap run` (snapd
sanitizes the environment before exec'ing the traced command), so an
`Environment=` drop-in setting it has no effect. Verify locally first
with `env -i <patched-binary> -V`.

Don't wrap `ExecStart=` in a bare `strace <cmd>` for a snap app: if
the target execs through snap-confine, an external ptracer already
attached before snap-confine's own seccomp/ptrace-sensitive setup
runs makes snap-confine fail immediately (unit fails with result
'protocol'). Use snapd's own tracing support instead:
`snap run --strace="<opts>" <snap>.<app> -- <args>` (put strace on
PATH via a systemd drop-in so snapd's internal exec of "strace"
resolves to your patched binary). Don't use strace's `-o <file>`
either — the confined child gets a private mount namespace/private
/tmp, so an absolute -o path can resolve to a location invisible from
outside the confinement. Omit `-o` (trace goes to strace's own
stderr, which for a systemd-managed process lands in the journal) and
read it back with `journalctl --user -u <unit>` (or filtered by
timestamp).

For a `Type=notify`/`NotifyAccess=main` unit, plain `strace <cmd>`
forks a new child to run <cmd> while strace itself keeps the PID
systemd is tracking as MainPID — so the actual notifying process has
the wrong PID and readiness notifications are silently ignored. Use
strace's `-D` flag (reparents so the traced program keeps the PID
relationship systemd expects); combine freely with `-f` to follow
forks/execs through the whole snap-confine chain.

Systemd drop-ins across ALL directories (vendor /usr/lib, /etc, user
~/.config/systemd/user) are merged and applied in lexicographic order
BY FILENAME ONLY, regardless of which directory they live in — ASCII
digits sort before lowercase letters, so e.g. `99-my-debug.conf` is
applied (and overridden by) a later `core-override.conf` in a
lower-priority directory. Don't assume ~/.config always "wins";
verify the actual merged `ExecStart=` with
`systemctl --user cat <unit>` after any daemon-reload, and if you
need to guarantee an override applies last, name it to sort after any
existing drop-ins (e.g. a `zzz-` prefix). Always `daemon-reload`
after adding/removing a drop-in, and remove/revert any debug drop-in
once done.

## A systemd drop-in resetting a multi-value directive can silently not stick

The normally-reliable pattern for removing an inherited value from a
multi-value directive via a drop-in is `After=` (empty, to reset)
then `After=dbus.service` (to reassign). This can appear to work by
every static check (`systemctl --user cat`/`show -p DropInPaths`
show the drop-in correctly merged/applied, and unrelated fields in
the same drop-in do take effect) while the *effective* property
(`systemctl --user show <unit> -p After`) still reports the old value
on every fresh login, with neither `daemon-reload` nor
`daemon-reexec` clearing it — observed on systemd 259.5-0ubuntu3.4
for a `Type=dbus`/`BusName=`-activated unit's
`After=graphical-session.target`. No systemd-internal root cause was
identified. If a drop-in's empty-then-reassign reset doesn't stick
for a *specific* value despite being confirmed parsed/applied for
everything else, don't keep debugging the drop-in mechanism —
replace the unit file wholesale at the same path instead, and
re-verify with `systemctl --user show -p <Property>` before assuming
the override approach itself is broken.

## exec.Command(...).CombinedOutput() silently drops stderr on success

If you add stderr-only debug tracing to a CLI tool to see how some
other process invokes it, and that tool is invoked via Go's
`exec.Command(...).CombinedOutput()` (e.g. snapd's
`runNamespaceTool()` in `interfaces/mount/ns.go` invoking
`snap-update-ns`), tracing shows zero hits for invocations triggered
that way even though they do run — `CombinedOutput()` only surfaces
stderr on error, discarding it on success. Only invocations made
directly (e.g. via `snap-confine --from-snap-confine`) will show up
in stderr-based tracing. Use file-based logging instead when
instrumenting code that might be invoked through a
`CombinedOutput()`-style call.

## Ubuntu Core's extrausers accounts: tool support is inconsistent

Accounts on Ubuntu Core Desktop live in
/var/lib/extrausers/{passwd,shadow,group,gshadow}, not /etc/passwd et
al. Support for this across shadow-utils commands is NOT uniform —
check each tool independently rather than assuming they're all
consistent:

  - useradd/groupadd/userdel/groupdel: support an explicit
    `--extrausers` flag.
  - usermod/chpasswd: stock chisel/Debian builds have NO
    `--extrausers` flag and silently target the read-only
    /etc/shadow — don't pass `--extrausers` to them on an unpatched
    image (it just errors). core-base-desktop now vendors the
    UCD-PPA `passwd` package (passwd_4.17.4-2ubuntu3+ucd1, in debs/,
    forward-ported from the 22.04-era desktop-snappers/core-desktop
    PPA) which makes `usermod`/`chpasswd` extrausers-aware without
    any new flag, plus a matching `adduser` build
    (adduser_3.153ubuntu1+ucd1) that drops adduser's own
    `usermod --extrausers` call (a flag that never existed upstream).
    With these two packages installed, plain `usermod`/`chpasswd`
    work against extrausers transparently — don't assume the tool is
    broken before checking which passwd/adduser build is actually on
    the image. (A `gpasswd` rewrite of adduser's group-add path also
    works — gpasswd has explicit `--extrausers` support — but the
    PPA lineage above is the established fix and also covers
    chpasswd.)

`.deb` extraction may not be possible on the target Core image itself
(no `ar`) — extract on the host (`ar x file.deb && tar xf
data.tar.*`) and transfer only the specific file(s) needed.

## void dir and user-journal access on a fresh VM (SSH diagnostics)

- `snap run --shell <snap.app>` on a freshly built/booted image fails
  with "cannot create void directory: /var/lib/snapd/void: Permission
  denied" (snapd doesn't pre-create it). Fix before using
  `snap run --shell` for in-session debugging:
  `install -d -m 0755 -o root -g root /var/lib/snapd/void`.
- `journalctl --machine=user@.host --user` from an ssh root shell
  fails ("Connecting to a machine as non-root is not supported"). Use
  the system journal filter instead, e.g.:
  `journalctl _SYSTEMD_USER_UNIT=snap.<snap>.<unit>.service`.

## Process-name matching gotchas (pgrep/pkill)

- `pgrep -x <name>` cannot match comm names longer than 15 chars
  (e.g. `kscreenlocker_greet` gets silently truncated by the kernel's
  `comm` field) — use `ps -eo comm=` or `pgrep -f` with a guard
  against self-matching instead.
- A remote `pgrep -f <pattern>` run over
  `ssh user@host pgrep -f ...` can match its OWN ssh/pgrep
  command-line string in the process table on the remote end,
  producing a false-positive match (e.g. a "still locked" conclusion
  when nothing is actually locked). Prefer `pgrep -x` (exact comm
  match, mind the 15-char limit above) over `-f` when running checks
  remotely.
- `pkill -f "pipewire-puls[e]"` (the character-class trick to avoid
  matching pkill's own command line) still matches a LITERAL
  occurrence of the same string elsewhere on the same command line
  (e.g. an exec path like `.../usr/bin/pipewire-pulse` present in the
  same `bash -c "..."` invocation) — split `pkill` and the rest of
  the command into separate invocations (e.g. separate `ssh` calls)
  to avoid killing your own remote shell.

## snapd's systemd unit is generated, not static, on Ubuntu Core

snapd.service / snapd.socket are not shipped as static unit files
under /etc or /usr/lib/systemd/system on this image — they only exist
via `/usr/lib/systemd/system-generators/snapd-generator`, which is
supposed to generate them into /run/systemd/generator/ from whichever
revision of the snapd snap is currently active
(`/snap/snapd/current`). If snapd.service ever shows as
`Loaded: not-found` (as opposed to just "failed"), check whether the
generator actually produced anything in /run/systemd/generator/ — if
it silently produced nothing, you can recover by copying the real
unit files directly:

    cp /snap/snapd/<rev>/lib/systemd/system/snapd.service /etc/systemd/system/
    cp /snap/snapd/<rev>/lib/systemd/system/snapd.socket  /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable snapd.socket snapd.service
    systemctl start snapd.service

This is a workaround, not a fix for whatever made the generator
decline to regenerate the units — but it's a fast way to get
snap/App Center/any snap-packaged app working again without a reboot
or reflash.

## Snap tree comparisons: don't trust a previously-extracted reference tree

A previously-unsquashed "store reference" tree can be LOSSY: a plain
extraction silently drops root:shadow-owned files (etc/shadow,
etc/gshadow, etc/security/opasswd, extrausers' shadow/gshadow and
their usr/share/factory copies), /dev char devices, and original
uid/gid ownership — producing false "only in build" diff hits for
exactly those paths. For any file-level diff against a
"stock"/store snap, unsquash a FRESH copy (`snap download <name>
--revision=<rev>`, `unsquashfs -ll` to see true modes/owners/devices)
rather than trusting an old extracted tree lying around from a
previous session.

## Diagnosing "SSH pubkey refused" on UC images

- sshd at default `LogLevel=INFO` logs successful pubkey auth but NOT
  failed attempts (those are `VERBOSE`) — a journal with no failures
  proves nothing about whether a key was refused. Temporarily drop
  `LogLevel VERBOSE` in `/etc/ssh/sshd_config.d/` and restart ssh to
  see actual refusal reasons ("bad ownership or modes", "Failed
  publickey").
- A readiness probe that opens a TCP connection and closes it
  (`nc -z`, banner checks, an ssh client with no usable key) shows in
  the journal as "Connection closed by <ip> port X [preauth]" at a
  steady cadence — that's a probe, not an auth failure; don't
  conflate the two patterns.
- During the early boot window (snap seeding/installs, ~1-5 min on
  the thin image), sshd may be down/restarting and clients just see
  "Connection refused"/timeouts — don't misread this transient window
  as a pubkey-auth problem; verify with
  `ssh -o BatchMode=yes -i <key> root@<vm> true` once the window has
  passed, plus `stat` perms (600 root:root key, 700 root:root
  `.ssh`/`/root`) and
  `sshd -T | grep -E 'permitrootlogin|pubkeyauthentication'`.
- The core-base-variant snap ships
  `usr/share/factory/.../root/.ssh` EMPTY (mode 700) by design — the
  per-image `authorized_keys` is added by the image repo's build.sh
  after unpacking the base snap. An empty `.ssh` in the base snap
  alone is not a bug.

## QEMU VM audio: getting guest sound to a human listener (VNC testing)

`-display none` (VNC) VMs have NO audio path at all by default — VNC
is video/keyboard/pointer only. Two things are needed: a virtual
sound card in the guest wired to a QEMU `-audiodev` backend, and a
backend the launching account (e.g. a service account with no desktop
session) can actually reach:

    -audiodev <backend>,id=snd0 -device intel-hda -device hda-output,audiodev=snd0

(`hda-output` = playback only; `hda-duplex` adds recording.) Backend
choices:

- `alsa,out.dev=plughw:<card>` — plays straight to a host sound card.
  Needs the launching account in the `audio` group (group changes
  don't affect already-running shells — relaunch via
  `sg audio -c "..."`). Use `out.dev=` (not `device=`), and a
  comma-free device spec (`plughw:1`, not `plughw:CARD=...,DEV=0` —
  comma-escaping in `-audiodev` values is a trap). `aplay -l`
  reporting "no soundcards found" while `/dev/snd` exists is the
  missing-group symptom, not an absent card.
- `pipewire,id=snd0` with `PIPEWIRE_RUNTIME_DIR=/run/user/<uid>` set
  on the QEMU process — routes guest audio into a specific desktop
  user's pipewire/default sink with no device contention; the
  preferred choice when a human listener's own session is the target.
  Needs that user's runtime dir opened once
  (`chmod 755 /run/user/<uid>`, no sudo). Without
  `PIPEWIRE_RUNTIME_DIR`, QEMU looks for the CALLING user's own
  session and fails ("Host is down") if it has none.
- `file,out.filename=...wav` — post-hoc review only, not live.

Guest-side verification: `/proc/asound/cards` shows the card even
with no userspace audio tools staged; check the guest's
pipewire/wpctl for a real sink (not `auto_null`). Host-side: for
alsa, `/proc/asound/card<N>/pcm0p/sub0/status` must show
`state: RUNNING` while the guest speaks (not just `SETUP` =
open-but-idle); for pipewire, `PIPEWIRE_RUNTIME_DIR=<dir> wpctl
status` shows a QEMU sink-input.

Process gotchas: QEMU's `comm` truncates to 15 chars
(`qemu-system-x86`), so `pkill -x qemu-system-x86_64` is a silent
no-op — use `pkill -f` (or kill by PID if a launch wrapper's own
cmdline also matches the pattern). After SIGTERM, QEMU releases its
drive lock asynchronously — wait ≥8-10s before relaunching or you get
"Failed to get 'write' lock". For any GUI testing over VNC, also add
`-device qemu-xhci -device usb-tablet` (no pointing device in the
guest means VNC clicks never reach a Wayland session).

## Auditing for pre-snap leftovers that compete with snapped services

When a service moves from the base/content tree into a snap, its old
systemd units / D-Bus activation files can survive in the base and
compete with (or shadow) the snap at runtime. Audit method (used
2026-11-15 on the core26-desktop image):

1. Enumerate every snap daemon: `unsquashfs -cat <snap>
   meta/snap.yaml` -> apps with
   `daemon:`/`daemon-scope:`/`activates-on:` (snapd generates
   snap.<snap>.<app>.service, plus .<socket-name>.socket for snap
   `sockets:`).
2. Enumerate the base tree from the built core.snap:
   `unsquashfs -l core.snap | grep systemd/{system,user}/`, plus
   `etc/systemd/**` enablement and the
   `usr/share/factory/writable/system-data/etc/systemd/**` copy.
3. Check session + system D-Bus activation files
   (`/usr/share/dbus-1/{services,system-services}`) against snapd's
   (`/var/lib/snapd/dbus-1/{services,system-services}`) for duplicate
   `Name=` entries and `Exec=` paths not present in the base — but
   skip files with `SystemdService=` in missing-Exec scans (those do
   NOT use `Exec=`).
4. Boot a copy and verify live: `systemctl show -p FragmentPath,
   ExecStart,ActiveState,UnitFileState`, ps, `busctl
   --system/--user`, `journalctl -b` for "Failed to start"/203/EXEC —
   and check every enabled unit's ExecStart path exists on the host
   rootfs.

Content-snap trap: the session wrapper symlinks
/snap/<content>/current/usr/lib/systemd/user into
$XDG_RUNTIME_DIR/systemd/user.control, which IS in the user manager's
unit path with HIGHER priority than /usr/lib — so pre-snap units left
in a content snap become visible to the host user manager (a
same-named base unit + base drop-in is the normal override shape, not
a duplicate). `grep -r` does not follow the base's ~48 user-unit
symlinks into the content snap — use the live FragmentPath or
`grep -R`.

Snapshot of that audit (still true 2026-11-15): system-bus provider
daemons are clean — no base unit or base D-Bus activation file
competes with accountsservice, avahi, bluez, bolt, fprintd, geoclue,
NetworkManager, udisks2, upower, provd or pipewire/wireplumber
(`snapd.seeded.service` existing in both base and snapd snap is
normal UC behaviour — /etc's snapd-supplied copy wins). Also by
design, NOT a leftover to fix: systemd-networkd + wpa_supplicant
stay ENABLED in the base alongside the network-manager snap —
networkd provides pre-NM boot networking, then NM starts and takes
over (a transient "DHCP lease lost" and a networkd sysctl
"conflicting with our setting" line are normal), and NM uses the
BASE's wpa_supplicant over D-Bus (the snap ships no supplicant
binary). Do not disable networkd as a "fix". The leftovers that were
found were all user-session side — the still-open ones are tracked
in gdm-graphical-session.md's route-through tranche audit.

## systemd path units: an existence condition loops — use PathChanged

A path unit whose oneshot service exits while the
PathExists/PathExistsGlob condition still holds is re-activated
IMMEDIATELY. With the service's start limit disabled (the a11y path
units' shape) this loops hard: 366 runs in 8s at CreateUser, each
spawning a transient logind session via su, until the path unit hit
its trigger limit, failed and degraded the boot; a stale marker file
also re-fired on every later boot. Use PathChanged= for the edge:

- PathChanged=<file> fires on the write that creates it (a stale file
  triggers nothing).
- PathChanged=<parent-dir> fires when an immediate child is created
  or removed, again for a later session's new child, and NOT for
  writes inside an existing child — the right shape for watching "a
  greeter home appeared under /run/gdm3/home".
- Caveat: PathChanged on an EXISTING file watches its inode; a
  temp+rename replacement may be missed depending on re-arm timing.
  Fine while the writer replaces in place (provd writes with
  O_TRUNC); re-check if a writer ever switches to rename-based atomic
  writes.

## /proc/<pid>/root is the namespace-accurate view

The host-side view of a snap's private paths (per-snap /tmp,
snap-bound runtime dirs) LIES or is empty — read and write THROUGH
the root of a live confined process instead:
`ls`/`cat`/`chown` /proc/<live-confined-pid>/root/<path>. Root can
operate through it (AppArmor may still refuse individual
operations), and bind mounts made on the host are visible to NEW
snap namespaces, since snap-confine rebinds from the host mount
tree. This also proves path-mapping gaps: a compiled-in path that is
ENOENT under /proc/<pid>/root/ while the file exists under
/snap/<provider>/current/... shows the library is looking outside
the namespace (see gdm-graphical-session.md's layout-bind section).

## Misc VM/device recipes

- Dynamic-uid session accounts (gdm-greeter, gnome-initial-setup)
  have /usr/sbin/nologin shells: use `su -s /bin/sh <user> -c '...'`
  (runuser -u fails on nologin).
- snapd's "database is locked" = state-lock contention: check
  `snap changes`, wait/abort, or reboot cleanly.
- Concurrent disposable test VMs collide on MAC/DHCP (~12-minute
  lease overlap cross-contaminates probes): before launching any VM,
  check the running qemu MACs
  (`ps aux | grep qemu-system | grep -v grep | grep -oE 'mac=[0-9a-f:]+'`),
  pick a MAC not in that list, and record it in the deliverable.
  Never assume a MAC is free because an earlier VM of yours used it —
  another concurrent agent may have taken it meanwhile.
- Disposable image copies: `df -h` first (~25G per copy), md5-verify
  the copy (the image may be re-baked mid-task — both md5s went
  stale once), and re-verify `snap list` after every boot: abrupt
  power kills lose sideloaded snap state.
- QEMU screendumps: use the PNG form (`screendump out.png -f png`);
  the PPM form is corrupt in qemu 10.2.1 (a long-standing upstream
  pixman stride bug, still unpatched in current distro packages) —
  widths not divisible by 4 come out diagonally sheared with
  scanline noise.
- dbus-monitor as the session user (systemd-run --user -M <uid>@.host,
  or su with the session bus env) — ~70k lines for a session's worth
  of traffic; grep for the Change signals and the writer labels.
