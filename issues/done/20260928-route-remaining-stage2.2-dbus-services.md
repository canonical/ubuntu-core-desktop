# Route and verify the remaining GNOME session D-Bus services

## Impact / Priority

High. Some desktop services still run unconfined while the session and
file-manager apps are confined. This can leave service interactions
outside the intended confinement boundary and can degrade file
browsing, search, portals, online accounts, or keyring behavior. The
full user-visible impact is not yet established: a live VM showed
repeated AppArmor denials from confined Nautilus to unconfined peers,
but the affected workflows have not all been tested deliberately end to
end.

## Context

This is the remaining tranche of Stage 2.2 in
`20260922-split-core26-desktop-base-snap.md`. The greeter collision and
the specific gnome-shell AppArmor gaps have their own completed notes;
their completion does not mean all D-Bus-activated desktop services have
been routed and verified.

On the running GNOME VM (2026-09-28), gnome-shell and the `gsd-*`
services had per-app enforce labels. The following active services were
still unconfined: `gvfsd`, `xdg-desktop-portal`, `gnome-keyring-daemon`,
`localsearch-3`, and `goa-daemon`. The journal also showed confined
Nautilus denials to unconfined GVFS, Tracker, and portal peers. Other
services in the parent plan may be inactive until D-Bus activated, so
audit the full set rather than treating this live process list as
exhaustive.

The xdg-desktop-portal frontend is distinct from its backends. On the
inspected VM, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-gnome`, and
`xdg-document-portal` were already launched as session-snap apps; verify
their actual labels and behavior before changing their routing. The GTK
portal backend currently has no `home` plug. If it is confined, determine
how its file chooser can browse and open a user-selected file under
`$HOME`; the frontend itself should not be given broad home access just
to make the chooser work. The document portal should expose only the
selected files to requesting apps.

Remaining candidates listed in the parent plan include GVFS and its
monitors, localsearch/Tracker, the portal frontend and
rewrite-launchers, document/permission store, GOA and identity service,
gnome-keyring/GCR, dconf, glib-pacrunner, spice-vdagent,
user-session-migration, xdg-user-dirs services, gnome-initial-setup,
control-center, extensions-app, and GJS-launched services. Classify each
as already confined, host-exec'd, or not yet exercised before editing
it.

## Work plan

1. Audit each candidate's D-Bus activation file and systemd user unit.
   Record its Exec/ExecStart, whether the corresponding snap app exists,
   and the live process AppArmor label when activated.
2. For host-exec'd services that have a session-snap app, route systemd
   units through `/snap/bin/ubuntu-desktop-session.<app>` in
   `core-base-desktop`, and override D-Bus activation files with the
   corresponding snap app and `AssumedAppArmorLabel`. Also audit desktop
   autostart entries and socket-activated units so they do not bypass
   the routed launcher. Apply the established greeter scoping for units
   that also run in GDM, and clear any base `AppArmorProfile=` override
   that would stack the wrong profile. Add a snap app only if one is
   genuinely missing.
3. Verify one service at a time on a fresh user session: it starts with
   the expected per-app enforce label, the greeter remains healthy, and
   no new AppArmor denials appear. Add only the narrow D-Bus/file rules
   needed by observed behavior; keep known-optional probes (such as
   fingerprint-device discovery) explicitly classified rather than
   granting broad access.
4. Exercise real workflows for each service family, especially opening
   the file chooser from a confined app and selecting a file under
   `$HOME`, GVFS browsing, search, online accounts, and secrets. Verify
   selected file access is delivered through the document portal without
   giving clients broad home access.
5. Update the parent plan with the per-service results. Stage 2.4's
   content-snap scaffold can proceed independently from this routing,
   but complete this tranche before treating the whole session split as
   ready for Stage 2.5/2.6 integration and verification.

## Progress (2026-09-28)

Started with GVFS `gvfsd`:

- Added a `dbus-gtk-vfs-daemon` session-bus slot for
  `org.gtk.vfs.Daemon` and associated it with the `gvfsd` app in
  `ubuntu-desktop-session-snap/snap/snapcraft.yaml`.
- Added a greeter-scoped systemd user-unit drop-in in
  `core-base-desktop` to launch `gvfs-daemon.service` through
  `/snap/bin/ubuntu-desktop-session.gvfsd`.
- Built the session and core-base snaps and a fresh GNOME image. The
  packed session manifest contains the GVFS app-to-slot association, and
  the image-generated profile permits `org.gtk.vfs.Daemon`.
- On both live iteration and the fresh image, the GVFS unit starts with
  `snap.ubuntu-desktop-session.gvfsd (enforce)` and owns
  `org.gtk.vfs.Daemon`. A shell confined as the Nautilus service
  successfully ran `gio list file:///home/your_username`. The
  fresh-image browse produced no new error-level journal entries or
  AppArmor denials.
