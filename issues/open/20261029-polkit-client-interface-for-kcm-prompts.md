# Grant session apps polkit client access (KCMs cannot prompt)

## Impact / Priority

Priority: High. EVERY GUI admin action on the KDE image is dead on
arrival. KCMs run a client-side polkit check BEFORE applying; that
check is AppArmor-denied, so the KCM concludes it cannot authenticate
and never performs the action. No prompt is ever shown -- polkitd
never even sees a request. This blocks the "real sudo action from the
GUI" QA item that has never passed on this image
(`20261015-fix-kde-boot-errors.md` item e) and any admin UI generally.

## Context

Written 2026-10-29, after the timezone-control plug work
(plasma-desktop-session 9392c66 + build.sh f352a66) fixed timedated
TRANSPORT access but the Date & Time KCM still produced no polkit
prompt and applied nothing (user report + live VM forensics, image
20261027+git9392c66, the test VM, boot 15:32).

## What already works (do not re-derive)

- timezone-control plug: zero timedate1 denials since 9392c66; the
  Date & Time KCM reads state from timedated fine (system-bus
  activations of org.freedesktop.timedate1 requested by the
  plasmashell-labelled process at every KCM open).
- Server side is healthy: `timedatectl set-timezone` as root works
  (tested; reverted to Etc/UTC). polkitd 127 running unconfined;
  policy org.freedesktop.timedate1.* all allow_active=auth_admin_keep;
  admin rule = unix-group:sudo (49-ubuntu-admin.rules) so admin
  password auth is accepted. polkit-kde agent starts and is connected.
- The KCM is NOT KAuth-helper based: kcm_clock.so
  (/snap/plasma-core26-desktop/current/usr/lib/x86_64-linux-gnu/qt6/
  plugins/plasma/kcms/systemsettings_qwidgets/kcm_clock.so) references
  SetTimezone/SetNTP/SetTime and carries NO org.kde.kcontrol strings;
  no org.kde.kcontrol.kcmclock.policy exists in the staged polkit
  actions. Apply is (almost certainly) direct timedated calls, gated
  on a client polkit check.

## Root cause (verified live 2026-10-29)

- The KCM (pid labelled snap.plasma-desktop-session.plasma-plasmashell)
  calls org.freedesktop.PolicyKit1.Authority.CheckAuthorization on the
  SYSTEM bus before applying. AppArmor DENIES it (journal 16:13:20 and
  repeatedly, 122 PolicyKit1 denials that boot; timestamps correlate
  exactly with the user's KCM interactions and the timedated
  activations at 16:13:36 / 16:14:51).
- The denial makes the client-side check error out; the KCM treats
  that as "cannot authenticate", never calls SetTimezone/SetTime, and
  polkitd logs NOTHING all boot (its only line is the 15:33:06 startup
  message). No prompt, no change, no error surfaced to the user.
- Root gap: NO snapd interface grants session apps polkit CLIENT
  access. Only the polkit-agent app's profile has PolicyKit1 grants
  (RegisterAuthenticationAgent side).

## Why the existing upstream `polkit` interface was not used

snapd (incl. our fork, polkit.go = unmodified upstream) HAS a polkit
interface granting {,Cancel}CheckAuthorization + Properties +
Introspect (+ RegisterAuthenticationAgentWithOptions) on the
authority. It is unusable here:
- base declaration: plugs allow-installation: false +
  deny-auto-connection: true -- declaring the plug in the session
  snap is rejected for our dangerous (locally signed) model;
- plugs require an `action-prefix` attribute AND the plug snap to
  ship meta/polkit/<plug>.*.policy files whose action IDs all match
  the prefix (validated by snapd);
- no precedent in this image family: GNOME's session snap has no
  polkit plug at all.

## Proposed fix (recommended; snapd fork, established local pattern)

New builtin interface in ubuntu-core-desktop-snapd (branch dev), e.g.
`polkit-client`, modelled on our pam-unix-chkpwd /
systemd-user-environment additions:

