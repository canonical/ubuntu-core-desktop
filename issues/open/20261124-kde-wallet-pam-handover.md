# KDE wallet (Secret Service) is unwired in the image; no wallet daemon runs

## Impact / Priority

Medium (raise to High if an app is confirmed losing or
plaintexting secrets - see the missing test at the end of this paragraph).
No KDE wallet daemon runs at all on the current image, so any KDE app that
persists credentials via the Secret Service (KDE Connect pairing keys,
KMail/Akonadi accounts, Konsole profiles, Chromium's KWallet bridge, ...)
has nowhere to store or fetch them. The exact user-visible failure (error
dialog, silent "not saved", or a plaintext fallback) is NOT yet reproduced
- a single real app (or a direct org.freedesktop.secrets CreateItem) must
be tried before deciding severity. Separately, every screen lock/unlock
writes a burst of PAM errors into the journal (2x pam_kwallet5 dlopen, 1x
pam_fprintd bus EACCES, harmless pam_extrausers YESCRYPT lines, several
AppArmor AVCs) and one kscreenlocker worker is killed after the 10 s
timeout. Unlocking still succeeds (password auth completes, greeter exits,
session live), so that part is noise plus a slow/quirky unlock, not a
lockout.

Verified live 2026-11-24 on the KDE test VM (image from the image build
(`build.sh`): core26-desktop 20261124+desktop, plasma 20261124-deb,
autologin as your_username, VNC).

## 1. Live evidence (2026-11-24, boot 23:02, single lock/unlock cycle at 23:08)

    kscreenlocker_worker[15986/15987]: PAM unable to dlopen(pam_kwallet5.so):
        /usr/lib/security/pam_kwallet5.so: cannot open shared object file
    kscreenlocker_worker[15986/15987]: PAM adding faulty module: pam_kwallet5.so
    kscreenlocker_worker[15986]: pam_fprintd(kde-fingerprint:auth):
        Error with getting the bus: 13
    kscreenlocker_worker[15987]: pam_extrausers(kde:auth): unrecognized
        ENCRYPT_METHOD value [YESCRYPT]                (harmless, known)
    kscreenlocker_greet[15978]: Worker did not terminate in time, killing it.
    AVC ... profile="snap.plasma-desktop-session.plasma-kwin-wayland"
        comm="kscreenlocker_w" name="/proc/<pid>/cgroup"  denied
    AVC ... operation="bind" class="net" ... addr="@<hex>/bus/kscreenlocker_w/system"
        denied                     (sd-bus system-bus socket bind, EACCES = the 13)
    AVC ... kscreenlocker_greet: /proc/<pid>/mountinfo denied;
        org.freedesktop.login1 CanPowerOff/CanReboot/CanSuspend* denied
        (lock screen power menu inert); org.freedesktop.UPower absent

And the wallet itself is not merely locked, it is absent:

- `gdbus call --session ... org.freedesktop.DBus.ListNames | grep -i
  'secret|kwallet'` -> nothing. No org.freedesktop.secrets, no
  org.kde.kwalletd6.
- /usr/share/dbus-1/services has no wallet/secret activation files; the
  only copies (org.freedesktop.secrets.service, org.kde.kwalletd6.service,
  org.kde.secretprompter.service, ...) are in
  /snap/plasma-desktop-session/current/sddm/usr/share/dbus-1/services/,
  and the session XDG_DATA_DIRS
  (/snap/plasma-desktop-session/x1/{kf6,plasma}/usr/share:/etc/xdg:
  /var/lib/snapd/desktop) does not include that tree.

## 2. What pam_kwallet5 actually does (from the module's own strings)

It is NOT an authenticator and it does not link libpam as a client. The PAM
client is sddm (root, login) and kscreenlocker_worker (as the user, unlock);
libpam loads pam_kwallet5.so into that process alongside pam_unix /
pam_extrausers. The module only hands the already-verified password to the
wallet daemon:

    pam_sm_authenticate:
      - creates a socket under $XDG_RUNTIME_DIR (logs "final socket path: %s")
      - exports PAM_KWALLET5_LOGIN=<socket> into the PAM environment
      - forks, drops gid/uid/euid/egid to the target user, execs the
        compile-time target /usr/bin/ksecretd (formerly kwalletd)
      - skips unless XDG_SESSION_TYPE is graphical ("not a graphical session,
        skipping. Use force_run parameter to ignore this.")

session phase: pam_kwallet_init is a 149-byte shell script:

    if test -n "$PAM_KWALLET5_LOGIN" ; then
        QUOTING_STYLE=literal env -u QUOTING_STYLE | socat STDIN UNIX-CONNECT:$PAM_KWALLET5_LOGIN
    fi

wallet key material is separate: salt file kwalletd/kdewallet.salt
every line in /etc/pam.d/{kde,kde-fingerprint,kde-smartcard,sddm} is
`optional`, so any failure leaves login working and the wallet locked.

So even under root's sddm the spawned daemon runs as the user; the only
"root runs desktop code" surface is the .so itself.

## 3. Why the chain is broken - four unconnected links

(a) libpam resolves a BARE module name only against /usr/lib/security and
    /usr/lib/<triplet>/security (`%s/%s`) inside the executing process's
    rootfs (the base). It never looks under /snap. The module exists at
    /snap/plasma-core26-desktop/x1/usr/lib/<t>/security/pam_kwallet5.so.
    -> "PAM unable to dlopen", nothing runs.

(b) The module's exec target is the compile-time /usr/bin/ksecretd, which
    does not exist in the image (the binary is only in the session snap:
    sddm/usr/bin/ksecretd, plus kwalletd6). -> "could not execute kwalletd".

(c) No wallet daemon is D-Bus-activated (see section 1), so even a running
    module has nothing to hand the password to.

(d) The handover socket lives in $XDG_RUNTIME_DIR, which for every confined
    session app is the snap-private /run/user/<uid>/snap.<snap>, and any
    cross-snap path must be granted by AppArmor (resolved path - the kwin
    profile today has `"/snap/plasma-core26-desktop/x1/**" mrkix`, so a
    module in the CONTENT snap is loadable, but a socket needs its own
    grants and the pipewire-style env bridging precedent).

closest working precedents in this tree: pam_fprintd.so (base) + fprintd
snap (daemon, D-Bus), the fuse mount broker and the session environment
broker, and the udisks2/upower/pipewire provider snaps (daemon-in-a-snap,
snapd-generated bus policy).

## 4. Who should ship what (the actual decision this todo is for)

Do NOT start adding per-desktop PAM modules to core-base-desktop (KDE now,
then whatever XFCE/others need later). It does not scale, and it puts
desktop-controlled code into root's sddm process. The base already does
this once: snapcraft.yaml:529-536 stages pam_gdm.so from the gdm3 deb into
the arch-neutral /usr/lib/security (explicitly because libpam falls back
there), alongside pam_fprintd/pam_gnome_keyring/pam_systemd_loadkey.

Base should stay distro-generic. Each desktop image already installs its
own PAM service files (build.sh:737-747 copies them from
plasma-core26-desktop/usr/lib/pam.d/), so the remaining glue belongs in the
same place - kde_sddm_integration() (build.sh:629) already creates the
sddm/wayland/kwin wrappers and symlinks.

Option A (proposed default: root never loads snap-supplied code):

- copy pam_kwallet5.so (~27 KB) from the content snap into the image's
  base rootfs PAM dir at build time, root-owned and image-versioned
  (same shape as pam_gdm.so; no base repo change);
- expose /usr/bin/ksecretd from the session snap (symlink or wrapper in
  kde_sddm_integration, like /usr/lib/<t>/sddm/sddm-helper and
  /usr/bin/sddm-greeter-qt6 today);
- make the wallet's D-Bus activation reachable by the session (add the
  sddm tree to XDG_DATA_DIRS, or install the wallet service files into
  the image /usr/share/dbus-1/services + /usr/share factory seed);
- verify the socket path/grants under the confined worker.

Option B (stopgap if A is too much now): strip the pam_kwallet5 lines from
the installed /etc/pam.d copies and do not install kde-fingerprint /
kde-smartcard unless fprintd/smartcard backends are in the model. Removes
the error burst; no auto-unlock, no wallet.

Option C (durable, cross-desktop): generic image-owned PAM shim that emits
"login credential for this session" on a per-user socket, and each
desktop's own backend consumes it (ksecretd/kwalletd, gnome-keyring,
oo7). This is the daemon-plus-protocol shape already used by pam_fprintd +
fprintd and the session-brokers; it should be a small upstreamable spec,
not a repo-local invention.