- The initial live iteration used a temporary matching bind rule because
  the running VM's sideloaded snap could not be refreshed from a local
  snap file; the final result was then confirmed with the generated
  policy in the rebuilt image. An unconfined D-Bus introspection probe
  was refused by policy; that synthetic probe is not a supported
  desktop-client path.
- An initial route of `xdg-permission-store` through a session-snap app
  started under its enforce label, but real portal use showed the
  unconfined host `xdg-desktop-portal` frontend's
  `PermissionStore.Lookup` call denied by the confined service. The
  core-session `dbus` slot policy permits connected snap peers, not this
  unconfined host caller. Removed the app/slot and systemd drop-in so
  the permission store remains host-executed until the portal frontend
  can be confined with a compatible D-Bus policy.
- Tried routing `xdg-desktop-portal` after finding its host activation
  file assumes `unconfined`. The fresh image included a matching
  `AssumedAppArmorLabel` for the snap app and a generated profile with
  the Desktop bus-name bind rule, but the frontend remained in
  `activating` and never owned `org.freedesktop.portal.Desktop`. A
  confined shell could request that name, and could introspect the
  permission-store, document-portal, and GNOME-backend services, so the
  failure is not explained by a missing bind rule or backend D-Bus
  access. The host unit was restored on the VM, and the non-working
  frontend app slot, unit override, and activation-file override have
  been removed from source. Keep this frontend unconfined until its
  startup/activation behavior is understood; do not add broad
  NetworkManager permission based only on the earlier live-test denial.
- The fresh boot also logged `ibus-portal-service: Not connected to the
  ibus bus` and the known `colord` cache-directory failure. These were
  not changed here; compare them with a baseline before treating them
  as regressions.
- Audited `gnome-keyring-daemon` next. Its session D-Bus activation
  files for `org.gnome.keyring` and `org.freedesktop.secrets` execute
  the host binary; GNOME also has `secrets` and `pkcs11` autostart
  entries. Associated the existing session-snap D-Bus slots for both
  names with the daemon app, routed both activation files with
  `AssumedAppArmorLabel`, and overlaid both autostart entries to launch
  `ubuntu-desktop-session.gnome-keyring-daemon`. The packaged systemd
  unit/socket are installed but inactive and disabled on the inspected
  VM.
- Live-tested source-equivalent D-Bus activation after stopping the
  original host daemon: `org.freedesktop.secrets` started as
  `snap.ubuntu-desktop-session.gnome-keyring-daemon (enforce)`, and a
  confined `nautilus-service` client successfully introspected the
  Secret Service API and read the `session` collection alias. An
  unconfined host caller was denied access by AppArmor; determine
  whether any required host caller needs this API before considering
  broader access. The actual store/unlock workflow and GCR prompting
  remain untested.
- The separate `org.freedesktop.impl.portal.Secret` activation still
  uses the host file. Routing it to the already-running keyring app
  timed out, but the same activation also timed out with the original
  unconfined host daemon, so this is not evidence of a regression.
  Leave it unchanged pending separate investigation. GCR's private
  prompter activation also remains host-exec'd; the system prompter
  name is currently owned by confined `gnome-shell`.
