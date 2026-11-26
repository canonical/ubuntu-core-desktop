# Replace the model base snap core26-desktop with stock core26

## Impact / Priority

PRIORITY: High — the architectural endgame of the base-split work
(direct follow-on to `20260922-split-core26-desktop-base-snap.md`).
This is architecture/maintenance debt, not a reproducible user-facing
bug: no user sees a crash from it today. What users inherit today,
measured 2026-11-05 on the live GNOME VM: the custom base costs
241,512,448 bytes packed vs 63,565,824 for stock core26 (15,223 files
vs 4,808) — roughly 178 MB compressed of extra rootfs payload in every
image download/OTA — plus a forked live-build rootfs (55 chroot hooks,
patched passwd/adduser, own chisel-releases fork) that must be kept in
sync with Debian by hand, and a model that cannot be published to the
store (see `20261103-publish-core-desktop-snaps-to-the-store.md`). The
risk side is equally concrete: PAM login, greeter account resolution,
locale selection and first-boot user creation all currently live in
the custom base, so a naive switch breaks login outright — hence the
staged, per-subsystem verification gates below. If prioritising
against other work, the honest empirical anchors are (a) the measured
178 MB packed delta (not all of it is recoverable — locales/system
daemons re-home into snaps, so expect a smaller net image reduction)
and (b) the historical count of bugs caused solely by base divergence
from Debian (e.g. the extrausers passwd/adduser patching). A base swap
also changes seed-assertion requirements, so first-boot failures after
the switch are expected until the model and gadget are re-signed
together.

## UPDATE 2026-11-05 (parallel session - chisel/chkpwd findings)

- Reassurance on the scariest risk: PASSWORD VERIFICATION IS NOT PART
  of this swap's problem. Verified live on the GNOME VM today: login
  and screen-unlock PAM conversations run in gdm-session-worker
  (uid=0, subj=gdm) via GDM's reauthentication channel, which never
  execs the chkpwd helpers; and stock core26 already ships the
  extrausers-aware machinery (common-auth with pam_extrausers + the
  lockout script, nsswitch "files extrausers", libnss_extrausers,
  pam_extrausers.so - verified in rev 750). The real PAM gaps remain
  exactly the ones inventoried below: gdm-* stack files, pam_gdm/
  pam_fprintd/pam_gnome_keyring modules, greeter userdb resolution.
- Wording fix in "Measured current state": "pam modules beyond
  libpam" overstates it - stock core26 ships the full pam-modules set
  (incl. pam_extrausers); it lacks pam_gdm, pam_fprintd,
  pam_gnome_keyring and userdb/nss-systemd.
- New re-home item (inventory B): core-base-desktop ships
  static/etc/apparmor.d/unix-chkpwd - our override ADDS
  /var/lib/extrausers/passwd and /group reads; stock core26's own
  profile grants only shadow (verified in rev 750). When the system
  rootfs becomes stock core26, re-home it via build.sh's /etc seed or
  upstream the two rules - otherwise the confined KDE session's
  unix_chkpwd (kscreenlocker path) loses extrausers NSS resolution:
  unlock still works (pam_extrausers_chkpwd runs unconfined) but
  "check pass; user unknown" journal noise returns on every unlock.
  Moot if pivotal unknown #7 drops the extrausers design.