Constraints if C is attempted: the endpoint must be per-user, with
SO_PEERCRED uid + AppArmor-label checks and a private socket (NOT the
session bus - other session apps must not be able to read the credential);
the plaintext must never be pushed into a system/root daemon; and the
snap-private XDG_RUNTIME_DIR needs explicit bridging (pipewire precedent).

## 5. Independent defects to fix in the same pass

- kwin profile (session snap): grant the locker worker `@{PROC}/@{pid}/cgroup
  r` (pam_systemd) and the sd-bus system-bus stream bind
  (`unix (bind,listen) type=stream addr=@...`), which should also stop the
  "Worker did not terminate in time" 10 s kill. Same class as the known
  plasma-polkit-agent /proc/<pid>/cgroup denial.
- lock screen logind CanPowerOff/CanReboot/CanSuspend* denials: power menu
  is inert. Wire the logind calls or accept it, but decide explicitly.
- fingerprint: pam_fprintd.so is in the base and /etc/pam.d/kde-fingerprint
  is installed, so the locker advertises a fingerprint authenticator, but
  the KDE model has no fprintd snap (GNOME does). Either add the fprintd
  snap + its bus rules, or stop installing kde-fingerprint/kde-smartcard.
- no UPower anywhere -> battery/suspend UI degraded (already known).
- pam_extrausers YESCRYPT warning: harmless, no action.