- Restored the live VM's original host keyring activation after testing
  and removed all temporary keyring D-Bus service files. The source
  changes have not yet been included in a rebuilt image.

GVFS and the permission store were already integrated and verified on a
fresh GNOME image. Continued the audit against the live session and
added source routing for the previously host-executed GVFS monitors and
metadata daemon, LocalSearch/Tracker services, GOA and identity
services, dconf, GLib PACRunner, keyring/GCR helpers, GNOME Shell D-Bus
helpers, Settings/Extensions providers, Nautilus'
`org.freedesktop.FileManager1` activation, user-session migration,
user-directory helpers, and portal launcher rewriting.
D-Bus app slots and activation overlays were added where direct
activation was required; systemd drop-ins route unit-activated services.
The LocalSearch indexer/writeback and user-directory helpers have home
access. Outbound network access is assigned only to GOA, identity, and
PACRunner apps, which need it for sign-in and PAC retrieval.

The final session snap has packed successfully. The core-base snap is
being rebuilt to include the final Nautilus FileManager1 and GTK
user-directory autostart overlays; no fresh image has been tested yet.
The GNOME VM was shut down cleanly before rebuilding. The portal
frontend remains a blocker because its confined app failed to own
`org.freedesktop.portal.Desktop`; keep it on the host until its
activation failure is understood. The live VM's GCR SystemPrompter name
was owned by confined `gnome-shell`, so its host D-Bus activation
fallback was not changed. The current VM has no SPICE virtio port, so
`spice-vdagent` cannot be exercised there. GNOME Initial Setup's
first-run unit is GDM-owned, while its regular-user upgrade unit only
runs when migration markers are present; neither path can be exercised
with this existing account, so both remain on the host pending a
dedicated first-run or upgrade fixture. dconf is inactive because this
session uses `GSETTINGS_BACKEND=keyfile`; PACRunner is inactive without
a proxy configuration. Fresh-image startup, service labels,
regressions, and real workflow checks remain to be completed. An
additional `org.freedesktop.MalcontentControl` activation file points
to `/usr/bin/malcontent-control`, but that executable is absent from
the image and no session-snap app/package supplies it. This route is
blocked on deciding whether the parental-controls application belongs
in the image; no broken snap launcher was added.
The base also ships `geoclue-demo-agent.desktop` as a host-executed
autostart, but the session snap has no GeoClue agent app. Routing it
would require a separate decision about the location-authorization
agent's system-bus policy; it is recorded as an additional blocker
rather than granting broad system-bus access speculatively.

## Follow-up fresh-image investigation (2026-09-28)

The first rebuilt image reached the GNOME session. `gvfsd`,
`gvfsd-metadata`, LocalSearch, GOA/identity, the Secret Service keyring,
and the permission store were observed under their expected
`snap.ubuntu-desktop-session.* (enforce)` labels. From a confined
`nautilus-service` shell, `gio list file:///home/your_username` listed
the user's standard directories, and Secret Service introspection
succeeded. The unconfined `gnome-keyring-daemon --daemonize --login`
process is still started by the login/PAM path; only the session Secret
Service process is routed.

Nautilus' `org.freedesktop.FileManager1` activation initially failed
because its host D-Bus service file did not direct activation to the
snapd-generated user unit. Added
`SystemdService=snap.ubuntu-desktop-session.nautilus-service.service`
and changed `Exec` to `/usr/bin/snap run ...`; a VM runtime test then
activated Nautilus under its enforce label and registered both
`org.freedesktop.FileManager1` and `org.gnome.Nautilus`.

