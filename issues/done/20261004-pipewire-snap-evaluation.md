# Evaluate switching pipewire to the store snap; fix broken pulse socket

## Impact / Priority

Medium. Real-user impact today: PulseAudio-client audio is silently
broken - `/run/user/1000/pulse` is a dangling symlink (points to
`snap.pipewire/pulse`, but no pipewire snap is installed and no pulse
socket exists anywhere), and pipewire-pulse (the PulseAudio compat
server) is not running. Any libpulse-based client (browsers, older
gstreamer sinks, pavucontrol-style tools) finds no audio server; only
native pipewire clients work. No complaints received yet only because
audio has barely been exercised on the test VM - pin the impact down by
playing audio through a libpulse client (e.g. paplay from the content
snap) before/after any change. The pipewire-0 native socket itself works
fine, so screen sharing/portal users are unaffected.

## Context (verified on the test VM, 2026-10-04 evening)

- No pipewire snap is installed. pipewire (1.6.2) + wireplumber run as
  per-user daemons from the gnome-desktop-content snap (apps
  `pipewire`/`wireplumber` in its snapcraft.yaml, labels
  snap.gnome-desktop-content.{pipewire,wireplumber}, enforce), one set
  for the user session and one for the gdm greeter.
- The content snap declares a `pipewire` interface SLOT (its
  snapcraft.yaml, `slots: pipewire: interface: pipewire`) - i.e. it
  plays the slot-provider role that the store pipewire snap normally
  plays. The gadget connects `ubuntu-desktop-session:pipewire` and
  `gnome-desktop-content:pipewire-client` plugs to
  `gnome-desktop-content:pipewire` (both "gadget" notes).
- core-desktop-session-wrapper.sh (source:
  core-base-desktop/static/usr/bin/core-desktop-session-wrapper.sh)
  symlinks /run/user/1000/pipewire-0 ->
  snap.gnome-desktop-content/pipewire-0 (works) and pulse ->
  snap.pipewire/pulse (DANGLING - see impact above; the wrapper was
  written assuming a pipewire snap would exist).
- The store `pipewire` snap is published by Canonical (verified) and
  bundles pipewire + wireplumber + pipewire-pulse. CAVEAT: latest/
  stable is 1.2.4-1ubuntu1 (rev 25, May 2025) while the desktop stack
  ships libpipewire 1.6.2 - a large version gap; wireplumber/server
  version coupling needs checking before any swap is trusted. There is
  no 26/stable channel.
- Stage 3C of the base-split plan
  (`20260922-split-core26-desktop-base-snap.md`) wants pipewire + the
  xdg-desktop-portal/xdg-document-portal/xdg-permission-store trio
  split into their own snap(s), with a NEW interface for direct
  pipewire-protocol access from the session snap (distinct from
  audio-playback/audio-record) and a resolution for the document
  portal's FUSE bind. Decide whether the existing `pipewire` interface
  (as the store snap provides it) is sufficient, or whether that new
  interface design is still required.

## Work (upower-style)

Follow the same pattern as the earlier upower snap fix (that note also
records its pattern and outcome).