## 6. Verification recipe

Before a fix, on a KDE VM built with the image build (`build.sh`):

    sudo journalctl -b | grep -iE 'kscreenlocker|pam_'      (1 lock cycle)
    sudo -u <user> XDG_RUNTIME_DIR=/run/user/<uid> \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus \
        gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus --method \
        org.freedesktop.DBus.ListNames | tr ',' '\n' | grep -i 'secret|kwallet'
    tr '\0' '\n' < /proc/<plasmashell-pid>/environ | grep XDG_

After the fix, expect: no "PAM unable to dlopen"; the query above lists
org.freedesktop.secrets (and the daemon is running); a real secret round
trip succeeds - e.g. `gdbus call ... org.freedesktop.Secret.Service
CreateItem` / ReadAlias, or one KDE app that saves a credential; unlock
does not prompt for a second wallet password and does not kill the worker.
Do not trust name presence alone (kwalletd can be the ksecretd compatibility
service); confirm with an actual CreateItem/GetSecrets round trip in the
user's session bus.

Not yet done (needed to settle severity): find one real KDE app on the
image that requests a secret and record what the user sees with no
provider. KDE Connect pairing and Konsole's profile storage are the
cheapest candidates.

## 7. Adjacent, unrelated defect found in the same session (file separately)

`systemctl --user --failed` shows user-session-migration.service failed
203/EXEC: build.sh:943's kde-override points ExecStart at
/usr/bin/user-session-migration, which neither the base nor the image
installs (the only copy is in the session snap's sddm/usr/bin). Harmless
on a fresh image (nothing to migrate) but tools/test-kde-sddm.sh:93 asserts
this unit succeeds, so that check would fail on this image.
