# First-boot black-screen delay, journal errors, late desktop

Date: 2026-11-20

## Impact / Priority

On a fresh install of the dconf-migration image the owner
reported a long black screen before the installer ran (~1 min of
first-boot snap seeding), "lots of errors in the journal" after
completion, and the desktop arriving ~53 s late after login. Two
of the three causes (the handover path-unit storm and the
content-data lock deadlock) were real bugs fixed here; the black
screen is inherent first-boot seeding cost.

Impact derived from the original note's described symptoms.

## Report

REPORT (owner): the test VM with the dconf-migration image. Ran
the installer. "Quite a delay with the black screen before the
installer ran"; after completion "lots of errors in the journal",
and "the desktop did not come up" (it did, ~53 s after login).

WHAT THE JOURNAL SHOWS (all times GMT, boot 358c... of that VM)

### 1. The black screen before the wizard is the first-boot snap seed

systemd-analyze blame: core.start-snapd.service 1 min 13 s,
snapd.seeded.service 1 min 9 s, gdm-homedirs.service 7.2 s.
snapd started 21:58:39 and only finished seeding at ~21:59:48;
gdm does not start until seeding is done. This is first-boot
seeding of the image's snaps (snapd's own "startup timeout by
30s plus 5s per snap" estimate), not the GSettings change: no
snap was downloaded, and the same cost exists on every image
line. Only the first boot pays it.

### 2. The handover path unit stormed (fixed, core-base 4fad222)

provd wrote /etc/dconf/channel/handover/ucd-handover.ini at
22:02:01.206. ucd-a11y-handover-live.path used PathExists=, and
a oneshot service that exits while its path condition still
holds is re-activated immediately: 366 runs between
22:02:01.211 and 22:02:09, ~45/s, each spawning a transient
logind session through su (session c52 ... c137+ in the
journal) until the path unit hit its trigger limit:

    ucd-a11y-handover-live.path: Trigger limit hit, refusing further
    activation; Failed with result 'trigger-limit-hit'

so systemctl is-system-running = degraded. The first runs DID
capture the live state (handover: live read (as
gnome-initial-setup) screen-reader-enabled=true), so the a11y
handover itself worked; the rest were the retrigger loop.
FIX: PathChanged= instead of PathExists=. Verified live on that
VM with a /run/systemd/system drop-in: starting the path with
the ini present no longer storms; touching the sibling
ucd-handover-greeter-state does not trigger; touching the ini
triggers exactly once; moving the ini back (creation) triggers
exactly once.

### 3. The ~50 s desktop delay is a content-data lock deadlock

FIXED in ubuntu-desktop-session bf5ec7d. First login of the new
user: gnome-session started at 22:02:05,
but "Starting GNOME session target" only at 22:02:57. In
between:

- gdk-pixbuf-query-loaders was building the content-snap image
  data while holding XDG_RUNTIME_DIR/desktop-content-data.lock;
  it asked GIO for the default VFS, which D-Bus-activated
  gvfsd;
- gvfsd's wrapper sources the same gdk-pixbuf-env.sh, so it
  waited 30 s for that lock and failed:

      ubuntu-desktop-session.gvfsd: Timed out waiting for content-snap
      image data setup   -> Failed with result 'exit-code'

- the query itself waited ~50 s on the gvfsd activation
  (gdk-pixbuf-quer: Error creating proxy: StartServiceByName
  for org.gtk.vfs.Daemon: Timeout was reached), then wrote the
  stamps (content-stamp at 22:02:56.659) and the session
  proceeded.

Every other session service activated in that window failed for
the same reason (xdg-desktop-portal-gnome, xdg-document-portal,
xdg-permission-store, session-environment-broker), which is the
bulk of the "lots of errors after the installer".
FIX: run the loader query with GIO_USE_VFS=local
GIO_USE_VOLUME_MONITOR=none. Verified live: with those vars
there is no StartServiceByName for the vfs services on the
session bus, and the generated loader cache is byte-identical
to the old one (cmp). The lock holder can no longer wait on
gvfsd, and gvfsd no longer waits on the lock.

### 4. The wizard UI still aborts at teardown

Pre-existing app bug, not fixed here. Tracked in
`20261120-ubuntu-init-flutter-teardown-abort.md`.
After the user was created and the handover ran, the Flutter UI
(ubuntu_init, the wizard's Main process) hit:

    embedder.cc: 'FlutterEngineRemoveView' returned
    'kInvalidArguments'. Remove view info was invalid. The implicit
    view cannot be removed.
    g_mutex_clear() called on uninitialised or locked mutex
    -> signal 6/ABRT (no coredump written)

It happens after provisioning is complete and does not affect
the created user (ubuntu-desktop-provision side).

### 5. Two unhandled Dart exceptions at UI startup (fixed, core-base 4fad222)

    ERROR ubuntu_init: Unhandled exception
            String: No DConf source to write to

twice at 22:01:00, from package:gsettings/src/dconf_client.dart
(notify and write paths). Cause: gnome-initial-setup.service set
DCONF_PROFILE= (empty) for the Flutter UI; the Dart client
treats an empty value as a profile NAME, looks for a profile
called "", finds none and returns no sources. (Setting the real
profile is not an option: the client cannot parse its file-db
line and throws "Unknown DConf source".) FIX: `env -u
DCONF_PROFILE` so the client falls back to the default user
dconf source on the session bus - the same user database GNOME
keeps the profile for.

### 6. Harmless noise at the same moment

- the wizard's own session manager (uid 60578) tears the
  session down while D-Bus activation requests are still
  arriving, so its journal has a burst of "Failed to start
  snap...portal/gvfsd" lines; the user session's own copies of
  those services start normally afterwards.
- gsd-media-keys: g_hash_table_size: assertion
  'hash_table != NULL' failed (upstream teardown warning).
- "Failed to start X Wayland" absent; zero dconf AVCs; the
  wizard chord and the handover live-read both worked on this
  VM.

## Status

STATUS: all three code fixes are committed locally (no pushes):
core-base-desktop desktop/26 4fad222 (path unit + DCONF_PROFILE),
ubuntu-desktop-session desktop/26 bf5ec7d (pixbuf query env).
The path-unit and query behaviors were verified live on the
reported VM; an end-to-end first-boot run on a rebuilt image is
still pending (it needs base + session snap + image, then the
wizard). The Flutter teardown abort remains open (app-side,
ubuntu-desktop-provision).
