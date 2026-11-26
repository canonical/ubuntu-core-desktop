# GDM / graphical session on Ubuntu Core Desktop

Relevant repos: `ubuntu-core-desktop`, `core-base-desktop`,
`ubuntu-core-desktop-snapd`, `ubuntu-desktop-session-snap`.

Confined GNOME session (the `build.sh --desktop gnome` image, see
build-tools.md): the `systemd-user-control` interface approach works
end-to-end now. `ubuntu-desktop-session-snap` uses
`base: core26-desktop`, plugs `systemd-user-control`, and
`scripts/run-session.sh` invokes plain `gnome-session --session=ubuntu`
(no `--builtin` — upstream gnome-session on Core 26 no longer accepts
that flag and aborts immediately). Before assuming a regression needs new
design work, check whether an already-written fix in the tree was
actually built and sideloaded onto the test VM — a stale store-published
snap can look like a design failure.

Open / unresolved issues (as of last investigation):

- FIXED (2026-10-04): gdk-pixbuf SVG loading failures traced to the
  gdk-pixbuf 2.44 (glycin-based) stack, not a `loaders.cache` ordering
  issue — see the "gdk-pixbuf/mime-database SVG loading" section below
  for the actual root causes and fixes.
- `gnome-session` can fail to start if the systemd unit template
  `org.gnome.Shell@.service` is missing/deleted by a build hook — check
  build hooks in the base/desktop-session snaps aren't stripping required
  systemd user units.
- FIXED: the confined session used to lose confinement partway through
  startup (gnome-session delegates to `systemd --user`, which ran
  unconfined, so gnome-shell and the GNOME Settings Daemon units came up
  unconfined too, causing most post-login AppArmor denials). Fix: static
  systemd drop-ins setting
  `AppArmorProfile=snap.ubuntu-desktop-session.ubuntu-desktop-session` on
  the specific instances `gnome-session-manager@ubuntu.service` and
  `org.gnome.Shell@ubuntu.service` (plus every
  `org.gnome.SettingsDaemon.*.service` unit), shipped in
  `core-base-desktop`'s `static/usr/lib/systemd/user/<unit>.d/` overlay,
  with companion AppArmor policy in `ubuntu-core-desktop-snapd`'s
  `interfaces/builtin/desktop_launch.go`,
  `interfaces/builtin/systemd_user_control.go`, and
  `interfaces/builtin/login_session_observe.go`.
  Reusable gotchas for future confinement work in this area:
  - Scope systemd user-unit drop-ins to the specific instance
    (`<unit>@ubuntu.service.d/...`), never the bare template
    (`<unit>@.service.d/...`) — the template also matches GDM's own
    greeter session (`@gdm`) and confining it breaks the greeter login.
  - A unit confined this way (via `AppArmorProfile=` on top of a
    previously-unconfined systemd-managed process) gets a *stacked*
    label like
    `snap.ubuntu-desktop-session.ubuntu-desktop-session//&unconfined`,
    not the plain snap label. AppArmor rules matching "my own snap" as
    a D-Bus/IPC peer must use the `**` AARE wildcard, not `*` — plain
    `*` doesn't cross the `/` implied by the `//&unconfined` suffix, so
    same-snap peer rules silently fail to match.
  - When confining a previously-unconfined unit tree for the first
    time, put the target profile(s) into complain mode
    (`aa-complain <profile>`, or `apparmor_parser -r --complain <profile-file>`)
    *before* testing, run a real session for a few minutes exercising
    actual app launches, then collect every `apparmor="ALLOWED"` line
    (complain mode logs would-be-denials as ALLOWED) grouped by
    (profile, operation, class, path/D-Bus member) to get the complete
    gap list in one pass — fixing enforce-mode denials one at a time is
    much slower since a single missing rule (e.g. a systemd-notify
    readiness socket) can hang a unit indefinitely and hide everything
    downstream.
  - Relabeling a single already-running unit live (`systemctl --user
    restart <unit>` after adding a drop-in) while the rest of the
    session still runs with mismatched labels is not a valid test and
    can crash the live session. Install all drop-ins for every unit
    being confined together, then trigger a fresh session start
    (reboot or full logout+login) so every unit is born with the label.
  - Reproducing a D-Bus-activation denial from an unconfined SSH shell
    (e.g. `gio launch`) is not a valid test either — test from within a
    real, live-login confined session.