The GVFS UDisks2 monitor cannot be confined against the current image:
the built-in `udisks2` plug has no connectable system slot here, and
`snap connections --all` showed it disconnected. The confined monitor
was denied UDisks2 calls. A temporary VM-only user-unit override
launched the host monitor unconfined; it connected to host UDisks2 and
enumerated the VM's drives/volumes. Removed the snap route, app
slot/plug, and systemd drop-in from source so this functionality
remains host-executed until UDisks2 is supplied by a snap with a
connectable slot.

The home browse test also exposed an attempted read of `$HOME/.hidden`
by confined GVFS; added the narrow existing `dot-hidden` personal-files
plug to `gvfsd` and Nautilus, and the image builder now connects all
declared personal-files plugs to snapd's personal-files slot. This
session snap has packed; the final core-base rebuild and fresh-image
verification of these last source changes are still pending.

Known remaining gaps: the portal frontend stays host-executed because
its confined version cannot register with the host portal; dconf and
PACRunner are inactive with the current keyfile/no-proxy configuration;
GCR prompting/store-unlock and portal file-selection workflows have not
been exercised; GNOME Initial Setup needs a first-run/upgrade fixture;
SPICE has no virtio port; Malcontent's executable is absent; and the
GeoClue demo agent requires a separate system-bus policy decision.
The boot also reports the known IBus portal activation failure and
baseline machine-id/floppy/Bluetooth warnings. Treat the synthetic
unconfined `gio mount -l` denials against confined GVFS monitor peers
as unsupported host probes, not as supported desktop-client
regressions.

## GTK portal readiness follow-up (2026-09-28)

The final-image boot showed that D-Bus activated the confined GTK
portal backend before `graphical-session.target` (09:13:13 versus
09:13:40). It repeatedly failed with `cannot open display` and exhausted
its restart limit. After the desktop was ready, starting the same snap
service manually succeeded, indicating a startup-order race rather than
a missing display plug.

Verified a VM-only user-systemd drop-in with
`After=graphical-session.target` on a fresh reboot. The target was
reached before GTK backend activation; the backend then reached
`active/running` with zero restarts, and
`org.freedesktop.portal.Desktop` responded to introspection. Added the
durable equivalent at

    core-base-desktop/static/usr/lib/systemd/user/snap.ubuntu-desktop-session.xdg-desktop-portal-gtk.service.d/core-override.conf

including `PartOf=graphical-session.target` to preserve the host unit's
session lifecycle. The source-built image still needs to be rebuilt and
checked with this drop-in. The actual file chooser flow from a confined
client remains untested; the backend also reports an AT-SPI bus warning
(`org.a11y.Bus` unavailable), which is separate from the display
failure.

## File chooser follow-up (2026-09-28)

From a shell confined as `nautilus-service`, an `OpenFile` request
reached the host portal frontend, but the frontend initially dispatched
`org.freedesktop.impl.portal.FileChooser` to the GNOME backend even
though that backend does not expose the interface. A VM-only
`~/.config/xdg-desktop-portal/portals.conf` selecting GTK for
FileChooser made the request reach the GTK backend. The GTK backend then
tried to enumerate `~/` and AppArmor denied it because the app had no
`home` plug.

Added a GNOME-specific system portal preference at
`core-base-desktop/static/usr/share/xdg-desktop-portal/gnome-portals.conf`
to route FileChooser requests to GTK without changing other desktops'
portal selection, and added the standard `home` plug only to
`xdg-desktop-portal-gtk`. This grants the chooser backend access to
browse the user's non-hidden home files; the portal frontend and
requesting clients remain without broad home access. These source fixes
still need a rebuilt image and a fresh confined file-chooser request to
verify.

## NetworkManager D-Bus policy follow-up (2026-09-28)

