# Use plasma-setup for first-boot account creation on KDE images

Date: 2026-10-13

## Impact / Priority

Priority: Medium. Real end-user impact: anyone booting a fresh KDE Core
Desktop VM today must separately download/attach a cloud-init seed.iso
and gets a fixed, pre-baked username/password (no interactive account
creation) -- there is currently no way to boot a plain KDE image and
create your own account at first boot, unlike GNOME (which already has
a working no-ISO first-boot wizard flow). This blocks any "just boot
the image" distribution story for KDE. Not yet reproduced end-to-end
against a real no-user KDE boot (no such path exists yet to test); the
investigation below is from source/package inspection, not a live
test. Once a no-user image boots, re-verify the real user-visible
experience (does the wizard actually appear/work, how long does it
take, does login work afterward) rather than trusting this write-up
alone.

At the moment account creation on KDE depends on creating a seed image
and using cloud init. This is undesirable because it requires the user
to download and attach an ISO image to their VM when they boot it for
the first time. It also means that the username is hard-coded.

What I want is When the VM is built with no pre-created user, on
first-boot it should run plasma-setup (KDE KISS) And the user should
create their user account. This mirrors the existing system that we
already use for GNOME builds.

## Investigation notes (2026-10-13)

"KDE KISS" = plasma-setup's old package name ("kiss"); upstream renamed
it to "plasma-setup" (invent.kde.org/plasma/plasma-setup, "Plasma new
device setup application"). It has a packaged .deb in Neon's
unstable/resolute apt suite (origin.archive.neon.kde.org/unstable,
suite resolute, confirmed present via Packages.gz query on 2026-10-13,
version 6.8.0+p26.04+vunstable+git20261009.2007-0) -- no from-source
build needed. Deps (plasma-keyboard, plasma-nm,
kf6-kauth/kconfig/kcoreaddons/ki18n/kpackage, libkf6screen8,
plasma-workspace, qt6-base, qt6-declarative) should already be
satisfied by the existing kf6-core26/plasma-core-desktop content
snaps; plasma-keyboard/plasma-nm are not currently staged anywhere and
need adding alongside plasma-setup into the existing sddm-runtime part.

CORRECTION (2026-10-13, later same day): an earlier draft of this note
wrongly assumed sddm was already being staged from Neon's apt suite
("same apt-stage approach already used for sddm"). It was NOT: the
sddm-runtime part had no package-repositories block at all before this
work, so it resolved sddm from plain core26's default Ubuntu archive
(verified live via `apt-cache policy sddm` in the snapcraft LXD build
container: candidate 0.20.0-2ubuntu4.2 from archive.ubuntu.com, no Neon
source configured). A comment added in commit d115acf
("Neon's apt sddm package...same Neon apt suite, so the ABI matches")
was an unverified assumption that nobody had actually wired up. Since
plasma-setup/plasma-keyboard/plasma-nm genuinely are Neon-only (not in
Ubuntu's archive), fixing this required adding a top-level
`package-repositories:` block (mirroring kf6-core26/plasma-core-desktop's
existing Neon resolute config) to snap/snapcraft.yaml. Per explicit
product decision, ALL KDE packages staged by sddm-runtime (sddm,
plasma-setup, plasma-keyboard, plasma-nm) must come from Neon
consistently rather than a mix of Ubuntu's archive + Neon for
different packages -- `core26`'s own default sources also carry a
resolute archive (core26's buildd base maps to Ubuntu 26.04/resolute,
see snapcraft's BuilddBaseAlias.RESOLUTE), and sddm/plasma-keyboard/
plasma-nm exist in both, so `priority: always` (apt pin 1000) was
added to the package-repositories entry to force Neon's copies to win
for every package it carries, even when Ubuntu's own resolute archive
also ships a same-named package. Verified live post-fix via
`apt-cache policy` in a fresh build container: sddm/plasma-keyboard/
plasma-nm/plasma-setup all resolve to Neon `...+p26.04+vunstable+...`
candidates at priority 1000, beating Ubuntu's own (lower-priority)
copies. A full local snapcraft pack succeeded with this config
(produced plasma-desktop-session_20261013+gitd115acf_amd64.snap).

Separately, a stale LXD build container (created weeks earlier, still
on a noble/24.04 rootfs despite core26 now mapping to resolute/26.04)
was found and deleted so snapcraft would provision a fresh
resolute-based instance; and a KDE Neon apt-caching-proxy bug was hit
and worked around mid-session (the caching proxy conflates the
unstable/release suite editions under one cache key, since Neon's URL
layout puts the edition as the first path segment and the proxy drops
it when building its cache key). Lesson: never fetch Neon /release/
URLs through a shared caching proxy, only /unstable/, and clean any
leftover /var/lib/apt/lists/partial/*neon* state in reused build
containers before retrying a build.

How it works upstream (very different mechanism from GNOME's approach,
do not assume symmetry):
- `plasma-setup.service` (oneshot, `Before=display-manager.service`,
  `ConditionPathExists=!/etc/plasma-setup-done`) runs a small
  `plasma-setup-bootutil` helper BEFORE sddm starts at all -- it is its
  own standalone pre-login GUI/compositor session, not something
  launched from inside GDM/SDDM's own session infra the way GNOME's
  gnome-initial-setup is launched from inside GDM.
- A dedicated system user `plasma-setup` (added via
  `files/plasma-setup-sysuser.conf`, a sysusers.d fragment) runs the
  wizard; `files/plasma-setup-polkit.rules` grants it passwordless
  polkit auth for a fixed action-id allowlist (network/hostname/locale/
  keyboard/timezone config plus plasma-setup's own
  org.kde.plasmasetup.* actions: createuser, createflagfile,
  createnewuserautostarthook, removeautologin,
  setnewuserglobaltheme/displayscaling, setnewusertempautologin).
- Real account creation is done by a KAuth helper
  (src/auth/authhelper.cpp) that drops privileges via
  setegid/seteuid(PrivilegeGuard) then shells out to the plain
  `useradd`/`usermod` binaries directly (no distro abstraction) --
  this is the same class of gap documented earlier for Ubuntu Core's
  extrausers accounts: unmodified upstream `useradd` without
  `--extrausers` writes to /etc/passwd, which is NOT the account
  database Core actually consults (/var/lib/extrausers/*). Fix
  approach (not yet implemented): since this ships as a compiled
  .deb (not built from source here), patching authhelper.cpp directly
  isn't an option without a from-source rebuild; instead shadow
  `useradd`/`usermod`/etc. inside the snap's own PATH with wrapper
  scripts that inject `--extrausers` (useradd/groupadd support the
  flag directly) and handle usermod specially (no such flag exists),
  placed so the snap's env resolves them before the base's real
  binaries.
- Completion flag `/etc/plasma-setup-done` must persist across
  reboots -- /etc is a writable-path on Core (seeded at first boot
  from usr/share/factory/writable/system-data/etc, same pattern
  build.sh already uses for gdm3/custom.conf and sudoers.d), so the
  static units/config need installing into both the real path and its
  usr/share/factory/writable/system-data mirror, exactly like the
  existing gdm3 custom.conf / sudoers.d handling in build.sh.
- SDDM integration points needed: plasma-setup writes
  /etc/sddm.conf.d/99-plasma-setup.conf (temporary autologin for the
  newly created user, removed by its own
  org.kde.plasmasetup.removeautologin polkit action after first real
  login) -- build.sh's existing kde_sddm_integration() function
  already owns sddm.conf generation/Autologin handling and will need
  to cooperate with (not fight) whatever plasma-setup writes to its
  own drop-in.

Current build state (as of 2026-10-13): GNOME already fully supports a
no-`--user` image (drops `build/pc.img.nouser` instead of a seed.iso,
leaves GDM's InitialSetupEnable at its default `true` so GDM's own
initial-setup session launches the ubuntu-desktop-init wizard). KDE's
branch of build.sh (`kde_sddm_integration`) has no equivalent no-user
path at all yet -- `--user`/`--password` are optional for `--desktop
kde` at the argument-validation level already (no explicit "kde
requires --user" check), but nothing installs plasma-setup's
units/config, and the image build hardcoded `--user your_username
--password x` unconditionally for both desktops -- that needs a way to
omit --user for a KDE no-user test build too.

Proposed staged plan (do NOT do all at once -- verify each step):
1. Add a `plasma-setup-runtime` part to plasma-desktop-session's
   snapcraft.yaml staging the Neon apt .deb (plus plasma-keyboard/
   plasma-nm), isolated into its own subdir the same way sddm-runtime
   is, plus the useradd/usermod extrausers-wrapper scripts.
2. Wire build.sh to install plasma-setup's static units
   (plasma-setup.service, sysusers.d fragment, polkit rules, tmpfiles,
   plasmasetuprc) into both the real and factory/writable paths,
   conditioned on no `--user` given (mirroring the GNOME
   InitialSetupEnable conditional).
3. Make the image build's KDE case support an optional no-user
   invocation (new flag, e.g. an env var or `--no-user`, rather than
   silently dropping --user for every call) so existing user-build
   workflows are unaffected.
4. Build the snap (apt-based, no from-source compile needed -- should
   be much faster than the old SDK pipeline) and the image, then
   verify via real boot (SSH/VNC) that plasma-setup actually launches
   pre-SDDM, creates a real extrausers account, and a subsequent SDDM
   login with that account works -- do not consider this done on "the
   service is enabled" alone.
5. Only once (4) is proven end-to-end, retire the seed.iso/cloud-init
   KDE path (or keep it as an optional alternative for scripted/
   unattended builds) and update any docs referencing the old flow.

## Resolution (2026-10-30)

Done end-to-end and verified live (account created via the wizard,
password valid at greeter login, sudo group membership, wizard skipped
on second+ boots, no idle lock):

- Stages 1-4 complete. plasma-desktop-session carries the
  plasma-setup/plasma-keyboard/plasma-nm runtime (Neon resolute suite,
  priority always) under sddm/; ubuntu-core-desktop build.sh
  kde_plasma_setup_integration() installs units/sysusers/tmpfiles/
  polkit/dbus/static files into both the squashfs and the
  usr/share/factory/writable mirrors, wires the libexec wrappers with
  the content-snap Qt env, shims useradd/chpasswd for extrausers, and
  aliases plasma.desktop -> plasma-desktop-session.desktop for
  bootutil's hardcoded Session=plasma.
- Four stacked bugs found during the first end-to-end no-user boot, all
  fixed and committed:
  1. Snap layout: vs the image-baked rootfs kauth symlink aborted every
     confined Plasma app at snap-update-ns ("existing symbolic link in
     the way"): dropped the snap layout (plasma-desktop-session
     271b224), moved the symlink to the all-KDE-builds path
     (ubuntu-core-desktop df4beb0).
  2. plasmasetuprc UserGroups=wheel -> auth helper aborted between
     useradd and chpasswd, leaving a locked shadow entry
     ("your_username:!") and a correct-password login failure.
     Rewritten to UserGroups=sudo; usermod -aG lands in the pre-seeded
     writable /var/lib/extrausers/group (8b73e4b).
  3. /etc/plasma-setup-done EROFS (read-only /etc): symlinked into the
     /etc/writable bind, same pattern as sddm.conf; the helper's
     QFile::open follows symlinks (8b73e4b).
  4. Wizard-session idle lock: upstream's tmpfiles writes kscreenlockerrc
     Autolock=false only to $HOME/.config, invisible to the
     snap-confined processes whose XDG_CONFIG_HOME is snap-private;
     kwin's 5-min default timer locked the passwordless wizard. Added a
     mirror tmpfiles fragment into the snap-private config dir (2739db8).
- Stage 5 (retire seed.iso path): NOT done; --user/cloud-init remains a
  supported scripted/unattended alternative alongside the wizard, which
  matches this issue's "or keep as optional alternative" branch. If it
  is to be retired, that is a separate explicit decision.