- FIXED: every GDM login stalled ~25-27s on a blank screen before the
  GNOME session appeared, caused by a D-Bus-activation-mediated
  ordering deadlock between gnome-shell and xdg-desktop-portal.service
  (+ its GTK/GNOME backend unit): both portal units carry
  `After=graphical-session.target`, but that target only becomes active
  once gnome-shell itself is ready — and gnome-shell's own startup makes
  a *synchronous* D-Bus call into the portal first. This ordering cycle
  is latent in the unmodified upstream unit files on any distro; it
  only actually deadlocks once gnome-shell runs genuinely AppArmor-
  confined via real `snap run`/snap-confine (not just a stacked/no-op
  `AppArmorProfile=` — see the stacked-label gotcha above), because
  glib/gio's sandbox detection (`glib/gportalsupport.c`, keyed off the
  `SNAP*` env vars and a snap-namespaced `XDG_RUNTIME_DIR`) only routes
  early-startup settings/etc. lookups through the portal's D-Bus
  interface when it detects it's running sandboxed — unconfined,
  glib reads GSettings/dconf directly and never calls the portal at
  startup, so the cycle is never exercised. Fixed by dropping
  `After=graphical-session.target` from both portal unit files
  (core-base-desktop,
  `static/usr/lib/systemd/user/xdg-desktop-portal{,-gtk}.service`,
  commit 034d42a on branch `26`) — a **drop-in** resetting
  `After=` did not reliably take effect across fresh `systemd --user`
  instances on this systemd version (259.5-0ubuntu3.4) for this unit,
  even though every static/`systemctl --user show` check said it had
  applied; only a full replacement unit file at the same path worked
  and was verified to fix the real login hang end-to-end. If a
  drop-in's empty-then-reassign reset for a multi-value directive
  (`After=`/`Before=`/`Wants=`/etc.) doesn't stick despite the drop-in
  otherwise being confirmed parsed/applied, switch to a full unit file
  replacement rather than continuing to debug the drop-in mechanism.
  Forward-looking: expect this same class of issue (glib/gio process
  silently starts making portal calls, and hits the portal's latent
  ordering cycle) to recur for any other glib/gio-using session
  component as more of it moves to real snap confinement — if a
  newly-confined component starts hanging or behaving differently only
  after confinement, check first whether it's now taking a
  portal-mediated codepath by diffing `/proc/<pid>/environ` for
  `SNAP*`/`XDG_RUNTIME_DIR` before/after, rather than assuming an
  AppArmor denial.
  Still open, likely-independent smaller gaps (not fixed by the above):
  - `run-session.sh`'s `$HOME/.hidden` step is resolved/moot as of
    2026-09-18: the script only appends to it (`>>`), not `mknod`, and
    it already exists from a prior run with no denial in current
    journals.
  - Nautilus/Files opens correctly now (nautilus-service is confined),
    but a related, distinct set of AppArmor denials to unconfined
    gvfs-volume-monitor/Tracker/D-Bus-bus-itself peers makes it take
    ~60-90s to open and silently breaks removable-media detection,
    search indexing, and network-location mounting — see
    `20260918-nautilus-gvfs-tracker-portal-denials-slow-degraded-file-manager.md`.
  - `bwrap`/`userns_create` denied ("failed to find unprivileged_userns
    profile") — see `20260918-bwrap-userns-create-denied.md`
    (caller not yet identified, so real impact unknown).
  - `ubuntu-desktop-session:wayland-client` (a plug added in a
    separate, in-flight `ubuntu-desktop-session-snap` change) has no
    persistent auto-connect mechanism yet — only ever connected
    manually on one long-lived test VM. Needs a gadget.yaml static
    connection added to `build.sh`'s `gnome_gadget_connections`
    function (see below) in the meantime.
  - Separately, App-Center-installed third-party snaps (e.g. Firefox)
    have no `wayland`/`x11` auto-connect mechanism at all on this image
    (no `ImplicitOnClassic` shortcut like classic Ubuntu Desktop) —
    tracked in
    `20260915-app-center-installed-snaps-need-desktop-interface-connections.md`.

Stage 2.2 update (2026-09-22): gnome-shell and the 16 gsd-*
(GNOME Settings Daemon) units are now confined by routing them through
`snap run` per-app instead of the `AppArmorProfile=` drop-in described
above (that mechanism is still correct/in-place for
`gnome-session-manager@ubuntu` and `org.gnome.Shell@ubuntu` at the
top level, but the underlying units it spawns are now snap-run-routed).
Mechanism and gotchas for any further unit in this style:
- A systemd --user unit whose binary only lives in the base snap is
  converted by a drop-in that clears and resets `ExecStart=` to
  `/snap/bin/<snap>.<app> [args]` (routes through `snap run`, giving a
  clean `snap.<snap>.<app> (enforce)` label with no stacked
  `//&unconfined` suffix) — and the pre-existing `AppArmorProfile=`
  drop-in line for that unit must be REMOVED entirely (not left empty;
  the base's own `/usr/lib` drop-in still wins over an empty override
  in `/etc`). Verify the label via `/proc/<pid>/attr/current`, not
  `systemctl --user` over SSH (that connects to a different `--user`
  manager than the graphical session's and shows stale/empty state).
- GDM's greeter runs its own full gnome-session as user `gdm-greeter`
  (gid `gdm`), instantiating the same non-templated unit names (the
  gsd-* units) as the real session. Add `[Unit] ConditionGroup=!gdm` to
  non-templated units being converted so they don't also fire for the
  greeter (which keeps its own unconfined gsd-*, fine since it's a
  lower-trust session). Templated units (`org.gnome.Shell@ubuntu`,
  `gnome-session-manager@ubuntu`) are already scoped away from the
  greeter (which uses `@gdm`) via their instance name — no
  `ConditionGroup` needed for those.
- gnome-shell itself must bind `/tmp/.X11-unix/X<display>` for
  Xwayland, but the `x11`/`wayland` interfaces only grant bind to the
  interface's SLOT OWNER. Once gnome-shell is routed through `snap run`
  as its own app it stops inheriting the main app's slots and aborts
  "Failed to bind X11 socket" — fix by adding `slots: [wayland, x11]`
  to the gnome-shell app itself in snapcraft.yaml (KDE's kwin does the
  same, via `x11-server` — same interface, different name).
- AppArmor brace-alternation gotcha: adding a D-Bus member to an
  existing rule of the form `Prefix{A,B,C}` only works if the new
  member's name does NOT already start with `Prefix` — e.g. adding
  `GetSessionByPID` inside a `Get{Seat,Session,User}` brace produces
  `GetGetSessionByPID` (wrong, silently never matches, though
  `apparmor_parser` accepts it without error). A member whose name
  already contains the shared prefix needs its own separate `dbus
  (send)` rule. Always confirm a changed rule actually clears the
  denial on a clean boot, not just that it parses.
- A snapd build missing the `fix-tmpdir-permissions-bug` commit
  (`ba1b318139`) breaks `snap run` for EVERY app on the image at once
  (`"/tmp/snap-private-tmp/snap.<name> has unexpected ownership /
  permissions"`, mode 0700 vs 01777) — this can present as
  `snapd.seeded.service` hanging for minutes because one snap's
  AppArmor profile fails to load, which blocks seeding entirely. Build
  snapd from `26@ba1b318139` or later if this symptom appears.
- Fast dev/verify loop for this style of unit change, no image
  rebuild needed: write the drop-in to `/etc/systemd/user/<unit>.d/`
  and bind-mount it over the base's own drop-in,
  `systemctl --user daemon-reload`, then `sudo systemctl restart gdm`
  for a fresh session (these units have `RefuseManualStart=`, so you
  can't `systemctl --user restart` them directly). The committed form
  lives in `core-base-desktop/static/usr/lib/systemd/user/<unit>.d/`
  and only reaches the image after a full image build (~10-15 min) —
  use the fast SSH loop to iterate, do one full rebuild to confirm.
- First boot of a freshly rebuilt image has a ~4 min cloud-init
  (cloud-final) delay before GDM starts (`GDM` is
  `After=cloud-config.service`) — a black screen during that window is
  normal, not a failure.
- The image is built WITHOUT `--autologin` by default; toggling
  autologin keys on the VM afterwards (crudini/sed) does not work
  because GDM's autologin path needs the build-time gnome-session shim
  — use manual login, or rebuild with `--autologin`.
- Route-through tranche audit (2026-11-15; method in
  diagnostics-methodology.md's pre-snap-leftover section): the
  found-and-fixed leftovers were all user-session side (gcr
  SystemPrompter's dead Exec path; gnome-desktop-runtime shipping the
  pre-snap pipewire/wireplumber/filter-chain user units, exposed to
  the user manager via the content snap's user-unit symlink — both
  fixed). Still open, each a different class:
  * `localsearch-3.service` (content snap, auto-started at login)
    fails 203/EXEC on every boot: ExecStart=/usr/libexec/localsearch-3
    doesn't exist on the host rootfs (same for
    localsearch-control/writeback-3). A bare
    ExecStart=/snap/bin/ubuntu-desktop-session.localsearch-3 starts it
    but then hits AppArmor denials (user systemd manager, ~/.hidden,
    snap dirs) and localsearch-extractor-3 is still missing — it needs
    the full route-through/gap pass
    (`20261104-localsearch-autostart-vendored-but-trimmed.md`).
  * `glib-pacrunner.service` is routed to the session snap correctly,
    but the snap's glib-pacrunner dies dlopening
    libpxbackend-1.0.so — the known libproxy-subdirectory-RUNPATH
    class from kde-internals.md's session-namespace note. Proxy PAC
    support is broken; low impact.
  * `gnome-keyring-daemon.service`/`.socket` (content snap + a base
    copy) are deliberately disabled/inactive — the running keyring is
    D-Bus-activated from the session snap, and starting the unit would
    spawn a second, UNCONFINED /usr/bin/gnome-keyring-daemon
    (`20260927-gnome-keyring-secret-service-activation.md`). Don't
    "fix" the disabled units.
  * Duplicate session activation files for org.gnome.OnlineAccounts
    and org.gnome.Identity exist in BOTH /usr/share/dbus-1/services
    and /var/lib/snapd/dbus-1/services — both entries run the same
    session snap app, so this is harmless, not a conflict to fix.

Fast dev-iteration tip for `core-base-desktop`/`ubuntu-core-desktop-snapd`
changes (saves ~10+ minutes per test cycle): `core-base-desktop`'s own
build (snapcraft+chisel+LXD) is slow (~10-15 min/rebuild) —
don't iterate by repeatedly editing and rebuilding it. Instead:
- `build.sh --desktop gnome` (or `kde`) already `unsquashfs`'s
  the `--base-snap` input (`core-base-desktop/core.snap`) into
  `build/squashfs-root/`, lets you add/edit files there, then
  `mksquashfs`'s it back into the image's custom core — fast (no
  chisel/apt rebuild), the right place to test static files (e.g.
  systemd drop-ins) before committing them properly to
  `core-base-desktop`.
- `ubuntu-core-desktop-snapd`'s `snapd.snap` (passed as `--snapd-snap`)
  is a plain Go build, also fast to rebuild independently — this is
  where AppArmor interface-template changes (`interfaces/builtin/*.go`)
  live.
- Only do the one full `core-base-desktop` rebuild once a fix is
  verified working via the fast loop, to confirm the real production
  packaging path also works.

GDM session-selection facts (this GDM build, may not generalize to other
GDM versions):

- There is no `AutomaticLoginSession`/`DefaultSession` key in
  `/usr/share/gdm/gdm.schemas`. GDM autologin (`gdm-autologin`)
  unconditionally execs the literal `gnome-session` binary (found via
  `PATH`) — it does NOT consult `/var/lib/AccountsService/users/<user>`
  `Session=` or any `.desktop` file. Only a real (password) greeter login
  honours `AccountsService` `Session=<name>` matched against
  `/usr/share/wayland-sessions/<name>.desktop`. So autologin alone cannot
  select the confined session — see the shim technique below for
  verifying the confined path without real keyboard/GUI input.
- The GDM greeter itself also launches via the same `gnome-session`
  binary path, so any trick that intercepts that binary must be
  conditional on the logged-in user, or it breaks the greeter too
  (observed: "GdmLocalDisplayFactory: maximum number of display failures
  reached. Giving up.").
- The wrapper script `core-desktop-session-wrapper.sh` may live in
  different locations across builds (seen at `/usr/bin/` on one image,
  `/usr/libexec/` on an older one). Always `which`/`find` it fresh rather
  than hard-coding the path.
- Still open (confirmed 2026-09-18): the manual `busctl ...
  SetSession`/`SetXSession` workaround does not persist across a reboot
  (`/var/lib/AccountsService/users/<user>` reverts to `Session=` empty),
  and this greeter build has no session-chooser gear icon at all -- so
  there is currently no real end-user path to the confined session. See
  `20260918-accountsservice-default-session-ux-gap.md`.

Reusable technique: verifying a confined session end-to-end without VNC
or any keyboard/GUI input (all via SSH + journalctl):

1. `/` on the running VM is a read-only squashfs, so you can't edit
   `/usr/bin/gnome-session` directly. Instead, stash the real binary and
   bind-mount a shim script over it — fully revertible, no image rebuild:

   ```
   sudo cp /usr/bin/gnome-session /tmp/gnome-session.real
   cat > /tmp/gnome-session-shim <<'SHIM'
   #!/bin/sh
   if [ "$(id -un)" = "<user>" ]; then
     exec /usr/bin/core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME
   else
     exec /tmp/gnome-session.real "$@"
   fi
   SHIM
   chmod +x /tmp/gnome-session-shim
   sudo mount --bind /tmp/gnome-session-shim /usr/bin/gnome-session
   ```

   Revert with `sudo umount /usr/bin/gnome-session`. The username check is
   required (see greeter note above) — an unconditional shim breaks the
   greeter's own session launch too.
2. Enable autologin for the target user in `/etc/writable/gdm3/custom.conf`
   under `[daemon]`:

   ```
   AutomaticLoginEnable = true
   AutomaticLogin = <user>
   ```

   Both keys must land under the `[daemon]` section header — naive
   `sed`/`tee -a` appends can silently land the line under a later
   section (e.g. `[debug]`) with no effect and no error. Verify with
   `grep -A3 '\[daemon\]' custom.conf` after editing.
3. `sudo systemctl restart gdm`, wait ~15s, then check
   `ls -la /run/user/<uid>/wayland-0` (should symlink to
   `snap.ubuntu-desktop-session/wayland-0` when the confined session is
   really up) and start/inspect any snap-provided systemd --user unit
   directly, e.g.

   ```
   systemctl --user -M <user>@ start snap.ubuntu-desktop-session.gnome-terminal-server
   systemctl --user -M <user>@ is-active snap.ubuntu-desktop-session.gnome-terminal-server
   ```

   `systemctl ... -M <user>@` lets you inspect/drive another user's
   systemd --user manager over SSH without ever needing a graphical
   login.
4. Always revert both the shim (umount) and the custom.conf autologin
   lines afterwards — this is a diagnostic-only technique, not meant to
   be left enabled.

Do not do the above by hand anymore — `tools/confined-autologin-test.sh`
in the ubuntu-core-desktop repo wraps steps 1-4 into `enable <user>`
(applies the shim and autologin together, refuses to leave autologin
enabled if the shim didn't land), `verify` (checks shim mounted +
autologin enabled + wayland-0 socket really points at a confined snap
session) and `disable` (clean, verified revert). It's a runtime test
helper only (copy to the VM, run there with sudo), not baked into any
image. Doing the shim/autologin steps manually risks forgetting the
shim and silently getting an unconfined "confined session" test result.

`snap connect <plug-snap>:<plug>` (single-arg form) does NOT reliably
resolve to a slot provided by the SAME snap as the plug — it can search
for a slot on some other/system snap first and fail outright (e.g.
"error: snap \"snapd\" has no \"wayland\" interface slots") rather than
connecting the obvious same-snap candidate. Any same-snap plug-to-slot
connection needs the explicit two-sided form:
`snap connect <snap>:<plug> <snap>:<slot>`. Verify with
`snap connections <snap>` afterwards that the specific plug actually
shows a slot — the `snap connect` command's/wrapping service's exit
code being 0 is not sufficient proof the connection was made.

`ensure-desktop-session-connections.service` (the snap-id-independent
boot-time `snap connect` workaround loop, see below) has no ordering
dependency on `gdm.service` and cannot block GDM startup by design. It
can take ~70s+ to finish on a fresh boot (bounded retries: 5 attempts x
3s per entry, times ~30 entries, plus fast-failing entries for snaps
not yet installed like Firefox) — this is normal/expected, not a hang;
don't disable it as a "fix" for slowness.

FIXED: `ubuntu_init` (the Flutter first-boot wizard) used to crash with
"Unknown DConf source: 'line'" when launched with the inherited
`DCONF_PROFILE=gnome-initial-setup` environment (that profile's
`file-db:...` source line isn't supported by the Flutter `gsettings`
package, only `user-db`/`system-db` are). Fixed for the `ubuntu_init`
invocation in `core-base-desktop`'s
`hooks/002.4-configure-system-setup-tool.chroot` (the profile is left
intact for GNOME itself, which needs it). CORRECTION (2026-11-21):
DCONF_PROFILE must be UNSET for that exec, never cleared to an EMPTY
string — the Flutter `gsettings` Dart client treats an empty value as
a profile NAME, finds none and throws "No DConf source to write to"
(two unhandled exceptions at UI startup); use `env -u DCONF_PROFILE`
(core-base 4fad222). That Dart client also READS the user db FILE
directly while its writes go over the session bus to dconf-service —
with DCONF_PROFILE unset it read `$HOME/.config/dconf/user` but wrote
the snap-common database, so the unit's XDG_CONFIG_HOME must point at
the same snap-common redirect the session service (and provd's own
unit) uses (core-base 378595c), or its reads and writes disagree.

Gadget static interface connections normally resolve purely by
snap-id, which a locally-built snap installed with `snap install
--dangerous` never has (a gadget.yaml connection keyed to the real
store snap-id silently never applies — the plug shows unconnected,
`snap connections <name>` shows `-`, with no error anywhere). Current
fix: `build.sh`'s `gnome_gadget_connections`/`kde_gadget_connections`
functions bake `connections:` entries directly into the unsquashed
gadget's `gadget.yaml` at build time, using snap-*name* endpoints
(e.g. `system:<plug>` for implicit system slots, or
`ubuntu-desktop-session:<plug>` / `plasma-desktop-session:<plug>` for
session-to-session plugs) instead of snap-ids, which works regardless
of whether the snap has a real store snap-id. A few store-asserted
providers (e.g. network-manager, bluez) are still referenced by their
real snap-id since those are always installed from the store. This
replaced an older runtime systemd-oneshot `snap connect` workaround.

Useful debugging methods:

- SSH into the booted QEMU VM — the *first* boot installs and reboots;
  examine the *second* boot.
- Cross-reference GNOME/gdm/gdk-pixbuf/base-files upstream source via
  `apt-get source` (or direct download) against what's shipped in the
  image.
- `journalctl`, `loginctl`, `aa-status` for session/AppArmor diagnosis.
- Shell directly into the LXD snapcraft build container to inspect build
  state without a full rebuild.
- VNC (typically no password) is a fast way to watch a boot graphically
  instead of relying only on serial console/SSH; GDM typically appears
  ~90s after boot start.

## gdk-pixbuf/mime-database SVG loading: root causes (fixed 2026-10-04)

A multi-bug chain broke the greeter login box AND the lock-screen
unlock box at once ("grey screen, clock, no password box") — both use
the same gnome-shell `LoginDialog`, so one underlying SVG-loading
failure killed both. All causes below are FIXED and landed; kept here
because the failure signature and diagnostic steps are reusable for
any future mime/pixbuf regression:

- gdk-pixbuf 2.44 (glycin-based) detects SVG via GIO content-type
  (shared-mime-info), NOT the legacy C magic sniffing — the C path
  cannot recognise SVGs starting with `<?xml` or plain `<svg`. If the
  mime DB is empty/broken, every SVG load fails with "Couldn't
  recognize the image file format", `St.TextureCache` returns null,
  gnome-shell's `loginDialog.js` `_updateLogoTexture` does
  `add_child(null)` -> JS ERROR "Argument child may not be null" ->
  the `LoginDialog` constructor aborts -> NO login box and NO unlock
  box. Quick probe: `Gio.content_type_guess("foo.svg", null)` must
  return `image/svg+xml`.
- The session snap's `gdk-pixbuf-env.sh` builds the mime DB into
  `SNAP_USER_COMMON/desktop-content-data-<rev>/share/mime` from a
  staging dir with a `packages` symlink to the content snap. A `mkdir
  -p "$mime_stage/packages"` before the `ln -s` can nest the symlink
  one level too deep (`packages/packages`), so
  `update-mime-database` builds an EMPTY DB (globs2 ~92 bytes, no
  rules) and everything downgrades to content-sniffing. Verify with
  `grep -c svg <dir>/share/mime/globs2`.
- glycin config discovery reads
  `<XDG_DATA_DIRS>/glycin-loaders/2+/conf.d/*.conf` (first match per
  mime wins); loader `Exec` paths are absolute and must resolve in the
  target process namespace. `RUST_LOG=trace` shows which conf files
  libglycin loaded. When reproducing inside a snap namespace, source
  the process's full env from `/proc/<pid>/environ` first — a reduced
  env gives a misleading "No image loaders are configured".
- GDM (50.x) resolves the autologin session via session FILES
  (`ubuntu.desktop` -> `gnome.desktop` -> fallback), searching
  `/usr/share/gdm/greeter/wayland-sessions/` among other dirs — if the
  real `ubuntu.desktop` is missing/unreadable, autologin silently
  falls back to `gnome-greeter.desktop` and becomes a GREETER session
  running under the logged-in user. The greeter's GDM D-Bus API then
  denies everything ("Can only be called before user is logged in"),
  `loginDialog`'s `_ensureGreeterProxy`/`get_greeter_sync` throws, and
  the login box never shows. GDM debug (`[debug] Enable=true` in
  `/etc/writable/gdm3/custom.conf`) shows the resolution flow in
  "getting session command for file '...'" log lines.
- Lock-screen reauth (confined shell -> GDM -> PAM -> logind) needs,
  in the gdm AppArmor profile: `OpenReauthenticationChannel` receive
  from the shell label, logind `UnlockSession`/
  `ActivateSessionOnSeat` send, `/etc/shadow` and
  `/var/lib/extrausers/shadow` reads, and `cgroup.events` reads in
  user session scopes. If `OpenReauthenticationChannel` is denied, the
  unlock box instantly shows an auth error before any typing ("Failed
  to open reauthentication channel" in the journal).
- `apparmor_parser -r <profile>` replaces the kernel profile and
  applies to ALREADY-RUNNING processes immediately — useful for fixing
  a profile without restarting GDM and killing the session.
- "A graphical session is already running!" (gnome-session-init-worker
  aborts, GDM falls back to the greeter) means
  `graphical-session-pre.target` was still active in the user's
  systemd `--user` manager (e.g. leftover from a greeter that ran
  under the same user) — clear with `systemctl stop user@<uid>.service`
  before restarting gdm.
- The stale-built-snap trap bites especially hard here: three separate
  "mysterious" greeter/lock-screen failures on one day all traced back
  to the SAME stale `core.snap` (built before the fixing commits
  landed in `core-base-desktop`'s tree). Check `ls -la core.snap` vs.
  `git log` dates before diagnosing a "new" regression — rebuild
  before chasing a design explanation.

## Desktop icon double-click silently doing nothing (fixed, two stacked bugs)

Double-clicking "Home"/any folder icon on the desktop did nothing — no
window, no error, no spinner. Two independent, now-fixed causes:

1. Missing `mimeinfo.cache` in the gnome-desktop-runtime content snap:
   `gio` resolves default apps from
   `/usr/share/applications/mimeinfo.cache`, normally generated by
   dpkg triggers — snap staging never runs triggers, so the cache
   never existed and `gio` found no default handler for ANY mime type.
   Fix: run `update-desktop-database` in the content snap's
   `override-prime`.
2. The GDM greeter's data dir (`$SNAP/gnome/usr/share/gdm/greeter`)
   was FIRST in the session app's `XDG_DATA_DIRS`. The greeter's own
   `mimeapps.list` maps `x-scheme-handler/file` (and most other common
   schemes) to a dummy `Exec=true %U` handler (a GDM isolation
   measure). `launch_default_for_uri()` checks the URI SCHEME handler
   BEFORE content type, so every `file://` launch silently executed
   `/usr/bin/true` and returned success. Fix: drop the greeter dir
   from the session app's `XDG_DATA_DIRS`; GDM sets the greeter's own
   env for the greeter session, so the greeter layout itself is
   untouched.

Diagnostic signature worth remembering for any similar "nothing
happens" launch bug: `Gio.AppInfo.get_default_for_type()` resolving
fine while `launch_default_for_uri()` silently no-ops is the tell that
a URI SCHEME handler (not content-type resolution) is intercepting the
launch — check `mimeapps.list` entries under every `XDG_DATA_DIRS`
component, in order, for `x-scheme-handler/<scheme>`. Keep the
diagnostic signature, drop the specifics once this recurs elsewhere.

Live-fix toolkit for a read-only Ubuntu Core rootfs (all reverted on
reboot, see also diagnostics-methodology.md's live-patching section):
bind-mount a corrected script over a snap file; bind-mount a tmpfs dir
containing a symlink over an empty dir (e.g. a missing
`wayland-sessions` entry); overlay `/etc/apparmor.d` then
`apparmor_parser -r`. A session snap's per-user content-data setup can
be gated by a content-stamp so a manually-fixed common dir (e.g. the
mime DB above) survives reboots until the content snap itself changes
— check for that gate before assuming a live fix won't stick.

## First-boot wizard (GNOME `ubuntu-desktop-init`) launch chain

How the wizard is supposed to start, and the gates needed wiring (all
below landed in `build.sh` + `core-base-desktop` static/hooks/002.4):

1. GDM runs initial setup when NO user accounts exist and
   `InitialSetupEnable` is true (default in gnome-desktop-runtime's
   `gdm.schemas`) — `build.sh` only sets `InitialSetupEnable=false`
   when `--user` is given (cloud-init creates that account before GDM
   starts).
2. GDM prefers a pre-existing static `gnome-initial-setup` account if
   one exists, but such a session always fails on this image (GDM
   hands it the greeter's `XDG_RUNTIME_DIR`, so its session bus never
   starts). GDM then falls back to creating a TRANSIENT account via
   AccountsService/adduser (extrausers db) in the baked
   `gnome-initial-setup` group (gid 996, primary), which the polkit
   rules check by group membership (`isInGroup('gnome-initial-setup')`)
   — so the static user is deliberately NOT baked (removed from
   passwd/shadow, group kept), and GDM creates the transient user on
   the FIRST attempt. The account may be named
   `gnome-initial-setup` or `gnome-initial-setup-<n>` — shims/
   whitelists must accept both forms.
3. The session is `gnome-session --session gnome-initial-setup`
   (Kiosk), from gnome-desktop-runtime's greeter wayland-sessions
   `.desktop`.
4. `gnome-session@gnome-initial-setup.target` requires
   `gnome-initial-setup.service`, whose `ExecStart` must run
   `/usr/libexec/launch-desktop-provision-init` (hook 002.4 rewires
   this away from the stock Debian wrapper, which hook 002.4 also
   removes).
5. `launch-desktop-provision-init` starts `/usr/libexec/provd`, waits
   for `/run/gnome-initial-setup/desktop-provision/init.socket`, then
   execs `/snap/ubuntu-desktop-init/current/bin/ubuntu_init` directly
   (raw, UNCONFINED, not via `snap run`; `DCONF_PROFILE` is UNSET —
   `env -u`, NOT cleared to an empty string, see the FIXED note above —
   for this exec specifically because the Flutter gsettings package
   can't parse the `file-db` source; left intact for GNOME itself).
   `provd` is configured by
   `/usr/share/desktop-provision/whitelabel.yaml`.

Gates that had to be fixed for this chain to work end-to-end (now
landed, kept as a checklist for the KDE equivalent or any future
wizard-session work):
- The `gnome-session` shim that reroutes non-gdm accounts to the
  confined session wrapper must exempt
  `gnome-initial-setup|gnome-initial-setup-[0-9]*` (like `gdm-greeter`)
  — otherwise the wizard gets the full confined session instead of the
  unconfined kiosk one.
- `gnome-content-launch`'s account whitelist ("refusing content
  runtime for non-GDM account") must allow `gnome-initial-setup*`
  accounts.
- The gdm AppArmor profile needs an exec rule (Ux, unconfined
  transition) for the wizard's raw-exec of
  `/snap/gnome-desktop-runtime/<rev>/usr/bin/gnome-session` — the
  greeter never raw-execs this path (its session dispatches through
  `snap run` first).
- `provd` needs `/usr/share/i18n/SUPPORTED` at runtime for locale
  validation — a hook that `rm -rf`s the whole i18n tree after
  compiling locales must keep `SUPPORTED` and only drop
  charmaps/locales.
- `systemd-localed` writes `/etc/locale.conf`/`/etc/vconsole.conf` via
  temp-file+rename in the file's own (read-only) `/etc` directory — the
  classic Ubuntu Core writable-etc gotcha. Fix via the
  `SYSTEMD_ETC_LOCALE_CONF`/`SYSTEMD_ETC_VCONSOLE_CONF` env overrides
  in a `systemd-localed.service` drop-in, pointing both at
  `/etc/writable/*.conf`.
- User creation (provd -> `org.freedesktop.Accounts` `CreateUser` ->
  `adduser` in extrausers mode) and the password step need the
  UCD-PPA `passwd`/`adduser` package overlays — see
  diagnostics-methodology.md's extrausers section for what those
  packages actually change.
- Debian's systemd ships
  `org.freedesktop.locale1.read-only.conf` (a D-Bus policy denying
  `SetVConsoleKeyboard`/`SetX11Keyboard` to everyone, loaded LAST
  alphabetically, overriding the allow policy) — staged by SEVERAL
  parts, so it must be removed in an `override-prime` against the
  MERGED tree, not a single chroot hook (a chroot `rm` only cleans one
  copy).
- AppArmor exec denials surface to the caller as plain "Permission
  denied" (EACCES) — always grep
  `apparmor="DENIED"` ... `operation="exec"` before assuming a Unix
  permission bug when a wizard/session component fails to start.
- cloud-init "failures" on a nouser (no seed.iso) boot are cosmetic:
  Ubuntu Core disables cloud-init via
  `/etc/cloud/cloud-init.disabled` and only re-enables it when a
  seed/cidata datasource is present — nothing on the wizard/first-boot
  path depends on cloud-init for a nouser build.

Still open on the wizard (2026-11-23):
- After provisioning completes, the Flutter wizard (ubuntu_init, the
  main process of gnome-initial-setup.service) aborts at teardown:
  "FlutterEngineRemoveView ... The implicit view cannot be removed"
  plus "g_mutex_clear() called on uninitialised or locked mutex" ->
  SIGABRT. It happens after the user is created and the a11y handover
  ran; the created user and the desktop are unaffected; no coredump is
  written (Storage=none).
  (`20261120-ubuntu-init-flutter-teardown-abort.md`)
- provd's CreateUser rollback dies on a D-Bus type mismatch ("Type of
  message "(t)" does not match expected type "(xb)""), so a failed
  CreateUser leaves the partially-created user behind and the wizard
  UI spins forever on the unhandled gRPC exception.

## Newer confinement interfaces

The snapd fork has grown new interfaces beyond the ones described
above — don't assume "all unconfined": `pam-unix-chkpwd` (fork
allowance + base unix-chkpwd AppArmor profiles + gadget plug + build.sh
connect) and `kde-kauth` (fork allowance + gadget plug, see
kde-internals.md). GDM's daemon/worker/wayland-session processes run
under a static ENFORCING `gdm` profile (not unconfined) — any older
note or doc claiming GDM itself is unconfined is stale.

## DBusActivatable session apps: vendored service files + activation env

`DBusActivatable=true` desktop entries (e.g. org.gnome.Settings) go
through GIO's fire-and-forget `org.freedesktop.Application Activate`
path: a click silently no-ops with nothing in the journal if activation
fails, so `launch()` returning TRUE proves nothing — verify via
`busctl --user` / the process list instead. The (unconfined) session
bus daemon only scans the BASE snap's own
`/usr/share/dbus-1/services` (not a content/session snap's private
mount), so every such app needs a vendored `.service` file in
core-base-desktop's `static/usr/share/dbus-1/services/`. Two gotchas
for any future vendored file in this tree:
- The Makefile install target copies `static/*` BEFORE running the
  `*.chroot` hooks, and a greeter-trim hook can delete vendored service
  files with globs aimed at apt-staged duplicates — a targeted
  re-copy of just the affected files after the hooks run is the right
  shape (re-copying the WHOLE static tree after hooks is wrong: several
  hooks deliberately transform static content, e.g. writable-symlink
  conversions, systemd `[Install]` stripping). Diagnose by
  `unsquashfs -ls`-ing the ACTUAL built core.snap, not the source tree.
- Don't vendor a backend file whose `Exec=` is specific to one desktop
  (e.g. `org.freedesktop.impl.portal.Secret.service` pointing at the
  GNOME session snap) into a base shared by both GNOME and KDE images.
- Any activation-env variable a library treats as "set means override"
  (e.g. `WAYLAND_SOCKET` for `wl_display_connect`) must never be
  "cleared" by setting it to an empty string — D-Bus has no unset, and
  a set-but-empty value is NOT equivalent to absent. A session wrapper
  clearing stale activation-env values this way silently breaks every
  D-Bus-activated Wayland client (falls back to X11, where confined
  session apps have no access — "Failed to open display" soon after
  activation). Probe the actual activation env by pointing a service
  file's `Exec=` at `/bin/sh -c 'env > /tmp/actenv'` and calling
  `org.freedesktop.DBus.StartServiceByName`.
Faithful click-path repro over SSH: run the real GIO launch call from
inside the live shell's exact environment via
`nsenter -t <shell-pid> -m -- setpriv --reuid=<uid> --regid=<gid>
--init-groups env -i <env from /proc/<shell-pid>/environ> ... gjs
test.js` — keep the test script alive after firing `launch()` (an async
D-Bus call), or the target app starts, gets no activation delivered in
time, and exits cleanly ~10s later looking like nothing happened.

## Thin-base variant: gdm.service start-order gaps appear one at a time

On the thin core26-desktop base (`desktop` variant, see
core-base-desktop.md), gdm.service surfaces missing desktop-payload
pieces one at a time as more are added back, each with a DIFFERENT
failure signature — useful as a checklist when bringing up gdm on any
new/trimmed base:
1. Missing `/usr/bin` aliases (dconf, gdm-*, gnome-session*, wrapper):
   exit 127 "setpriv: failed to execute dconf" (generate-config runs
   `setpriv --reset-env`, resetting PATH, so these must resolve from
   rootfs `/usr/bin`).
2. Missing `/usr/share/dbus-1/system.d/gdm.conf`: gdm.service is
   `Type=dbus`, so the start job just times out (90s) when the daemon
   can't acquire `org.gnome.DisplayManager` — a classic D-Bus
   name-request denial logs NOTHING (no AppArmor denial either); see
   diagnostics-methodology.md's two-D-Bus-mechanisms note.
3. Missing AccountsService: gdm3 exits(1) fast with "Failed to list
   cached users: ... org.freedesktop.Accounts was not provided by any
   .service files" — needs the accounts-daemon binary plus its
   system.d policy and system-services activation file.
Also: a `gnome-session` shim that moves files must first check whether
the target base already ships the wrapped dispatch/`.real` alias pair —
otherwise it clobbers the alias and `gnome-session.real` execs itself in
a loop. And `-e` on an unsquashed tree is false for an absolute symlink
whose target doesn't resolve from the host root — use `-L` to check
existence of symlinks themselves.

## GSettings/dconf: one settings store for the confined session

The confined session snap used to run every GSettings client on
GLib's KEYFILE backend
(`$SNAP_USER_COMMON/.config/glib-2.0/settings/keyfile`)
instead of dconf, so nothing session-side ever saw what
provd wrote to the real dconf database (the exposing symptom: picking
"English (UK)" on the wizard's keyboard page never changed the
compositor keymap). GLib picks the default backend in
gio/gkeyfilesettingsbackend.c (gnome-shell 50, GLib 2.88) from two
snap probes (gio/gportalsupport.c):

    glib_should_use_portal()            -> snapctl is-connected desktop
    glib_has_dconf_access_in_sandbox()  -> snapctl is-connected gsettings

and `snapctl is-connected` matches plugs AND slots by name — the
session snap has a desktop SLOT (connected to snap-store), which is
enough to count as "sandboxed desktop". With no gsettings plug
anywhere and no :gsettings slot on Core, keyfile priority 110 beat
dconf's 10.

Landed design (2026-11-20): ONE live store — dconf — for the whole
session (shell, gsd-*, the a11y scripts):
- GSETTINGS_BACKEND=dconf is set in the snap environment, so no
  component can silently fall back to the keyfile store if the probe
  logic changes. Nothing else exports GSETTINGS_BACKEND (a wrapper-
  level export only distorts the unconfined user-manager/D-Bus
  activation environment — the snap env wins for confined apps).
- A dbus plug literally named `gsettings` (name ca.desrt.dconf) sits on
  EVERY app that touches GSettings: all apps plugging
  systemd-user-control plus the seven that don't (screencast-service,
  nautilus-service, xdg-desktop-portal-gnome, the three ibus
  services, colord). The broad grant is REQUIRED, not tidiness: a send
  to the well-known name ca.desrt.dconf needs
  peer=(name=ca.desrt.dconf), and the generic same-snap
  `peer=(label=snap.<snap>.*)` rules that come with
  systemd-user-control do not cover it — without the plug the a11y
  keybinding seeding fails with a real AVC
  (destination="ca.desrt.dconf"). The plug is gadget-connected at seed
  time only (see the in-place-upgrade note below).
- The dconf backend module ships in the gnome-desktop-runtime content
  snap: the thin base has no `/usr/lib/<triplet>/gio/modules`
  (libgio's compiled-in GIO_MODULE_DIR). Set GIO_EXTRA_MODULES to the
  runtime's `$SNAP/gnome/usr/lib/<triplet>/gio/modules` — derive the
  triplet, don't hardcode x86_64-linux-gnu. Side effect: that
  directory also enables the GVfs/proxy/TLS GIO modules for every
  session app (only libdconfsettings is needed for settings, but the
  module needs the runtime's libdconf on the app's LD path, so the
  whole directory is the practical form).
- A wizard session inherits DCONF_PROFILE=gnome-initial-setup, whose
  stock profile lives only in the fat system base — a confined session
  sees the plain core26 base, so with the dconf backend selected but
  the profile missing, dconf opens the null configuration (reads
  empty, writes unwritable). Ship the profile in the session snap
  under usr/share/dconf/profile/ (XDG_DATA_DIRS includes
  $SNAP/usr/share), or unset DCONF_PROFILE for that session — unset,
  not empty (see the FIXED ubuntu_init note above).

Rules for anything that reads or writes settings on this image:
- `gsettings set` exits 0 even when the dconf commit fails (verified
  with an unreachable bus: rc=0, the key keeps its old value). Never
  treat the exit code as "written": read every write back (bools
  exact, doubles numerically) before acting on it. The a11y handover's
  once-per-user marker is only written once every present key
  verified, so a failed write retries next session instead of being
  lost forever. The keyfile stays best-effort fallback only (for data
  from older images) — never a second live store, and never proof that
  a handover happened.
- Diagnose which backend a confined process REALLY uses from inside
  it: `snap run --shell ubuntu-desktop-session.gnome-shell -c
  'G_MESSAGES_DEBUG=all gsettings get
  org.gnome.desktop.input-sources sources'` (create
  `/var/lib/snapd/void` first) must print "Found default
  implementation dconf (DConfSettingsBackend)". A readback through any
  other backend/store than the session uses confirms whatever you
  wrote there — a self-consistent lie.
- Wizard-session dconf dbs: the per-boot db lives under

  ```
  /run/gdm3/home/<gnome-initial-setup*>/snap/ubuntu-desktop-session/common/.config/dconf/user
  ```

  the shm the clients mmap is
  `/run/user/<uid>/snap.ubuntu-desktop-session/dconf/user`.
- In-place upgrades of already-seeded devices are NOT supported
  (dangerous-model, unasserted development images). If upgrade
  support is ever added, BOTH a keyfile->dconf migration and a
  self-heal for the gsettings connection are required: the plug is
  only connected by the gadget at seed time, so a device refreshing
  the session snap in place would have it unconnected while
  GSETTINGS_BACKEND=dconf forces the backend — every session write
  denied — and existing users' settings live in the old snap-common
  keyfile.

Compositor-keymap probe used to verify end-to-end without a GUI: a
tiny gjs+Gtk window on the target session's WAYLAND_DISPLAY, then
Gdk.Keymap.translate_keyboard_state(12, SHIFT, 0) (hw keycode 12 =
KEY_3) — 0xa3 for the gb layout, 0x23 for us. To live-test a candidate
fix without a rebuild: bind-mount a patched run.sh over the snap's
(bind mounts made on the host are visible to NEW snap namespaces —
snap-confine rebinds from the host mount tree), `apparmor_parser -r`
any profile change, `systemctl restart gdm`.

## Layout binds for libraries with compiled-in absolute paths

Some libraries locate their plugins/modules/data at COMPILE-TIME
ABSOLUTE paths (e.g. `/usr/lib/<triplet>/<name>-<ver>`), not under
$SNAP. Staging the package in a provider snap is NOT enough: the files
become visible at `$SNAP/<mount>/...` but the library still looks them
up at the absolute path, which does not exist in the confined mount
namespace — it fails silently while everything around it works. Fix:
one `layout:` bind per affected path in the session snap's
snapcraft.yaml (e.g.
`/usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/tinysparql-3.0`,
`.../libcanberra-0.30`). The diagnosis that proves the gap: the
compiled-in path is missing under the RUNNING process's root
(`/proc/<pid>/root/<path>` — see diagnostics-methodology.md) while the
file exists under `/snap/<provider>/current/....`.
Worked signature (libcanberra): GSound/canberra-driven sounds silent
(g-c-c "Test speakers", event sounds) while normal app audio works
(libpulse/pipewire clients bypass canberra); journal: "Failed to play
sound: No such driver" (CA_ERROR_NODRIVER: backend dlopen failed). Red
herring: `wpctl status` showing the sound panel's per-channel
monitor/capture streams as active — those are level meters, present on
healthy desktops too. Related classes: KDE's subdirectory-RUNPATH
trap (kde-internals.md's session-namespace note) and the GIO module
dir (GIO_EXTRA_MODULES, section above).

## Snap-private /tmp: per-snap, shared across users, shadows the host

snap-confine binds `/var/lib/snapd/.../snap.<snap>/tmp` (root:root
01777) over /tmp for every confined process of a snap. Two properties
that bite:
- It SHADOWS the host /tmp — fixes applied to the host's /tmp are
  invisible to confined processes; the namespace-accurate view and
  write path is through a live confined process's root,
  `/proc/<pid>/root/tmp/...` (see diagnostics-methodology.md).
- It is SHARED across the users of the same snap — the wizard session
  (dynamic uid ~60578) and the user session (uid 1000) see the SAME
  /tmp. A cross-uid /tmp/.X11-unix collision used to SIGABRT
  gnome-shell: mutter demands the dir be owned by root or the current
  uid and does NOT accept a classic sticky-1777 dir owned by another
  uid. Fixed (core-base-desktop 840ab0d) with a boot-time root oneshot
  normalizing /tmp/.X11-unix root-owned 1777 before any session runs,
  plus a launcher self-heal: root-owned 1777 is accepted by every uid,
  and the sticky bit keeps a dynamic-uid session from deleting or
  replacing it.
Upstream notes (recorded): mutter should accept sticky 1777
.X11-unix dirs regardless of owner; snapd should mount the private
tmpfs per-USER, not per-snap — the cross-uid collision is inherent
for any multi-user snap writing /tmp content.

## D-Bus name binds: one name per slot, rules land only on referencing apps

snapd's dbus interface (interfaces/builtin/dbus.go): each dbus slot
carries ONE name, and the bind/send rules land ONLY in the AppArmor
profiles of the apps that reference the slot (an app's `slots:` list
and `activates-on:` scope it; a slot referenced by NO app applies to
all apps of the snap). Consequences for the session snap:
- Every well-known name a session app owns must be declared as its own
  dbus slot and referenced from the owning app, or the bind is denied.
- Apps forked from gnome-shell inherit the SHELL's profile label — the
  shell's profile needs bind grants for every service name the
  session's apps own.
- DBusActivatable panels fail SILENTLY without their bind: failed
  register -> exit -> the menu spinner just dies. Audit with
  `journalctl -b | grep dbus_bind | grep DENIED`.
- GDBus resolves well-known names to unique names before sending, so
  `peer=(name=<well-known>)` rules NEVER match unconfined owners —
  label-based grants are the only mechanism for unconfined peers and
  are broad by nature. Prefer confining the peer (root-cause fix: the
  base's gnome-content-launch dispatches the initial-setup session's
  gnome-shell into the confined session snap) over granting
  unconfined-peer sends.

## GDM dynamic session users: incrementing uids, ephemeral homes

The greeter and wizard sessions run as dynamic users (gdm-greeter,
gnome-initial-setup) with uids 60578/60579/... — INCREMENTING and
REUSED after exit; never assume a fixed uid or a stable username
suffix (gdm-greeter vs gdm-greeter-2 alternates). Their homes
(`/run/gdm3/home/<name>`) are on tmpfs: EPHEMERAL, recreated per boot —
per-boot state delivery into these sessions uses path-triggered units
(.path units globbing the runtime dirs) plus a session-bus write
through the target session's own dconf service. /var/lib/gdm3 belongs
to the gdm daemon user and is inert for session state.
- Identify the current dynamic uid per boot (loginctl/pgrep -u);
  never hardcode.
- The accounts have /usr/sbin/nologin shells: use
  `su -s /bin/sh <user> -c '...'` (runuser -u fails on nologin) — see
  diagnostics-methodology.md.
- The a11y greeter mirror re-delivers per boot BY DESIGN (nothing
  persists in the greeter home) — see accessibility.md.

## Wizard-phase autologin: /etc/gdm3/custom.conf must be writable

The wizard's "log in automatically" step chains: Flutter wizard ->
provd -> AccountsService
org.freedesktop.Accounts.User.SetAutomaticLogin -> accounts-daemon
save_autologin_gdm() -> g_file_set_contents("/etc/gdm3/custom.conf").
That atomic write CANNOT go through the /etc/writable symlink
indirection: g_file_set_contents builds its temp file as
`<name>.XXXXXX` in the target's OWN directory and renames it over the
target (replacing a symlink, not following it), so on a read-only
squashfs /etc/gdm3 the temp creation fails EROFS and the choice never
lands (provd surfaces gRPC Internal "failed to set autologin"). This
is a concrete instance of the atomic-write-vs-symlink gotcha in
diagnostics-methodology.md. GDM consumes autologin ONLY from
custom.conf keys (daemon/AutomaticLoginEnable, daemon/AutomaticLogin
— gdm-manager get_automatic_login_details); this GDM build does not
read AccountsService's per-user AutomaticLogin flag, so the
custom.conf write is the only path that matters.

Fix shape (PR core-base-desktop#92; the mount + seeding verified live
2026-11-23 — packaging placement rules in core-base-desktop.md):
bind /writable/system-data/etc/gdm3 over /etc/gdm3 (x-initrd.mount),
tmpfiles `C /writable/system-data/etc/gdm3`, factory template at build
time. tmpfiles `C` preserves symlinks inside the copied tree, so the
factory copy of etc/gdm3 keeps its custom.conf ->
../writable/gdm3/custom.conf symlink working through the bind.

STILL OPEN even with the mount: accounts-daemon runs SNAP-CONFINED on
current images (snap.accountsservice.accounts-daemon — the
accountsservice snap is in the model; an older base tree's unconfined
/usr/libexec/accounts-daemon is stale evidence), and its profile
grants only `r` on the literal /etc/gdm3/custom.conf — a read through
the /etc/writable symlink never matches, because AppArmor mediates
the RESOLVED path — and it has no write grants at all. The wizard then
fails with gRPC INTERNAL "failed to set autologin: failed to change
automatic login: Permission denied". The full fix = the core-base
mount + these grants in the accountsservice snap profile
(live-verified with `apparmor_parser -r`, then reverted):

    /etc/writable/gdm3/custom.conf r,
    /etc/gdm3/ rw,
    /etc/gdm3/custom.conf rw,
    /etc/gdm3/custom.conf.* rw,

Once the write works: the wizard's identity page demands a non-empty
password even when "log in automatically" is chosen (isValid insists —
the account still gets one, for sudo); after the wizard-phase write
/etc/gdm3/custom.conf is a REAL file (the rename replaced the symlink)
inside the writable tree, and /etc/writable/gdm3/custom.conf (still
seeded by the image build) goes STALE — GDM reads
/etc/gdm3/custom.conf, so the runtime config is authoritative and any
tooling reading the /etc/writable path sees old data once the wizard
has rewritten it. Verified end-to-end: the setting persisted across
reboot and GDM autologged the created user straight into the confined
session (wayland-0 -> snap.ubuntu-desktop-session/wayland-0).
