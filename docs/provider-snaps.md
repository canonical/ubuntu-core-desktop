# System-service provider snaps (udisks2, upower, pipewire): architecture

Reusable facts about running system-bus/user-bus daemons as separate
provider snaps alongside the base/content/session snaps, instead of
baking them into the base or a content snap. Repos: udisks2-snap,
upower-snap (both upstream snapcore/*, branch snap-24, base core24),
and a locally built `pipewire` snap (the pipewire-snap repo, branch
`26`, base core26).

## System D-Bus-activated daemons (udisks2, upower)

Upstream provider snaps work on a core26 Core Desktop image essentially
unmodified. Both use `daemon: dbus` + `daemon-scope: system` +
`activates-on: [<raw dbus slot>]` — the daemon is NOT started at boot,
the system dbus-daemon activates it on first use. Full activation
chain:

1. snapd generates a D-Bus activation file into
   `/var/lib/snapd/dbus-1/system-services/<name>.service`
   (`Exec=snap run <snap>.<app>`, `SystemdService=snap.<snap>.<app>`,
   `User=root`) for any app with `activates-on` + `daemon: dbus`
   (wrappers/dbus.go `AddSnapDBusActivationFiles`).
2. dbus-daemon only scans that directory because the `snapd` snap ships
   `usr/share/dbus-1/system.d/snapd.system-services.conf` (pointing at
   `/var/lib/snapd/dbus-1/system-services/`) and copies it to
   `/etc/dbus-1/system.d` on Core — the dbus-daemon binary itself has
   no such path compiled in; the conf file is required.
3. The interface's slot policy supplies the D-Bus `<allow own>`/
   `<allow send_destination>` policy (written to
   `/etc/dbus-1/system.d/snap.<snap>.<app>.conf`), the daemon's
   AppArmor/seccomp policy, and udev rules (for udisks2, from the
   slot's `udev-file` attribute).
- Client wiring: the well-known interface slot (`udisks2`,
  `upower-observe`) works fine on an app snap. Gadget STATIC
  connections are needed for the client plug (session ->
  `udisks2:udisks2`), the daemon's own observation plugs
  (hardware-observe, mount-observe, block-devices), and
  `udisks2:polkit`. Deny-auto-connection on these interfaces does not
  block gadget static connections (see gdm-graphical-session.md for
  the general snap-id-independent gadget.yaml connection technique).
- polkit actions from snaps DO work on UC: snapd's polkit backend
  writes action files into `/usr/share/polkit-1/actions`, which is
  read-only on a stock base but exposed writable through the
  factory-writable overlay on the image
  (`/usr/share/factory/writable/system-data/usr/share/polkit-1/actions`).
  No base-side copy of the provider's action XML is needed. polkitd is
  dbus-activated and only reads actions at first start; seeding
  connections happen well before that, so no reload race was observed.
- The implicit `:udisks2` system slot (dangerous-grade,
  `ImplicitOnCoreDangerous`) still exists in this project's snapd fork
  but is no longer used — the session plug connects to the provider
  snap's own `udisks2:udisks2` slot via the gadget instead.
- `upower-observe`'s implicit CORE slot requires `/usr/libexec/upowerd`
  on the host (an executability gate) — the post-trim base has no
  upowerd, so `system:upower-observe` no longer resolves; the plug
  stays unconnected until the `upower` snap is in the model
  (`upower:upower` slot).
- Known snapd-fork fixes (upstreamable): the udisks2 interface's mount
  rule didn't cover `/dev/loop*` (fixed 93c6f2a3a0); the
  `upower-observe` connected-plug policy lacked KbdBacklight
  GetBrightness/GetMaxBrightness reads entirely (added 99d6fbc332).
- AppArmor D-Bus rule gotcha found while fixing the above: a trailing
  comma after `member=Get{,All}` terminates the dbus rule, and a
  following `peer=` then becomes a syntax error that makes
  `apparmor_parser` reject the WHOLE profile — aborting seeding for the
  entire snap and leaving first boot stuck in `snapd.seeded.service`
  until a manual restart (every graphical unit waits behind it). One
  wrong character in an interface policy can look like a dead device.
- Daemons that moved into a content snap transitively bring their
  Depends with them (e.g. `gvfs-daemons` hard-Depends udisks2,
  `gnome-control-center` Depends upower) — pruning by a stage-packages
  exclusion breaks the apt resolution; prune the binaries by PATH in
  override-prime instead.
- `gsd-media-keys` queries UPower but only has an app-level
  `upower-observe` plug if explicitly declared on that app — a
  snapcraft top-level `plugs:` list does NOT implicitly apply to apps
  that declare their own app-level plug lists. Missing it shows as
  AppArmor denials in BOTH directions (sender and receiver) for
  `org.freedesktop.DBus.Properties` traffic on UPower paths (the
  `upower-observe` slot policy only whitelists
  `interface=org.freedesktop.UPower*`, not Properties traffic).
- Both provider daemons log one harmless CAP_NET_ADMIN capability-probe
  denial at first activation (libudev/systemd init).
- Loop-device mount testing works end-to-end in QEMU (confined client
  via the provider's own `udisksctl`, polkit, confined daemon mount
  with AppArmor mount rules); mountpoints land in the host namespace at
  `/media/<user>/` and are visible to session processes. udisksd can't
  set up the loop device itself under confinement (no
  `/dev/loop-control`) — set up the loop as root first; udisksd's
  mount monitor still picks up the resulting mount.
- `snap.udisks2.udisksd` logs one AppArmor denial (operation=capable,
  capname=net_admin, comm=udisks-uevent-m) on activation — inherent to
  the udisks2 interface policy (daemon falls back), not specific to any
  particular udisks2 snap build.

Testing the GVfs client path (udisks2 volume monitor) from SSH:
- The GVfs *client* GIO modules (libgvfsdbus.so,
  libgioremote-volume-monitor.so) live in the content snap, not the
  base; an unconfined `gio mount` never uses the remote volume monitor.
  Even inside a confined `snap run --shell
  ubuntu-desktop-session.gnome-shell` with `GIO_MODULE_DIR` pointed at
  the content snap's gio modules, `gio mount -li` can print NOTHING —
  `gio mount -l` lists MOUNTS only, and an image with no mounted user
  media prints empty even when everything works.
- Reliable check: call the monitor's D-Bus API directly from a confined
  session profile:
  `gdbus call --session --dest org.gtk.vfs.UDisks2VolumeMonitor
  --object-path /org/gtk/Private/RemoteVolumeMonitor --method
  org.gtk.Private.RemoteVolumeMonitor.List`
  (note the object path is `/org/gtk/Private/RemoteVolumeMonitor`, NOT
  `/org/gtk/vfs/UDisks2VolumeMonitor` — that path exists but is empty
  and gives a confusing "UnknownMethod" instead of a clear error).
  Unconfined callers get AppArmor AccessDenied by design — the monitor
  profile rejects unconfined peers deliberately.
- Real user-visible confirmation ultimately needs a GUI (Files listing
  volumes) or mounted user-visible media.

## pipewire/pulseaudio snap (user-bus daemons)

The audio stack (pipewire-bin, pipewire-pulse, wireplumber-bin,
libspa-0.2-bluetooth, alsa-ucm-conf) is staged from the same resolute
archive packages the desktop content snap used to use, now in its own
`pipewire` snap, version-matched to the content snap's stack
(wireplumber 0.5.13) — do NOT swap in upstream canonical/pipewire-snap's
`main` branch build unmodified, it builds an OLDER pipewire/wireplumber
(1.2.x / 0.5.8) silently via a subprojects/wireplumber.wrap with no
visible wireplumber part, and resolute splits pipewire-pulse into its
own package that must be staged explicitly.

Apps: pipewire-bin (socket-activated: pipewire-0 + pipewire-0-manager),
pipewire-pulse (socket-activated: pulse/native), wireplumber-bin
(always-on). All three declare pipewire/audio-playback/audio-record/
pulseaudio app-level slots. Gadget connections wire
`session:pipewire -> pipewire:pipewire`,
`session:audio-playback -> pipewire:audio-playback` (audio-record
deliberately NOT connected, for record privacy — clients then report
as playback-only), plus the pipewire daemon's portal dbus plug and
wireplumber's PermissionStore dbus plug to the session snap's slots.
The content snap keeps only the pipewire/wireplumber LIBRARIES/configs/
client binaries for session apps to link against; no daemons or audio
interface plumbing live there anymore.

How snap user daemons and their sockets actually work on these images:
- `daemon-scope: user` works on snapd 2.76+: snapd generates
  `/etc/systemd/user/snap.<snap>.<app>.service`, enables via
  `/etc/systemd/user/default.target.wants/` (GLOBAL for every user
  including the gdm greeter's) and starts with each user manager.
  Socket-activated ones additionally get
  `/etc/systemd/user/sockets.target.wants/` units.
- Every strict-confined snap app (user daemon or client) runs with
  `XDG_RUNTIME_DIR=/run/user/<uid>/snap.<snap-instance-name>` — there is
  NO bridging mechanism to the real runtime dir. A server's socket thus
  lives in its own snap-private dir; a client's default lookup
  (`$XDG_RUNTIME_DIR/pulse/native` etc.) never finds a cross-snap socket
  by path. Bridge with an env override (`PULSE_SERVER`) or a symlink in
  the client's own private dir. AppArmor mediates the RESOLVED path —
  the pulseaudio/audio-playback connected-plug snippets grant
  `/run/user/<uid>/snap.<SLOT-snap>/pulse/**`, so wrapper symlink +
  env override resolve to a granted path. The session snap's wrapper
  symlinks `/run/user/<uid>/{pipewire-0,pulse}` to `snap.pipewire/*`
  and exports `PULSE_SERVER`; the session environment broker (see
  session-brokers.md) normalizes `PULSE_SERVER` to the host-visible
  path for session apps.
- Hot-installing a snap with user-scope daemons on a RUNNING desktop
  can fail several ways: service enablement against the gdm greeter's
  manager is rejected (its per-boot greeter user has a custom unit path
  and may not even exist in /etc/passwd, only as a logind session), and
  once that greeter session is dead, snapd's service-control can get
  connection-refused from its own stale session-agent socket. For a
  live sideload test: stop gdm, wait for ALL gdm sessions to disappear
  from `loginctl list-sessions` (terminate any lingering manager-early
  session), keep `user@<uid>` running, then install. Seeded (boot-time)
  installs are unaffected.
- Stale-manager trap: after a failed install attempt on a live manager,
  socket units stay loaded with old config — systemd logs "Unit
  configuration changed while unit was running, and no socket file
  descriptors are open. Unit not functional until restarted" and the
  sockets never reappear until `daemon-reload` + restart of the socket
  units. A fresh boot has no such state.

pipewire-pulse's per-snap-client audio permission delegation
(module-protocol-pulse/snap-policy.c):
1. `aa_getpeercon(client fd)` — gets the client's AppArmor label +
   confinement mode.
2. Non-snap label -> full access (PW_SANDBOX_ACCESS_ALL); a failed
   peer read is EPERM -> NONE, not full access.
3. `aa_getcon()` — the SERVER reads its own label. libapparmor 4.x/5.x
   probes `lsm_get_self_attr` ONCE; only ENOSYS/EOPNOTSUPP falls back
   to /proc attr reads — snapd's implicit seccomp deny is EPERM, so
   without an explicit seccomp allowance the probe "succeeds" and every
   `aa_getcon` fails forever -> PW_SANDBOX_ACCESS_NONE for everyone.
   Fixed via new AppArmor /proc self-read + ptrace(read) peer rules and
   `lsm_get_self_attr`/`lsm_set_self_attr` seccomp entries on the
   pulseaudio/audio-playback permanent slot snippets (snapd fork
   commits 8b9fcc6d6c + 1037f1349e).
4. If client snap != server snap: `snapctl2 is-connected
   --apparmor-label <client-label> pulseaudio` then `audio-record`.
   Exit 0 -> ALL; exit 1 -> continue (not-connected audio-record ->
   PLAYBACK, connected -> ALL); any ERROR -> NONE.
- `snapctl is-connected` semantics that bite here: the plug/slot NAME
  is resolved against the CALLING (server) snap only — if the server
  snap doesn't declare a plug/slot literally named `audio-record`
  (interface audio-record), the query HARD-ERRORS instead of answering
  "not connected", denying every client. The server snap serving the
  socket must declare BOTH `pulseaudio` and `audio-record` slots.
  `--apparmor-label`/`--pid` is only allowed for slots of interface
  type pulseaudio/audio-record/cups-control. Label mode checks whether
  an ACTIVE connection exists between the caller's plug/slot and the
  label-identified snap — not whether that snap has the interface
  connected to ANYTHING.

snap-seccomp silently drops unknown syscalls: it resolves template
syscall names through its linked libseccomp and SKIPS any entry it
can't resolve, with no error (explicit "ignore unknown syscalls" + a
FIXME in `cmd/snap-seccomp/main.go`). The `snapd` snap builds with
`build-base core22` (jammy libseccomp 2.5.3), so any syscall template
added after 2022 (`lsm_get_self_attr`, `lsm_set_self_attr`, ...) is
silently missing from generated filters — a profile LOOKS like it has
the rule but the compiled BPF doesn't. Diagnose by compiling the
template .src with/without the new lines and diffing the .bpf outputs
(identical = dropped). Fixed by building libseccomp 2.6.0 from its
release tarball as a snapcraft part in the snapd snap (remove
`libseccomp2` from the runtime part's stage-packages, or it stage-
conflicts). Two snapcraft gotchas hit along the way:
`$CRAFT_ARCH_TRIPLET_BUILD_FOR` is NOT expanded inside prime filesets
(use plain globs); incremental rebuilds keep files a removed
stage-package previously installed in a part's install dir
(`snapcraft clean <part>` needed after removing one).

Testing audio end-to-end on a sound-card-less VM: a QEMU launch
without `-audiodev` has no ALSA devices — wireplumber creates no sink,
and pipewire-pulse does NOT auto-create one. Recipe:
`pactl load-module module-null-sink` then `paplay <wav>` (generate wavs
on the host with Python's `wave` module). Client binaries (paplay/
pactl) only exist in the content snap, and the content snap itself
cannot connect to the pipewire snap's pulse socket (no audio-playback
plug) — run client checks from the SESSION snap instead (`snap run
--shell ubuntu-desktop-session.ubuntu-desktop-session -c ...`; its
`common` data dir is a snap-readable place for test files — $HOME
itself is not readable by most snaps). Verify playback really linked
via `pactl list sink-inputs` (application.name = paplay) — rc=0 alone
is NOT proof; paplay can return 0 after a "Stream error: Timeout".
pipewire-side view: `pw-cli ls Node/Link` or `pw-dump` from the
pipewire snap's own apps.