The latest fresh boot also logged NetworkManager property-signal
denials to confined `gnome-shell`, and NetworkManager method-call
denials from confined `gsd-sharing`. Neither app declared the
`network-manager` plug, and the GNOME gadget had not connected that
plug to the `network-manager:service` slot. Added `network-manager` as
an app-scoped plug to `gnome-shell` and `gsd-sharing`, and tested a
VM-only `snap connect ubuntu-desktop-session:network-manager
network-manager:service`. Both confined app shells then successfully
called NetworkManager's `GetPermissions` method, with no matching
denials in the follow-up check. Added the equivalent connection to the
GNOME gadget in `ubuntu-core-desktop/build.sh`; the rebuilt image still
needs to verify that the connection is automatic and the boot-time
denials are gone.

## Latest portal and NetworkManager follow-up (2026-09-28)

After removing the temporary user-systemd override on the live VM, a
fresh reboot with that override added back showed that ordering the
host `xdg-desktop-portal.service` after `graphical-session.target`
allows the frontend and GTK backend to become active with zero
restarts. D-Bus introspection then exposed
`org.freedesktop.portal.FileChooser`. Added the durable ordering to the
core-base unit source.

A persistent client running under the external `snap-store` profile
opened the GTK chooser, selected the visible `~/portal-test.txt`, and
received its document-portal URI. Reading the URI failed because the
confined `xdg-document-portal` worker itself was denied opening the
selected home file. Added the standard `home` plug to that daemon only;
requesting apps still receive only the document-portal path. A fresh
image must confirm that the daemon can now serve the selected file.

The rebuilt session snap includes that plug and adds `network-manager`
to `gsd-rfkill`. A newly built image confirmed that the session `home`
and `network-manager` plugs auto-connect through the gadget and showed
no NetworkManager AppArmor denials. That image used a core snap built
before the permission-store route was removed; its stale unit drop-in
therefore tried to launch the now-removed snap app and prevented portal
startup. A clean core-base rebuild from the updated source is in
progress; repeat portal verification on the image built from that core
snap before closing the remaining portal work.

## IBus and remaining D-Bus policy triage (2026-09-28)

The current boot's IBus private-bus address file and socket both
existed; the earlier failed direct test had used a stale socket name.
From the confined `ibus-portal-service` profile, a D-Bus introspection
call to `org.freedesktop.IBus` over the current address succeeded,
ruling out socket access and the `wayland-client` plug as the failure.
The running portal process had `WAYLAND_DISPLAY` and
`XDG_CONFIG_HOME` but no `IBUS_ADDRESS`; supplying the current address
through the user systemd manager made it start under its enforce
profile and own `org.freedesktop.portal.IBus`. Added a dedicated
launcher that resolves the address file from the machine ID and bare
display name. A fresh image must verify that this launcher handles
normal D-Bus activation.

The same boot recorded a GOA NetworkManager `GetAll` denial, UPower
KbdBacklight `GetBrightness`/`SetBrightness` denials from `gsd-power`,
and a GDM `RegisterDisplay` denial from `gnome-shell`. Added the
app-scoped `network-manager` plug to `goa-daemon`, `upower-observe` to
`gsd-power`, and `login-session-control` to `gnome-shell`. The gadget
already connects all three system plugs. Confirm each on the next
clean boot; if UPower brightness writes remain denied, classify them
separately because no `upower-control` interface is available.

## Final clean-image verification (2026-09-28)

Rebuilt the session snap and core-base snap with their build scripts,
assembled the image with the image build (`build.sh`), and booted it in
QEMU. The user session reached `graphical-session.target`; GDM and
GNOME Shell were active.

- The new IBus launcher found the current per-display address without a
  systemd environment override. `ibus-portal-service` started
  automatically under
  `snap.ubuntu-desktop-session.ibus-portal-service (enforce)` and owned
  `org.freedesktop.portal.IBus`; no `Not connected to the ibus bus`
  error recurred.
- `goa-daemon`, `gsd-power`, and `gnome-shell` started under enforce
  profiles. The GOA NetworkManager and GDM `RegisterDisplay` denials
  disappeared. `upower-observe` removed the UPower `GetAll` denials
  from GNOME Shell and LocalSearch. `bluez` was auto-connected by the
  GNOME gadget; a call to BlueZ `GetManagedObjects` succeeded from the
  confined GNOME Shell profile.