- Sequencing prerequisite: the KDE session snap must be off the
  core26-desktop BASE before Stage E drops the model base (otherwise
  core26-desktop still needs seeding for the session). That revert
  lands separately today behind a temporary build.sh injection of a
  locally-fixed core26 - see
  `20261105-fix-core26-chkpwd-via-build-sh-and-revert-session-base.md`
  (drop condition:
  `20261105-drop-build-sh-core26-chkpwd-workaround.md`). Context:
  stock core26 stable (646) still has both chkpwd helpers setgid root
  (chisel ownership bug); candidate 750 fixed only unix_chkpwd
  (core-base #481); the extrausers helper fix is core-base #485 (open).
  Irrelevant for root-side login/unlock (see above), but if Stage E
  lands before the post-#485 rev reaches stable, build.sh's existing
  fakeroot base-customization is the natural place for the same
  two-line chown.

## Background

core26-desktop is not "a snap dependency" — it is the base declared by
the model assertions
(ubuntu-core-desktop-26-amd64.json, ubuntu-core-desktop-26-amd64-
dangerous.json, and the kde-26-amd64 variants, all line 13
"base": "core26-desktop"). The model base IS the root filesystem the
whole system runs on; every snap executes against it. (An earlier
assessment mistakenly concluded from per-snap meta/snap.yaml `base:`
fields that only the gadget consumed it — wrong; the gadget's own base
field is a separate, minor consumer, and the gadget source
snapcraft.yaml already says `base: core26`. The installed pc-desktop
x1 gadget is stale on this point and needs a rebuild regardless.)

The custom base is built by the core-base-desktop repo: a live-built
Debian rootfs shaped by ~55 hooks/*.chroot scripts + snapcraft parts,
NOT a chisel-built stock core base. Replacing it with stock core26
means re-homing everything desktop-specific it carries into:
  A. provider-snap system/user daemons (the proven 3B recipe:
     daemon-scope system/user + activates-on + gadget static
     connections + snapd-fork interface policies — udisksd, upowerd,
     pipewire/wireplumber/pipewire-pulse already work this way,
     verified live 2026-11-05);
  B. image-build-time /etc + factory seed written by
     ubuntu-core-desktop/build.sh (precedent: the polkit actions file
     already reaches the running system through the factory-writable
     /usr/share/factory/writable/system-data path);
  C. the content/session snaps (GDM's binaries ALREADY exec from
     gnome-desktop-runtime via gnome-content-launch — see below);
  D. the gadget or first-boot wizard snap (rare, case-by-case);
  E. drop as dead weight (stock core26 already provides it);
  F. escalate (genuinely needs a core26/chisel/snapd upstream change
     or a design dodge).

## Measured current state (2026-11-05, the GNOME test VM)

- Packed: core26-desktop_x1 = 241,512,448 bytes / 15,223 files;
  core26_646 = 63,565,824 bytes / 4,808 files. File delta (desktop
  minus stock): 10,161 under usr/, 102 etc/, 89 var/, 77 overlay/
  (the ucd-ppa patched passwd+adduser tree), 1 root, 1 dev.
- Stock core26 HAS: snapd-generator, dbus-daemon + launch-helper,
  libpam + /etc/pam.d/other, systemd-localed.service, polkit policy
  files + polkit.service + polkit-agent-helper units, nsswitch.conf,
  sudo, /var/lib/snapd/void, /usr/share/polkit-1/actions.
- Stock core26 LACKS (verified): systemd-userdbd socket/daemon,
  libnss_systemd.so.2, locale-gen + /usr/share/locale/locale.alias
  (only C.utf8 in /usr/lib/locale; the custom base ships a full
  pre-generated locale archive), cloud-init binary (only an /etc/cloud
  config stub), python3, glib schemas dir, polkitd binary (find
  returns nothing despite the units — chisel polkitd_services slice is
  custom-base-only), pam modules beyond libpam.
- GDM already runs from the content snap: the running gdm3 binary is
  /snap/gnome-desktop-runtime/current/usr/sbin/gdm3, exec'd via
  /usr/libexec/gnome-content-launch (base gdm.service ExecStart is
  overridden to that). gdm-session-worker and gdm-wayland-session too.
  The base retains only: unit files + overrides, /etc/gdm3,
  /etc/pam.d/gdm-*, pam_gdm.so + other PAM modules, sysusers.d/gdm3.conf,
  dbus system.d/gdm.conf, system-services org.gnome.DisplayManager.
- The repo model JSONs do NOT list pipewire or gnome-desktop-runtime;
  the image build side-loads them via `ubuntu-image snap --snap`
  (build.sh extra_snaps). Any model rework must preserve or properly
  replace that mechanism.
- build.sh re-execs itself under fakeroot to unsquashfs->edit->
  mksquashfs root-owned content into the gadget AND custom-core snaps
  (permanent design decision documented in-line — do not "simplify" the
  ubuntu-image call). The custom-core editing half of that machinery
  goes away with the custom base; audit what remains.

## Inventory of what must be re-homed (mechanism candidates)

A. Host system daemons -> provider-snap pattern (each needs a
   snapd-fork interface slot policy, gadget static connections, D-Bus
   activation via activates-on):
   - polkitd (chisel polkitd_services slice today; stock core26 has
     units/policies but NO binary). Without it, udisks2/upower
     authorization breaks. Check for an upstream polkitd snap first;
     else add to a system-provider snap. This is the highest-risk
     item — udisks2/upower mount/unmount flows depend on it.
   - accountsservice (daemon + dbus policy; GDM and the session both
     talk to it).
   - fprintd + its PAM module (see B for the PAM half).
   - boltd (also a leftover 3B item — fold together with
     colord/geoclue/rtkit/fwupd from Stage 3B where convenient).
   - provd (onboarding wizard daemon; coordinates with
     `20261103-land-ubuntu-desktop-provision-off-the-personal-fork.md`
     and ubuntu-desktop-init; whitelabel.yaml seeding in hook 002.4).
   - xdg-fuse-broker (socket-activated Go binary +
     static/usr/lib/systemd/system/xdg-fuse-broker.{socket,service};
     either a snap daemon or /etc-seeded unit + /etc-hosted binary —
     prefer snap daemon).
   - gnome-keyring: PAM-launched (deliberately excluded from dbus
     activation in 3B); decide snap-daemon vs PAM-module coupling.
B. PAM/NSS stack -> the hardest class. Host libpam dlopens modules
   from rootfs paths; a snap cannot supply them. Candidates:
   - seed /etc/pam.d/gdm-* (and ssh, sudo stacks already in stock
     core26) + module .so files into the writable /etc factory seed
     and reference modules by ABSOLUTE PATH in the stack lines
     (Linux-PAM accepts paths — VERIFY empirically; if it does, this
     unblocks pam_gdm.so, pam_fprintd.so, pam_gnome_keyring.so).
   - If absolute paths don't work: escalate (ask for a pam-modules
     chisel slice / core26 change) or redesign the flow (e.g. drop
     pam_gdm; move keyring unlock out of PAM).
   - Re-home core-base-desktop's static/etc/apparmor.d/unix-chkpwd
     override (adds /var/lib/extrausers/passwd + /group reads; stock
     core26's own profile grants only shadow) via the /etc seed or
     upstream - else the confined KDE session's unix_chkpwd loses
     extrausers NSS resolution (unlock still works; journal noise
     returns). See the UPDATE block above; moot if #7 drops
     extrausers.
   - GDM greeter account resolution: gdm-packages stages
     libnss-systemd + systemd-userdbd because the dynamic greeter
     user resolves through systemd userdb. Stock core26 has neither.
     DODGE: pre-seed static gdm user/group entries in the build-time
     /etc seed so plain nss files resolve them — then userdb/nss-
     systemd are unnecessary. VERIFY the greeter works with a static
     uid/gid (it did historically before userdb).
C. GDM host integration -> mostly build.sh /etc seed (binaries already
   come from the content snap): /etc/gdm3, gdm.service/gdm3.service
   (ExecStart override can move into the unit or a /etc drop-in),
   /etc/pam.d/gdm-* (see B), dbus system.d/gdm.conf + system-services
   (or generate via a snapd dbus slot if GDM becomes a snap app —
   heavier, not required), sysusers.d/gdm3.conf -> static passwd/group
   seeding, gdm-homedirs.service (also written by build.sh already),
   hook 005.1 gdm-getty mask -> /etc/systemd/system symlink in seed.
D. Locale data -> content snap. gnome-desktop-runtime carries the
   locale archive; session/greeter processes resolve via LOCPATH or
   the content mount (VERIFY how glibc finds compiled locales outside
   /usr/lib/locale — LOCPATH env; must reach the GDM greeter
   environment too, e.g. via the gdm.service drop-in or
   /etc/environment). locale-packages part (language packs) likewise.
E. Custom rootfs binaries/generators:
   - ubuntu-core-generator (Rust, /usr/lib/core/, five entry points:
     bootchart, bootloaders, hybrid-users, console-conf-generator,
     rtc-sys-time-init-generator). Systemd reads generators from
     /usr/lib + /run + /etc/systemd/system-generators — /etc is
     seedable, so /etc/systemd/system-generators symlinks + the binary
     itself in /etc is viable but ugly; alternatively upstream the
     still-relevant generators (bootloaders/rtc/hybrid-users look
     inherited from classic UC core bases — check which snapd already
     covers natively before moving anything).
   - /overlay (patched passwd/adduser): exists only because usermod/
     chpasswd lack --extrausers. With stock core26, REVISIT the whole
     account-storage design: stock UC keeps users in /etc/passwd; if
     the first-boot wizard + image seed can use plain /etc/passwd,
     the extrausers machinery, the ucd-ppa patch builds, and the
     /overlay runtime overlay all disappear. Trace how /overlay is
     applied at runtime first (some unit copies it — find which).
     This is likely the single biggest simplification in the whole
     item; coordinate with the wizard (ubuntu-desktop-init) and
     build.sh's cloud-init path.
F. Misc host files -> build.sh /etc seed: admin-console script +
   desktop entry (hook 002.3), motd (016), /usr/share/desktop-provision/
   whitelabel.yaml (002.4), manual-plug-connection.service +
   /usr/libexec/snap-connections.sh (993), dconf wallpaper defaults
   (dconf-init-data + glib-compile-schemas at build — VERIFY what
   still reads rootfs glib schemas now that the greeter runs from the
   content snap), plymouth ubuntu-core theme (021) — decide keep
   (kernel/initrd side or /etc?) or accept default splash.
G. Drop candidates (stock core26 already correct): snapd-files part
   (snapd-generator verified present in stock core26; verify
   tmpfiles.d/snapd.conf too), the majority of the 55 chroot hooks
   (systemd fixes, ld.so symlink/cache, alternatives, machine-id,
   os-release, nsswitch/apparmor/ssh init, python compile/move,
   perl/hwdb/pkcs11/misc cleanups, snapd tree skeleton, uids/gids,
   etc/writable design — stock core26 has its own /etc semantics,
   and build.sh's factory-seed path must be re-pointed at whatever
   stock core26 + our snapd fork actually consume; VERIFY what reads
   /usr/share/factory/writable/system-data on the current image first),
   cloud-init config hook if cloud-init is re-homed/dropped,
   ext4-conf patch, remove-slices, snap symlink, hostname/timezone
   defaults (seed instead).

## Pivotal unknowns to resolve FIRST (each gates the mechanism choice)

1. Does Linux-PAM accept absolute module paths in stack files on this
   image? (Test on the VM by temporarily pointing one seeded stack
   line at a copied .so in /etc.)
2. Where does polkitd come from on stock core26-based images — does an
   upstream/store polkitd snap exist and work with the snapd polkit
   interface + factory-seeded action files?
3. Does the GDM greeter work with a statically-seeded gdm user (no
   userdb/nss-systemd)?
4. How do compiled locales resolve from a non-rootfs path (LOCPATH)
   for BOTH the session and the GDM greeter environment?
5. What consumes /usr/share/factory/writable/system-data at boot on
   the current image, and what is the stock-core26 equivalent for
   build.sh's /etc seeding (snapd firstboot machinery? /etc/writable
   overlay?)?
6. Cloud-init plan: canonical cloud-init snap vs dropping cloud-init
   and handling --user/--password seeding via build.sh + wizard
   (decides the python3-on-rootfs question too).
7. How is /overlay applied at runtime, and can the extrausers design
   be replaced by plain /etc/passwd seeding end-to-end (wizard, sshd,
   sudo, polkit admin rules)?
8. Do any snapd-fork implicit interfaces / policies reference custom
   base paths (ImplicitOnCoreDangerous etc.) that assume core26-desktop
   content? Audit before switching.

## Staged plan (one change at a time, boot-verified each step)

Stage A: Full inventory + mechanism table.
   File-by-file delta of core26-desktop vs stock core26 (same method
   as the Stage 2.3/2.4 audits), each entry mapped to a re-homing
   mechanism from the inventory above or marked drop. Enumerate the
   full chisel SLICES array and all 55 hooks (one line each: what it
   does, still needed on stock core26?). Also do the KDE variant
   delta (plasma image) in the same pass. Deliverable: the decision
   table + the commands that produced it. Resolve pivotal unknowns
   1-8 (VERIFY tasks, VM experiments, no permanent changes).

Stage B: Provider-snap the host daemons (one per gate):
   polkitd first (it unblocks the others' verification), then
   accountsservice, fprintd, boltd (+ fold in 3B's colord/geoclue/
   rtkit/fwupd while in the pattern), provd, xdg-fuse-broker,
   gnome-keyring decision. Follow the udisks2/upower recipe exactly:
   snapd fork slot policy, gadget static connections, dbus
   activation, per-daemon confinement + denial check on a clean
   image. Remember the snapd-fork gotchas: trailing-comma AppArmor
   parser abort (stuck snapd.seeded), snap-seccomp silent syscall
   drops, stale-manager trap for live sideload installs (test seeded,
   fresh-boot).

Stage C: GDM host integration re-homing: seed /etc/gdm3,
   pam.d, dbus policy, unit files + gdm user via build.sh's /etc
   seed; switch the greeter account to the static-seeded user; move
   locales into gnome-desktop-runtime (+ greeter LOCPATH); verify
   login, logout-to-greeter, greeter restart, fingerprint and
   password paths, per the `20261001-confine-gdm.md` verification
   list.
   Do NOT change GDM confinement in the same step.

Stage D: Base skeleton + build plumbing: extrausers -> plain
   /etc/passwd decision and wizard/build.sh changes; admin-console,
   motd, whitelabel.yaml, manual-plug-connection, plymouth, dconf
   defaults; prune the snapd-files part and dead hooks; audit
   build.sh's fakeroot/unsquashfs machinery for now-unused halves;
   audit the snapd fork for custom-base assumptions.

Stage E: The switch itself: update both model JSONs (base:
   core26; drop the core26-desktop snap entry), regenerate + re-sign
   model + auto-import assertions together (base swaps change seed
   assertion requirements), point the image build's --base-snap at
   stock core26, rebuild the gadget (its source is already base:
   core26; the installed one is stale), rebuild everything, full
   verification gate (below). Land GNOME first, then repeat for the
   KDE model (SDDM host integration gets the Stage C treatment).

## Verification gate (per stage AND final)

- Same discipline as Stage 2.6 of the split issue: clean-image boot,
  confined-session /proc/<pid>/attr/current comparison, zero-new-
  denial AppArmor gate (with explicit, documented exceptions only),
  terminal/nautilus/screenshot/screencast, audio end-to-end through
  the pipewire snap (null-sink recipe), udisks2 loop-mount + upower
  query through their snaps (now via the new polkitd home), App
  Center Firefox install (polkit agent helper), LUKS unlock flow,
  first-boot wizard AND cloud-init user paths, logout -> greeter ->
  second login, admin-console, locale switching, reboot + snap
  refresh across the new base.
- Final size measurement: model base 241.5 MB -> 63.6 MB packed;
  record the net whole-image delta honestly (content snap/provider
  snaps grow by whatever re-homes into them).

## Risks / known failure modes

- A wrong character in any new interface policy aborts the whole
  seed (apparmor parser) — boot sits in snapd.seeded.
- Base swap changes seed assertion requirements — expect first-boot
  seeding failures until model/assertions are consistent.
- PAM absolute-path modules, LOCPATH, and static gdm user are
  VERIFY-first items — do not batch them with the switch.
- polkitd has no fallback: if its new home misbehaves, udisks2/upower
  authorization fails and removable-media/power flows break.
- The image builder's factory-/etc mechanism must be proven on stock
  core26 BEFORE Stage C (unknown #5) or login seeding silently
  won't land.
- Do not touch the ubuntu-image/fakeroot invocation shape documented
  in build.sh (permanent design decision).
- Keep gadget snap name matching the model — the gadget rebuild
  rides along with Stage E.

## Relationship to other issues

- `20260922-split-core26-desktop-base-snap.md`: parent effort;
  this is its de-facto Stage 4. Stage 3B/3C/3D continue independently;
  fold 3B's remaining daemons into this Stage B where convenient.
- `20261103-publish-core-desktop-snaps-to-the-store.md`: a stock-
  core26 model is the store-publishable shape; sequence store
  publication after this lands.
- `20261029-migrate-gadget-connections-to-store-gadget.md` and
  `20261104-update-all-desktop-snaps-to-core26.md`: gadget/snaps work
  overlaps Stage E.
- `20261103-land-ubuntu-desktop-provision-off-the-personal-fork.md`:
  provd snap-ification (Stage B) should land with that move.
- `20260915-app-center-installed-snaps-need-desktop-interface-connections.md`:
  documents the implicit-interface constraints this design already
  works around; unchanged by the base swap but re-verify the
  implicit-on-core slots still resolve with stock core26.

## Manager notes for dispatching steps

Stage A's delta/enumeration work is mechanical; the VERIFY
experiments 1-8 need judgement about what a result means, except where
purely mechanical. Stages B/C/D: within each, one item per
verification gate, sequential (single test VM). Stage E must come
last; GNOME before KDE. The Stage A decision table is the go/no-go
artefact — if pivotal unknowns 1/2/5 have no clean answer, STOP and
re-scope (fallback: keep a drastically slimmed custom base containing
only what has no re-homing path, and re-estimate).

## Stage A complete (2026-11-05) — GO verdict

All 8 pivotal unknowns resolved; full evidence and the consolidated
decision table (≈300 rows: every delta cluster, all 52 hooks, all 135
slice entries) were recorded with the Stage A work. Unknown
resolutions: #1 PAM absolute module paths WORK (empirically verified
incl. extrausers against the real DB; bad path hard-fails, no silent
no-op) → 4 custom-only modules /etc-seedable; #2 MOOT — stock core26
ships polkitd byte-identical (the "LACKS polkitd" inventory above was
wrong; delta is only ~10 policy actions); #3 greeter dodge WORKS —
GDM's transient gdm-greeter-* accounts resolve via files+extrausers,
userdbd is not on the greeter critical path (VM-verified, userdbd
masked); #4 LOCPATH WORKS from non-rootfs paths, propagate via
gdm.service drop-in or pam_env//etc/environment, must point at
/snap/... (private-tmp); #5 stock core26 runs the identical factory
tmpfiles machinery — build.sh /etc seed ports unchanged; #6 drop
cloud-init + the variant, factory-seed user creation; #7 /overlay is
build-time staging residue with zero runtime consumers — delete; #8
no snapd code keys on the base name but release.OnCoreDesktop depends
on VARIANT_ID=desktop from the rootfs os-release — must be preserved
via image-build seeding or home-locale-control/steam-support slots,
reboot semantics and home auto-connect all flip to plain-UC
otherwise. Also corrected vs this note's premises: stock core26 ships
the full 544-dir C.* compiled locale set (only .mo catalogs are the
delta); openssh/mdns/pwquality/mke2fs-fix are all in stock. Key
decisions taken: adopt stock Rust coreutils (drop the gnu-* pin),
target core26 >= 750 (unix_chkpwd setgid fixed there; PR #485 still
open), preserve extrausers (leaning, both options recorded in §3-3 of
the decision table). Remaining open items are listed in decision
table §4 (18 items: os-release seeding mechanism is the top one and
gates Stage C). Next: Stage B.

## Design review (2026-11-05, post-Stage-A)

An upstream-maintainer-style design review REJECTED Stage B as
specified; central claim verified against the squashfs trees — stock
core26's writable /etc is a CURATED bind-mount set (fstab +
core-writable.conf): /etc/pam.d, /etc/os-release, /etc/apparmor.d,
/etc/gdm3 are NOT seedable on stock (the custom base added those
mounts). Also: polkit action installation needs the writable
/usr/share/polkit-1 mount (custom-only); xdg-fuse-broker needs host
mount-namespace visibility (incompatible with snap-confine slave
mounts); PAM module dependency closure unproven. Full analysis +
design fork (repack vs upstream fstab change vs delivery redesign)
recorded with the Stage A work (decision table §0 and the design
review). Stage B must NOT start until the §0 design fork is decided
and Stage A.1 (rev freeze, unchanged-base provisioning proof, polkit
path resolution, daemon contracts) completes.

## Execution progress (2026-11-06): thin-variant implemented, boot-verified

Design fork resolved as "thin core26-desktop variant built from
upstream core-base machinery" (the issue's own fallback shape):
- core-base-variant worktree (branch desktop-variant/26, upstream/main
  base 224ca34): variant skeleton + fstab/writable + /etc wave + /usr
  unit-graph wave + users wave, then greeter-loop fixes (AA coreutils
  paths, GNU install shim, launch binaries, gdm dbus policy,
  AccountsService+wizard+adduser/perl+libnss_systemd baked, loader
  symlinks for the session lib closure + gbm/dri/glvnd data dirs — env
  injection impossible: gdm-wayland-session scrubs env and execs at
  absolute snap path). Variant ~72 MB packed vs fat base's 241 MB.
- ubuntu-core-desktop-base-swap worktree (branch base-swap/26):
  build.sh consumes the variant (base-snap resolution, shim guards);
  cloud-init seed.iso path REPLACED by factory-seeded extrausers
  (--user/--password works: user+sudo+ssh+home provisioning service,
  idempotent, wizard correctly suppressed).
- VERIFIED on the VM (scriptable gate): boots, seeds (59s), greeter +
  wizard, autologin user session (confined gnome-shell enforce), audio
  via pipewire snap, udisks2 root mount + user GUI-polkit-challenge
  path, upower, logout->greeter, reboot persistence. Dispositions:
  screenshot API by-design denies scriptable callers (needs
  interactive PrtSc check); wireplumber snapd.socket denial
  pre-existing non-fatal; polkitd 127 duktape SIGABRT on unix-session
  CheckAuthorization found (upstream-worthy, affects fat too).
- Corrections to earlier conclusions: libnss_systemd IS needed (the #3
  experiment masked userdbd but the NSS module itself remained present
  on the fat rootfs); the polkit-action-seeding concern from the
  design review works fine via the T1.3 writable mount + factory seed.
- REMAINING: interactive verification items (PrtSc screenshot, App
  Center/Firefox install, LUKS, locale switching); Phase 4
  provider-snap migration of temporarily-baked daemons
  (AccountsService, provd/wizard); KDE model pass; upstream
  conversations (variant into core-base, polkitd duktape bug);
  root-side artifacts in the MAIN checkout build/ were overwritten
  during this work (fat custom-core.snap rebuildable from
  core-base-desktop). desktop/26 in all repos remains untouched.

## Phase 4 progress (2026-11-07): GNOME thin-variant now fully user-verified

(wizard click-through incl. user creation, desktop, Snap Store Firefox
install, terminal, lock/unlock, fonts). Migrations completed:
- AccountsService -> provider snap (accountsservice-snap, new repo;
  snapd-fork accountsservice interface; gadget connections; variant
  payload removed; all 3 gates + live-verified confined daemon; real
  SSH login via snap-created user works).
- provd/wizard Phase A -> provd-snap (payload move, raw exec
  unconfined; Phase B confinement pending: dconf peer-label decision
  + gdm private-bus interface). Wizard fixed on thin variant (lost
  tmpfiles /run/gnome-initial-setup rule; locale1.read-only.conf
  removal; GIO_EXTRA_MODULES). Headless CreateUser round-trip
  verified.
- Variant fixes along the way: /var/lib/snapd skeleton first-boot race
  (d-lines, 6517658), polkit action files incl
  io.snapcraft.snapd.policy (2e0f566 — fixed App Center install 401),
  fontconfig /etc/fonts + conf.avail payload (d606fa4 + 83fe93a, rides
  next image build).
- Remaining Phase 4: provd Phase B, fprintd, boltd, geoclue,
  xdg-fuse-broker, gnome-keyring decision; then KDE pass;
  locale/language implementation item; upstream conversations.

## Phase 4 complete (2026-11-07): all provider-snap migrations done

- Migrated to confined provider snaps (each with fork interface,
  gadget connections, boot gates; all confined enforce, zero new
  denial classes): accountsservice, provd (Phase A payload + Phase B
  confinement incl. new gdm private-bus interface and dconf peer
  fix), fprintd, boltd, geoclue (last three on plain core26 bases).
- xdg-fuse-broker: KEPT IN VARIANT, justified — its FUSE mounts must
  originate in the host namespace to propagate to snaps; snap-confine
  slave mounts make a snap daemon architecturally impossible (recon
  recorded; revisit trigger = snapd upstream host-ns helper support).
  The variant's irreducible content is now formally: gdm host
  integration + fuse-broker + wizard/account plumbing
  (adduser/perl/chpasswd-1017, libnss_systemd) + polkit controlcenter
  actions.
- gnome-keyring: wizard's rides provd's profile; session-side
  functional per user testing.
- Cleanup (11333ec, 1b5e81a48c): duplicated fprintd/bolt polkit
  actions removed from variant (snap-delivered copies verified
  first-boot safe); fork's baseDeclSuite.TestSlotInstallation fixed
  (test-data regression — slotInstallation map missed the 4 new
  interfaces); full fork interface suite green (24 packages).
- Flags for later: provider snaps seeded beyond the model assertion
  (re-check on seed composition changes); adduser+perl possibly
  removable if confined provd no longer execs it; controlcenter
  polkit actions are variant-only host source.
- NEXT TRACKS: KDE pass; locale/language implementation; upstream
  conversations (variant into core-base, snapd host-ns helper,
  polkitd duktape, chkpwd PR #485); final size-delta measurement.

## KDE pass complete (2026-11-07)

User-verified end to end: wizard + account setup, SDDM login/logout,
screen lock/unlock (the #485 path: both chkpwd helpers setgid
root:shadow, PAM probes discriminate correctly), konsole, settings,
and `snap refresh --list`/`snap list` from the confined terminal
(fixed: systemd-user-control plug on plasma-plasmashell +
gnome-terminal-server parity — pre-existing on fat, classified (b)
shared gap). Two KDE-specific fixes landed: the greeter XKB keymap
regression (build.sh kde_sddm_integration exports
XKB_CONFIG_ROOT/XLOCALEDIR into the SDDM wrappers — thin rootfs has
no xkb-data; wizard worked because its kwin ran snap-confined with
the session snap env) and the mesa GL symlinks (dri/gbm/egl_vendor.d
→ kf6-core26; the fat base got these via gdm3's closure). #485
carried as cherry-pick fa2cc54 (droppable at next upstream sync).
Build dirs separated (build-gnome/build-kde; parallel test VMs).
Full records kept with the work.

## Final size measurement (2026-11-07)

Base 241,512,448 → 85,291,008 (GNOME) / 85,319,680 (KDE) = -64.7%.
NET GNOME delta after provd-snap slimming (T6.1, provd 179.4 MB ->
14.5 MB; root cause was the deb's Pre-Depends: gnome-initial-setup
staging the whole wizard-GUI closure behind a headless daemon):
**-118,702,080 B (-4.9%) — the thin GNOME image is 118.7 MB smaller
than fat** (was +45.4 MB pre-slim; commit 709b367 in provd-snap; all
wizard gates re-verified, zero new denial classes; trim candidate
left: gtk-3+atk insurance). NET KDE +12.66% vs fat-GNOME baseline
(cross-desktop caveat; Plasma trio ~1.93 GB dominates). OPEN
follow-ups from the measurement: (1) done — provd slimmed; (2) thin
KDE seeds no provider snaps — verified NOT a parity gap for
accountsservice/provd (KDE's plasma-setup path never used them) nor
for upower/mesa-2404/gnome-46-2404/snap-store (fat KDE model never
shipped those — GL comes from kf6-core26, no store UI by design);
the only real delta is fprintd (+bolt/geoclue for completeness) which
the fat BASE rootfs carried unconfined — add to the KDE model/wrapper
when fingerprint login on KDE matters (pam_fprintd skips gracefully
without it); (3) upstream conversations as listed above; (4)
locale/language implementation (parked; design in decision table
§4).

## Project state

The original goal (replace the 241 MB live-built custom base with
stock-core26-based content) is achieved in the thin-variant form,
user-verified on BOTH desktops, desktop/26 untouched in every repo
(work lives on desktop-variant/26 + base-swap/26 + 5 new snap repos +
session-snap worktree branches).

## Final review + fix batch (2026-11-08)

An independent-maintainer review returned "REJECT as project-complete,
RETAIN the architecture" — all five prior-review concerns verified
resolved; the architecture stands. The required fixes have since
landed and passed the integration gate: input validation (a93ed11 +
089e6fc: POSIX-name allowlist, built-tree collision checks,
stdin-piped openssl hashing with output validation — '--password
-help' is now simply hashed as data; empty/malformed hash output
aborts), wizard-runtime chpasswd hardening (fea651b),
home-provisioning hardening (f875fd9 + 64aefe1: root-only marker on
the writable /root bind, Before=gdm sddm sshd, non-empty-home skip,
symlink rejection, NSS-failure handling), regular-build isolation
restored (af62247: 995 hook variant-gated + test fixed, proven by a
full-clean vanilla pack with zero GNOME payload), PAM keyring handoff
(2907994: /usr/bin/gnome-keyring-daemon wrapper exec'ing from
gnome-desktop-runtime with the content-snap lib path —
pam_gnome_keyring embeds that path; interactive password-login test
pending), bolt resolved-sysfs write policy (ef0283ac54 + corrected
tests), and the accountsservice SetPassword record-injection guard
(333550c in accountsservice-snap; verified: injected payloads
rejected, root hash unchanged — see
`20261108-investigate-accountsservice-security-issue.md` for the
upstream investigation this spawned).

## Honest scope of "verified" (per the review's demand)

Fresh-install VM images, both desktops, user-verified core flows
(wizard, login, lock/unlock, terminal, store install, settings);
scriptable gates for audio/disks/power/logout/reboot/provisioning.
NOT established: hardware-dependent paths (thunderbolt bolt writes,
fingerprint readers, WiFi geoclue), refresh/rollback ABI
compatibility of the /snap/*/current symlink dependencies,
upgrade/migration from populated fat installs (provider state moves
to $SNAP_COMMON — fresh-install-only by design), the interactive
keyring handoff test (deferred to
`20261108-check-gnome-keyring-pam-handoff.md` — not a regression,
never tested on fat either; structural parity restored by 2907994;
bounded risk = one extra unlock prompt), and the parked
locale/language work. Upstream conversations remain open: variant
into core-base (core26-cloud-init precedent), snapd host-ns helper
for fuse-broker, polkitd duktape SIGABRT, chkpwd #485 (cherry-picked
as fa2cc54; preserve the ownership invariant when dropping), and the
accountsservice security investigation issue above.