- AppArmorConnectedPlug grants ONLY:

      dbus (send) bus=system
        path="/org/freedesktop/PolicyKit1/Authority"
        interface="org.freedesktop.PolicyKit1.Authority"
        member="{,Cancel}CheckAuthorization" peer=(label=unconfined),
      dbus (send) ... interface="org.freedesktop.DBus.Properties"
        member="Get{,All}" peer=(label=unconfined),   [KAuth reads the
        authority's Properties.GetAll -- seen denied 2026-10-29]
      dbus (send) ... Introspect

  NO RegisterAuthenticationAgent* -- agent rights stay exclusively
  with the polkit-agent interface. NO policy-file machinery.
- Normal allow-installation (default); deny-auto-connection: true is
  fine (the gadget connects explicitly, as with all our plugs).
- Register in the builtin registry (all.go / init pattern used by
  systemd_user_environment.go) + add the usual
  <name>_test.go (test helpers enumerate the expected snippets).
- Security note for the commit message: the grant only lets a client
  ASK polkitd; authorization decisions (and the prompt) remain
  entirely with polkitd -- identical trust position to any
  unconfined desktop app.

Wiring:
- plasma-desktop-session: app-level plug on plasma-plasmashell
  (ALL KCMs run under that label -- verified: systemsettings' comm
  shows under the plasmashell profile) ; follow the app-level-only
  convention used for systemd-user-control/timezone-control.
- ubuntu-core-desktop build.sh kde_gadget_connections: add
  "polkit-client" to simple_plugs.
- Rebuild: the snapd fork (rebuild the snap) + the image build
  (`build.sh`) (session + image) so the new snapd AND the new
  plug/connection land in the image; verify `snap interface
  polkit-client` exists on the VM.

## Related latent gaps found on the way (check while in there)

1. SetTime/SetNTP are still not granted to timedated clients (snapd's
   timezone-control lacks them) -- tracked in
   `20261027-snapd-extend-timezone-control-settime-setntp.md`. Once the
   client check is unblocked, the KCM's manual-time and NTP-toggle
   applies will surface THOSE AppArmor denials next; do both together
   or expect a two-step debug.
2. ALL KAuth helper binaries are pruned from the content snap
   (find -path '*kauth*' -type f in plasma-core26-desktop: empty)
   while their polkit policy files ARE staged (powerdevil
   backlighthelper/chargethreshold/discretegpu, kcmsddm, fontinst,
   locagenhelper, kinfocenter dmidecode). Any KAuth-helper-based admin
   action will fail the same silent way even after the client check is
   granted. Inventory which of those helpers are actually needed
   (backlight? sddm theme install?) before pruning rules can be
   relaxed in the snapcraft.yaml.
3. 82->122 PolicyKit1 denials per boot are also generated by other
   session components (drkonqi? kded modules?); the client interface
   plug should probably go on more apps than plasmashell over time --
   start with plasmashell, expand by journal evidence.

## Verify (fresh image, reboot)

- Date & Time KCM: change timezone -> polkit prompt appears promptly ->
  admin password accepted -> timezone actually changes (timedatectl);
  journal shows polkitd "successfully authenticated" decision for
  unix-user:your_username, action org.freedesktop.timedate1.set-timezone.
- No NEW PolicyKit1 denials from plasma-plasmashell label
  (CheckAuthorization/GetAll must be gone).
- No timedate1 SetTimezone denial (was already granted).
- SetTime/SetNTP denials expected IF item 1 not yet done -- that is
  the documented two-step, not a regression.
- Regression: lock/unlock, login, dolphin, session restart unchanged.

## Done when

GUI admin action works end-to-end (prompt + applied change) on a fresh
image with polkit-client committed on the snapd fork dev branch, the
session snap and build.sh wired, and the image rebuilt via the image
build (`build.sh`). Update `20261015-fix-kde-boot-errors.md` item e
status at the same time.