1. In-VM feasibility test before any build change: `snap download
   pipewire`, inspect meta/snap.yaml (slots, apps, daemon-scope,
   whether its per-user services integrate with the session's systemd
   user manager or need units), then `snap install --dangerous` on the
   running VM, stop the content snap's pipewire/wireplumber user units,
   repoint the wrapper's symlinks live, and verify: pipewire-0 socket
   reachable from the confined session, a libpulse client gets a
   server (paplay a tone), gnome-shell/gsd audio paths clean, zero NEW
   AppArmor denials (pre-existing known denials: wireplumber ->
   /run/dbus/system_bus_socket and /run/snapd.socket - see the day's
   journal; decide whether the store snap's profile avoids these).
2. If green and the version gap is acceptable: switch the build -
   add pipewire to the GNOME model (channel 24/stable... check what
   the store actually serves; there is no 26 channel), drop the
   content snap's pipewire/wireplumber apps and its pipewire slot,
   update the gadget connections (session:pipewire ->
   pipewire:pipewire), and fix the wrapper symlinks
   (pipewire-0 -> snap.pipewire/pipewire-0, pulse -> snap.pipewire/
   pulse) in core-base-desktop/static/usr/bin/
   core-desktop-session-wrapper.sh. Rebuild session + content snaps
   and the image; fresh-boot verify (upower checklist: connections
   gadget-seeded, enforce labels, journal denials, functional client
   test, libpulse audio test).
3. If the version gap (1.2.4 vs 1.6.2) or per-user daemon integration
   is a blocker, fall back to: fix the pulse story inside the content
   snap (run pipewire-pulse as a third user daemon + correct the
   wrapper's pulse symlink to snap.gnome-desktop-content/pulse) and
   defer the snap split until the store snap is current. Land that
   fix either way - it is small and user-visible.
4. Independent cleanups noticed on the way (can be folded in or split
   out): the `name: null` -> explicit interface-name lint cleanup was
   done for ubuntu-desktop-session-snap (commit 93f594a);
   plasma-desktop-session's snapcraft.yaml likely still uses the null
   shorthand and will emit the same snapcraft 9 warnings.
   Also one-off triage item: a single CAP_NET_ADMIN probe at first
   activation from snap.udisks2.udisksd and snap.upower.upowerd (and
   the same from the pipewire daemons is likely).

## Gotchas learned (reusable; also recorded in the project documentation)

- `pkill -f <pattern>` matches your own shell's argv if the pattern
  string appears in the command line - it kills the tool's shell and
  (via process-group cleanup) unrelated background builds. Use a
  character-class trick (e.g. `pkill -f "pipewir[e]"`) or exclude the
  pattern from the command text.
- Long builds: start with `setsid nohup <build command> </dev/null >log
  2>&1 & disown` so tool-timeout process-group cleanup cannot kill
  them; poll the log instead of waiting.
- The image build (`build.sh`) refuses to assemble the image if the
  session snap's embedded git rev != the repo's HEAD - rebuild the
  session snap after ANY session-snap commit (hit twice today).
- core-base-desktop's build wipes the old core.snap early; a killed
  build leaves no output snap - just rerun, it is incremental.
- Snap swap verification checklist on the VM: `snap connections`
  (gadget-seeded entries present), `ps -o label=` (enforce),
  journalctl apparmor="DENIED" triage (distinguish known/one-off),
  functional client test, then a fresh-image boot for the real proof.

## Resolution (2026-10-04/05 evening)

Store pipewire snap: evaluated and DEFERRED (see findings below) - the
fallback (step 3) was implemented and verified end-to-end instead.

Store-swap verdict (step 1/2 findings):

- daemon-scope:user + socket activation DO work on this Core image
  (proved by installing the store snap: snapd generates
  /etc/systemd/user units + socket units, the greeter's manager ran the
  full set).
- Blocker: pipewire-pulse's snap audio-permission delegation
  (module-protocol-pulse snap-policy) is broken for ANY confined
  server: libapparmor's aa_getcon uses lsm_get_self_attr
  (seccomp-denied with EPERM by snapd's implicit deny; libapparmor only
  falls back to /proc reads on ENOSYS) -> every client gets
  PW_SANDBOX_ACCESS_NONE -> clients connect but see no sinks and
  playback streams time out. The store snap (1.2.4) and a hypothetical
  content-snap pipewire-pulse hit the same wall; fixed in our snapd
  instead (see below).
- Also against the swap: 1.2.4-vs-1.6.2 version gap (wireplumber 0.5.8
  vs 0.5.13) with no 26/stable channel; store wireplumber's portal
  D-Bus calls are denied (label mediation, plug set lacks portal
  access); and hot-installing user-scope daemons fails with running
  user managers (enable against the gdm-greeter manager fails; after
  killing it, snapd's service-control hits the dead session-agent
  socket). Seeded installs are unaffected.

Landed (fallback, all fresh-boot verified 2026-10-05, paplay tone
through the confined session gives Sink Input + rc=0, zero new denial
classes beyond the daemons' own non-fatal D-Bus connects):

- ubuntu-core-desktop-snapd 26-dev 8b9fcc6d6c: pulseaudio/audio-playback
  slot snippets gain the AppArmor attr self-read + ptrace(read) peer
  rules and the lsm_get_self_attr/lsm_set_self_attr seccomp entries that
  the delegation needs.
- ubuntu-core-desktop-snapd 26-dev 1037f1349e: the snapd snap now builds
  libseccomp 2.6.0 from its release tarball and stages it; core22's
  libseccomp 2.5.3 made snap-seccomp silently drop the new syscalls
  (unknown names are skipped without error), which is why the rules
  above had no effect until this.
- gnome-desktop-content main df1fcd2 + 3ad60e8: pipewire-pulse runs as
  a third daemon-scope:user app, providing audio-playback, audio-record
  and pulseaudio slots. The audio-record slot declaration is REQUIRED:
  snapctl is-connected --apparmor-label <label> audio-record first
  requires the calling snap to have a plug/slot with that name, else it
  hard-errors and every client is denied.
- core-base-desktop 26-dev 87d7c06: wrapper pulse symlink now points at
  snap.gnome-desktop-content/pulse (was dangling snap.pipewire/pulse)
  and the wrapper exports PULSE_SERVER into the session, D-Bus
  activation and systemd user environments (confined clients look for
  the socket in their own snap-private XDG_RUNTIME_DIR, which never
  matches the server's). The session environment broker normalizes the
  value to /run/user/<uid>/pulse/native for session apps, which
  resolves through the wrapper's host symlink.
- ubuntu-core-desktop main 9576c95: gadget connection
  ubuntu-desktop-session:audio-playback ->
  gnome-desktop-content:audio-playback. audio-record deliberately NOT
  connected (mic stays off; the delegation then reports clients as
  playback-only).

Impact pinned down per the note's own plan: before the fix, paplay from
the confined session failed with "Connection refused" (no server, no
socket anywhere); after, the same client plays (null sink on the
sound-card-less VM). Verified on a rebuilt image (rebuild + fresh boot,
not the live-patched state).

Item 4 cleanups NOT done here (still open): plasma-desktop-session's
name:null -> explicit interface lint cleanup; one-off CAP_NET_ADMIN
probe triage for udisks2/upower/pipewire daemons.