- `xdg-desktop-portal.service`, the confined GTK and GNOME backends,
  and `xdg-document-portal` were active with zero restarts. The
  FileChooser interface was introspectable. Confined Nautilus listed
  the home directory and accessed the Secret Service API. The
  end-to-end chooser selection/read through the document portal was
  already verified on the preceding clean image; it was not repeated
  interactively on this final boot.
- The final boot still logs `gsd-power`'s
  `UPower.KbdBacklight.GetBrightness` denial. `upower-observe` does not
  grant this method and Snap has no `upower-control` interface; QEMU
  exposes no keyboard-backlight hardware, so the hardware impact
  remains unknown. Do not broaden policy without a supported interface.
- GNOME Shell's `GeoClue2.Manager.AddAgent` call remains denied against
  the unconfined host `geoclue.service`; there is no connectable host
  location slot, and the GeoClue demo agent has no session-snap app.
  Leave it blocked pending a dedicated system-bus authorization design.
- `xdg-desktop-portal-gnome` consistently logs a timeout opening
  Mutter's Wayland service channel on initial activation. Restarting it
  later makes `OpenWaylandServiceConnection` succeed from the confined
  app. The GTK FileChooser route is unaffected; GNOME-specific dialog
  behavior during early startup remains an ordering limitation.
- Other remaining dispositions: UDisks2 monitor stays host-run because
  there is no connectable slot; portal frontend and permission store
  stay host-run because the confined frontend cannot own the Desktop
  name and the host frontend cannot call a confined permission store;
  GCR prompt/unlock was not exercised; dconf and PACRunner were
  inactive (keyfile backend/no proxy); lazy Settings/Extensions
  providers were routed but not deliberately activated. LocalSearch's
  `.hidden` probe remains intentionally denied.

There were no error-level journal entries on the final boot. Remaining
warnings included absent RealtimeKit, PipeWire, and AT-SPI services; the
final kernel audit also showed the unrelated Snap Store namespace probe
and an Avahi ping from host GeoClue. These are recorded rather than
hidden or fixed with broader access.

Resolution: this tranche is complete to the requested criterion: every
candidate is routed and verified, or has a concrete blocker/inactive
workflow recorded above. The parent plan is updated for Stage 2.4.

Commits:

- ubuntu-desktop-session-snap: e39e0f3
- core-base-desktop: 73bc174
- ubuntu-core-desktop: 19a71f7

## Resolution of remaining scope decisions (2026-09-28)

The GeoClue demo agent is not used in the GNOME session. Its host
autostart entry is removed by
`core-base-desktop/hooks/002.4-configure-system-setup-tool.chroot`.
This does not resolve GNOME Shell's separate denied GeoClue
`Manager.AddAgent` call; location-agent authorization remains a distinct
policy question.

The stock GNOME Initial Setup executable, regular first-login helpers,
and upgrade-login helper are removed/disabled. The GDM
`gnome-initial-setup` session and its wrapper are intentionally
retained: they launch the Ubuntu `ubuntu-desktop-init` first-boot
wizard, rather than the stock GNOME wizard. Removing that GDM session
would break the Ubuntu setup flow. Important confinement caveat: the
configure hook rewrites the wrapper to execute
`/snap/ubuntu-desktop-init/current/bin/ubuntu_init` directly, explicitly
to run without confinement. Although the snap metadata declares strict
confinement, this GDM first-boot launch path bypasses it and is not a
confined component.

SPICE vdagent, Malcontent, and dconf are outside the required product
scope: there is no SPICE virtio device in the supported test VM,
parental-controls functionality is not required, and the desktop uses
the keyfile GSettings backend. No confinement work is required for
those inactive/unneeded components.

The host portal frontend is still an open confinement gap. Its separate
investigation and acceptance criteria are in
`20260928-confine-portal-frontend.md`.
