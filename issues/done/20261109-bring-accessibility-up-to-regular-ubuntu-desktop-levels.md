# Bring GNOME accessibility up to regular-Ubuntu-desktop parity

Date: 2026-11-09

## Impact / Priority

Priority: High. A user who is blind or has low vision gets a desktop that
assistive technology cannot see or speak, in the session AND at the login
screen. What a real user observes: toggling "Screen Reader" (quick
settings, Settings a11y panel, greeter/wizard a11y menu) flips a gsettings
key and nothing happens — no speech, no braille, Alt+Super+S is a no-op;
and even with a screen reader installed by hand, no app is readable,
because the AT-SPI bus cannot start at all. Regular Ubuntu desktop ships
Orca working out of the box (at-spi2-core is a hard Depends of
ubuntu-desktop; orca/speech-dispatcher/brltty are Recommends; gdm3 pulls
orca for the greeter), so this is a strict regression vs the product
we are replicating, not a nice-to-have.

Grounding: this impact is currently INFERRED from a static packaging audit
(no at-spi2-core/orca/speech-dispatcher/brltty in any built snap; no
org.a11y.Bus.service in any scanned dbus services dir). It has NOT been
reproduced end-to-end on a live Core image yet. The reference-vs-Core
comparison below is exactly what pins it down — per project methodology,
verify by actually using the features on both VMs (enabling the screen
reader and listening, zooming, typing on the OSK), not by journal greps.

Written 2026-11-09, after a static packaging audit of the built GNOME
snaps (gnome-desktop-runtime content snap built 2026-10-08, core26-desktop
base core.snap, ubuntu-desktop-session 20261027, model
ubuntu-core-desktop-26-amd64.json).

## Definition of parity

The same accessibility packages present AND the same features verified
working, established by comparing a regular Ubuntu desktop VM against the
Core Desktop VM feature by feature. Package presence alone is not parity.

## Work items

1. Build the reference VM: a regular Ubuntu desktop install (26.04 ISO or
   cloud image + ubuntu-desktop) under the same QEMU setup the GNOME test
   image uses. This VM is the source of truth for "what stock does"; its
   observed behaviour is the expected value for every check below.

2. Package parity diff (stock vs Core). On the stock VM, enumerate the
   a11y package set actually installed (ubuntu-desktop seed closure), at
   least: at-spi2-core, at-spi2-common, orca, speech-dispatcher (+ its
   espeak-ng backend module), brltty (+ brltty-x11), gir1.2-atspi-2.0,
   python3-speechd, the ATK bridge libs, gnome-shell OSK layouts. Diff
   against what our snaps actually stage — unsquashfs -l each built snap
   (base, content, session, and ubuntu-desktop-init) and grep for the
   packages' files. caribou is obsolete (shell OSK replaced it) — confirm
   it is genuinely absent from 26.04 too before declaring parity, don't
   just carry forward assumptions.

3. AT-SPI bus: stage at-spi2-core in the core26-desktop BASE, so
   /usr/share/dbus-1/services/org.a11y.Bus.service +
   /usr/libexec/at-spi-bus-launcher land on the host rootfs
   (<standard_session_servicedirs/> scans it — same pattern as
   ca.desrt.dconf.service). Content-snap-only placement will NOT work:
   the session dbus-daemon never scans /snap/<content>/usr/share/dbus-1/
   services. One base change serves user session, greeter, and wizard.

4. Screen reader: decide between
   (a) stage orca + speech-dispatcher + espeak-ng + brltty in the base
       (fast stock parity; base bloat; needs python3-gi + the Atspi
       typelib — Atspi-2.0.typelib already exists in the content snap,
       base needs its own), vs
   (b) upstream-aligned: port canonical/snapd#16292 (accessibility-legacy
       interface, SUPERPRIVILEGED slot + interface-dependencies mechanism)
       into our snapd fork and use a snapped Orca (sergio-costas/orca-snap
       is the reference implementation).
   (a) is the minimal first step; (b) is where upstream wants Core to go.
   Record the decision + rationale in this file's resolution notes.

5. Session-snap grants (dormant until step 3 lands): session snap apps
   declare no desktop/desktop-legacy plugs, and the AT-SPI client grants
   (bus=accessibility rules, /run/user/*/at-spi/bus*, org.a11y.Bus
   GetAddress to unconfined peers) live in snapd's desktop-legacy plug
   snippets. Give the session snap's apps those grants (plug
   desktop-legacy per app, or add fork rules) and confirm via
   apparmor="DENIED" greps that nothing needed is missing once a reader
   actually runs against the session.

6. Greeter: base unit org.gnome.SettingsDaemon.A11ySettings.service is
   ConditionGroup=!gdm, so the login screen has NO gsd-a11y-settings at
   all. Check what stock GDM does for greeter a11y (on stock, gdm3's
   orca dependency + unconfined greeter make Alt+Super+S work at login)
   and match it — a blind user must be able to log in unaided.

7. E2E verification matrix — run the SAME checks on both VMs; stock
   results are the expected values:
   - org.a11y.Bus activation: `busctl --user list | grep -i a11y`;
     `gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus
     --method org.a11y.Bus.GetAddress` returns a socket path (today it
     fails with no such name — that failure is the pre-fix baseline).
   - Process parity while a11y is active: at-spi-bus-launcher present in
     the session on both VMs; orca + speech-dispatcher running after
     enabling the screen reader on both.
   - Screen reader actually reads: enable via quick settings; flat-review
     the top bar; open gnome-terminal (GTK3) and Settings (GTK4) and have
     orca announce their widgets; Alt+Super+S toggles on/off.
   - Magnifier toggle zooms and tracks the cursor.
   - OSK opens and types into gnome-terminal.
   - High contrast / large text apply and survive reboot.
   - Sticky/slow/toggle keys show indicators.
   - Greeter: screen reader usable AT the login screen (orca launchable
     by the gdm user), magnifier + OSK on the greeter.
   - Wizard: screen reader usable during initial setup. Note the wizard
     app is Flutter (ubuntu-desktop-init) — its Linux AT-SPI support may
     be its own limitation; compare against what stock offers during
     install (live-session installer) before calling it a Core regression.
   - After enabling each feature, grep journal for apparmor="DENIED".

8. Speech-output verification path: the QEMU runs have NO -audiodev, so
   "orca speaks" cannot be verified by listening. Either add an audio
   backend to the QEMU run (-audiodev pipewire/sdl so VM audio reaches
   the host) or verify the pipeline without ears: speech-dispatcher
   connected, and a real PulseAudio stream visible in `pactl list
   sink-inputs` when orca announces something (rc=0 alone is NOT proof).
   Brlaille (brltty) cannot be exercised without hardware: parity check =
   packages present + BrlAPI up, and say so explicitly in the resolution
   notes.

9. Re-audit trigger: the model JSON lists store gnome-46-2404; local
   images use our locally built gnome-desktop-runtime content snap (the
   audit target). If the model ever resolves the store content snap, redo
   the package diff — upstream's content snap may already carry some
   at-spi2-core bits, so conclusions here are specific to our build.

## Task breakdown + progress log (manager session 2026-11-09)

Work is delegated one task per agent; the manager re-verifies claims
independently before treating anything as done. Work products are
recorded in a work log.

Task graph:
  T1  Stock baseline on the reference VM (regular26): a11y package
      census (names+versions+dpkg -L for key pkgs), expected E2E
      values (a11y bus activation, process parity), how stock GDM
      does greeter a11y (what makes Alt+Super+S work at login).
      BLOCKED on VM access credentials (asked user 2026-11-09).
  T2  Snap-side file audit (host, no VM): unsquashfs -l our built
      snaps -> file-level a11y presence report; download the 26.04
      debs for the a11y stack and produce the exact expected-file
      checklist for the base rebuild. Feeds T4/T7.
  T3  Stage at-spi2-core in core-base-desktop, rebuild, verify
      org.a11y.Bus.service + at-spi-bus-launcher + at-spi2-registryd
      in core.snap, commit. (Work item 3.)
  T4  Orca decision + implementation (work item 4). DECISION (manager
      2026-11-09): option (a) — stage orca + speech-dispatcher +
      espeak-ng + brltty(+brltty-x11) + python3-gi + Atspi typelib in
      the base. Rationale: project principle "smallest independently
      verifiable change first"; option (b) (port snapd#16292
      accessibility-legacy + snapped orca) is a large snapd port that
      should follow only after (a) proves the pipeline end to end —
      to be filed as its own follow-up issue, not lost. (b) is where
      upstream wants Core to go long-term.
  T5  Greeter a11y (work item 6), matching what stock GDM does per
      T1 findings (ConditionGroup=!gdm handling, gdm-user orca).
  T6  Session-snap AT-SPI client grants (work item 5): desktop-legacy
      plugs or fork rules for ubuntu-desktop-session apps. Prep can
      run early; verification is gated on T3 landing.
  T7  Rebuild the GNOME image (build.sh) + run the E2E matrix (work
      item 7) on the Core VM with T1's stock values as expected
      values; journal apparmor DENIED sweep; speech-output
      verification per work item 8 (pactl sink-inputs proof; add
      -audiodev to the QEMU run only if the ears-free path is
      insufficient).
  T8  Independent verification pass over T3-T6 commits + live VM
      state, by an agent that did not do the work.

Progress log:
  [2026-11-09] Manager oriented (audit findings + project docs).
  Environment: the reference VM (regular26, a manual 26.04 desktop ISO
  install) existed, not currently running; credentials unknown — asked
  the user. A Core Desktop test VM was running — ownership/usage
  asked.
  [2026-11-09] Work item 1 is effectively already satisfied: the
  reference VM image and its run setup exist and the VM ran today.
  Remaining caveat: remote access for agents.
  [2026-11-09] T2 and T3 dispatched.
  [2026-11-09] T2 DONE. All a11y daemons absent from all snaps (prior
  audit held). Key refinements: base already carries the whole
  atk/atspi CLIENT stack (only at-spi2-core was missing); T4 is bigger
  than the work item implied — base has no python interpreter binary,
  no python3-gi, no typelibs (content snap has them, base needs its
  own); espeak-ng-data is a separate 24MB package (staging espeak-ng
  alone = silent synth); caribou still EXISTS in 26.04 universe
  (0.4.21-11) — stock-seed check is T1's; chisel has no a11y daemon
  slices → stage full debs via stage-packages.
  [2026-11-09] T3 DONE + manager-verified independently (git show
  29b3468; own unsquashfs greps): at-spi2-core staged in
  core-base-desktop gdm-packages (branch desktop/26). core.snap now
  carries org.a11y.Bus.service (Exec=at-spi-bus-launcher),
  /usr/libexec/at-spi-bus-launcher, /usr/libexec/at-spi2-registryd,
  at-spi-dbus-bus.service user unit, autostart desktop file,
  accessibility.conf. Zero removals vs previous snap; +56KiB.
  E2E activation still unverified (needs rebuilt image — T7).
  [2026-11-09] User answers: the regular26 VM is SSH root with the
  usual test-VM password convention; agents work on a COPY of the
  reference image (original stays pristine); the running Core test VM
  may be used freely.
  [2026-11-09] Wave 2 dispatched: T1 (stock baseline on the regular26
  copy), T0b (pre-fix baseline capture on the running Core VM —
  addresses the "impact is INFERRED, not reproduced" caveat), T4
  (orca/speech/braille staging in base), T6 (session-snap AT-SPI
  grants prep). T5 (greeter) waits on T1's stock-GDM findings.
  [2026-11-09] T0b DONE + manager-verified (journal lines re-grepped
  live; orca deb contents checked). Pre-fix impact is now REPRODUCED,
  not inferred: org.a11y.Bus activation fails ServiceUnknown (gdbus +
  busctl, verbatim), no at-spi/orca/speech processes, screen-reader
  gsetting flips with no effect, and boot-time journal carries live
  AT-SPI failure lines from gnome-shell AND the wizard app
  (ubuntu_init). TWO AUDIT CORRECTIONS: (1) `busctl --user list |
  grep -i a11y` is NOT empty pre-fix (org.freedesktop.a11y.Manager +
  gsd's own A11ySettings name always match) — E2E expected value is
  "org.a11y.Bus APPEARS", not "empty before"; (2) gsd-a11y-settings
  DOES run in the wizard session (wizard user not in gdm group) —
  the greeter gap is gdm-specific. NEW FINDINGS: orca 50.3 deb ships
  /usr/lib/systemd/user/orca.service — gsd-a11y-settings manages
  orca via that user unit (StopUnit/DisableUnitFilesWithFlags, both
  currently AppArmor-DENIED for the session snap app, along with
  org.gnome.SessionManager RegisterClient/GetAll denials) — session
  snap needs systemd1/SessionManager grants too (relayed to T4/T6);
  session snap needs systemd1/SessionManager grants too (relayed to
  T4/T6);
  gdbus/gsettings are content-snap-only on Core — E2E recipes must
  use content-snap paths or busctl. VM identity: base 20261108+
  desktop (pre-T3), content snap 2026-10-08 (the audit target).
  VM was at the first-boot wizard (no desktop user yet) — desktop
  user-session baseline is T7 scope.
  [2026-11-09] T6 DONE + manager-verified (git show 901e17f session
  snap: desktop-legacy plugs on 11 AT-SPI-client apps; git show
  c8e74b4 gadget: connection entry in both gadget yamls; fork code
  greps confirmed). KEY FINDINGS: (1) only the snapd snap can host a
  desktop-legacy slot on Core (implicit slots live on the type-snapd
  snap), and desktop-legacy has implicitOnClassic but NOT
  implicitOnCore — so NO slot exists today; a one-line fork change
  (implicitOnCore: true, precedent: desktop_launch.go/
  systemd_user_control.go fork tags) makes it exist. (2) AUDIT
  CORRECTION: no gsd-* daemon links gtk/atspi in this build — only
  gnome-shell + the GTK3/GTK4 apps are AT-SPI clients needing the
  plug (11 apps total). (3) T0b's gsd-a11y-settings denials
  (systemd1 StopUnit/DisableUnitFilesWithFlags, SessionManager
  RegisterClient/GetAll) are NOT covered by desktop-legacy —
  separate systemd-user-control gap; the fork interface has per-tag
  extra snippets (hardcoded app SecurityTags) but none for
  gsd-a11y-settings, and its session-leader snippet grants only
  GetUnit/StartUnit/ResetFailed. TWO ONE-LINE BLOCKERS + the grants
  gap dispatched as T6b.
  [2026-11-09] T6b dispatched (snapd fork implicitOnCore one-liner,
  gsd-a11y-settings per-tag grants, build.sh connection, snapd snap
  rebuild). T5 PHASE 1 dispatched (investigation only — greeter gap
  root-cause + plan; landing waits for T4's build to clear
  core-base-desktop).
  [2026-11-09] T1 DONE + manager-verified (claims spot-checked
  against verbatim captures; orca deb contents re-checked). Stock VM
  runs as a copy of the reference image (left RUNNING at the greeter,
  autologin re-enabled for next boot — reusable for T7 stock-side
  runs; original left pristine). MAJOR PREMISE CORRECTIONS for
  26.04: (1) greeter runs as dedicated user gdm-greeter (uid 60578),
  not gdm (975, still exists) — use systemctl --user -M
  gdm-greeter@.host. (2) gsd-a11y-settings DOES run under the stock
  greeter; there is NO ConditionGroup=!gdm on stock and no dconf
  greeter config at all — our vendored override's condition is a
  purely local addition (why = T5 question). (3) gdm3 only SUGGESTS
  orca on 26.04; orca comes from ubuntu-desktop-minimal Recommends.
  (4) STOCK GREETER GOLD STANDARD: QEMU monitor sendkey
  alt-meta_l-s (Super = meta_l!) → orca + speech-dispatcher +
  sd_espeak/sd_dummy running as gdm-greeter within 12s,
  shell-internal path that does NOT flip screen-reader-enabled
  (session path: key flip drives orca-autostart.desktop
  AutostartCondition; greeter chord is separate). (5) CARIBOU
  VERDICT: absent from the stock seed — do not stage. (6) STOCK
  PACKAGE TRUTH: at-spi2-core=Depends(ubuntu-desktop), orca
  50.3/speech-dispatcher 0.12.1/brltty 6.7=Recommends; espeak-ng CLI
  NOT installed (libespeak-ng1+espeak-ng-data only — synth runs via
  the lib); brltty-x11 replaced by xbrlapi (greeter autostart
  desktop file; brltty service DISABLED on stock, no BrlAPI socket —
  work item 8's "BrlAPI up" parity bar was wrong, stock itself does
  not run it); no gnome-shell-osk-layouts package (gresource inside
  gnome-shell); pactl absent — wpctl + spd-say stream
  [paused]→[active] is the ears-free speech proof. Full
  expected-value table for every SSH-observable E2E row captured
  verbatim (report §4-5); non-SSH rows listed in §6 for VNC/human
  verification. Corrections relayed to running T4 (package set +
  autostart/socket-enablement checks).
  [2026-11-09] Design review (external, via user): distinguish a11y
  INFRASTRUCTURE (shipping the stack) from a11y EXPERIENCE
  (greeter/wizard/shell/apps actually working with AT); sharpened
  the requirement that the FIRST-BOOT WIZARD must support orca
  BEFORE any user account exists (a blind user must be able to
  complete initial setup). ACTIONS TAKEN: T5 scope extended to the
  wizard shell (same confined-shell-spawns-orca question, both
  users); T1b dispatched (static stock-ISO installer a11y analysis
  — what the stock live-session/installer offers, per work item 7's
  wizard-row comparison requirement); T7 planning updated (see
  below). Existing evidence already favourable: T0b showed the
  wizard session runs gsd-a11y-settings and the Flutter wizard app
  already ATTEMPTS the AT-SPI bus connection at boot.
  [2026-11-09] T7 SCOPE DECISIONS (recorded ahead of dispatch):
  (1) fresh-image wizard a11y is a FIRST-CLASS, first-run check
  (before any user exists): a11y menu/chord → orca + speechd up in
  the wizard session; the pre-fix "ubuntu_init: AT-SPI: Error
  retrieving accessibility bus address" journal line must disappear.
  (2) ADD a store-app check (per project compat principle): install
  a stock GNOME app snap (e.g. gnome-calculator), verify it can
  reach the a11y bus — its desktop-legacy plug must find the new
  implicitOnCore slot AND auto-connect; if it does not, that is a
  separate gap to record (app snaps' AT-SPI access depends on the
  same slot T6b creates).
  [2026-11-09] T1b DONE + manager-verified (our-side claims re-traced
  in source; stock-side evidence captured at the time). Stock 26.04
  DURING INSTALL offers near-full a11y: orca 50.1.2 / at-spi2-core
  2.60.0 / speechd / brltty / xbrlapi all in the live session;
  in-installer Accessibility page at DEFAULT STEP 2 with Screen
  Reader toggle wired to the gsettings key; Flutter GTK ATK bridge
  COMPILED INTO the installer binary (FlViewAccessible + semantics
  handler) — so Flutter a11y support is present upstream, not a
  missing feature. Stock's only installer gap: no a11y entries in
  the GRUB menu (casper access=v1/v2/v3/m1/m2 + braille=ask flags
  exist but need manual boot-param editing). OUR wizard: same
  upstream family, the SAME accessibility page at step 2; only
  wiring delta = ProvdAccessibilityService (gRPC) vs stock's
  GnomeAccessibilityService (direct gsettings). Manager traced the
  provd path in source: provd/internal/services/accessibility uses
  gio.NewSettings("org.gnome.desktop.a11y.applications") and
  EnableScreenReader sets screen-reader-enabled — the exact key
  driving orca-autostart's AutostartCondition — so the wiring is
  equivalent to stock, CONDITIONAL on provd running in the wizard
  user's session (relayed to T5: verify provd's session/user + its
  five startup schema ping-tests). Open questions needing a live
  boot (for T7): does orca read the Flutter installer end-to-end;
  does the toggle really start orca in the live session; do casper
  access= flags work manually; orca under Wayland during install;
  runtime parity of the provd backend. IMPLICATION for work item 7's
  wizard row: our wizard's a11y limitations (if any) must be judged
  against a stock installer that DOES ship the pieces — "Flutter
  AT-SPI may be its own limitation" is now known to be a runtime
  question, not a missing-compile question.
  [2026-11-09] T5 PHASE 1 DONE + manager-verified (commits a67a33c/
  db41caf shown; template.go ixr allowlist grepped; T6b commits
  confirmed). ROOT CAUSE: ConditionGroup=!gdm was added deliberately
  (a67a33c, 2026-09-22) to keep snap-run ExecStart overrides out of
  the greeter's user manager, but its rationale ("greeter keeps its
  own unconfined gsd-*") died 8 days later when db41caf removed the
  session payload from the base — today it just silently disables
  greeter a11y. Our greeter runs as gdm3's userdb-dynamic user
  (group gdm) so the condition bites. LOAD-BEARING ANSWER: the
  confined greeter shell CANNOT exec /usr/bin/orca (~70-binary ixr
  allowlist in the fork's apparmor template.go, no orca, no generic
  /usr/bin/*) — BUT the wizard shell is UNCONFINED and the shell is
  not the spawner anyway. STOCK CHORD CHAIN CORRECTED (live busctl
  trace; supersedes T1 §3's "shell-internal launch" reading — the
  "key stays false" there was an artifact of greeter dconf being
  tmpfs): chord → media-keys flips screen-reader-enabled (live state
  only) → gsd-a11y-settings Start/StopUnit +
  Enable/DisableUnitFilesWithFlags orca.service → systemd --user
  spawns orca UNCONFINED. The primary path therefore needs:
  gsd-a11y-settings at the greeter (drop condition), the systemd
  grants (T6b + EnableUnitFilesWithFlags — being added), and
  orca.service in the base (T4) — the confined-shell exec limit only
  affects gsd's fallback spawn + autostart (fixed by adding orca to
  the template allowlist).
  MANAGER DECISIONS: (M2) APPROVED both fork one-liners — add
  EnableUnitFilesWithFlags to the gsd-a11y-settings snippet, add
  /{,usr/}bin/orca ixr to apparmor/template.go (relayed to T6b).
  (M3) APPROVED the 3-unit scope only (A11ySettings, MediaKeys,
  dconf — the chord chain); the other 13 conditioned gsd units stay
  as-is (out of a11y scope). (M1) greeter/wizard AUDIO (pipewire
  deliberately skipped there today — orca would be MUTE at the
  login screen, which fails "a blind user must be able to log in
  unaided"): dispatched T9 read-only investigation to size the fix;
  if small, land before T7; if big, document + follow-up issue.
  User-session speech is unaffected (pipewire runs there). (M4)
  snap-run as the userdb-dynamic greeter user is UNVERIFIED —
  proceed, T7 verifies at the live greeter, fallback =
  wrapper-dispatch (in-tree precedent). T5 PHASE 2 (drop the
  condition from the 3 drop-ins in core-base-desktop) QUEUED behind
  T4's build (same repo).
  [2026-11-09] T9 dispatched (greeter/wizard audio investigation,
  read-only: how user session gets audio via the pipewire snap, why
  greeter/wizard skip it, what stock's greeter runs, cost to fix).
  [2026-11-09] T9 DONE + manager-verified (hook code + commit 123d36d
  shown; pipewire snap socket config read; socket redirection
  confirmed LIVE on the Core VM: /run/user/0/snap.pipewire/pipewire-0
  exists, /run/user/0/pipewire-0 does not — root's manager runs the
  daemons since it is in neither skipped group). WHY SKIPPED:
  deliberate — core-base-desktop hook 002.1 bakes 70-gdm-skip.conf
  (ConditionGroup=!gdm !gnome-initial-setup) on the three pipewire
  snap user services (123d36d, "noisy restart loop on minimal
  accounts"; the lock-file justification is stale on snapd 2.76.3).
  Stock greeter: full deb pipewire stack unconfined, globally
  enabled. FIX VERDICT: SMALL, ~30-45 lines ALL in core-base-desktop:
  (1) un-skip pipewire for the wizard unconditionally, greeter gated
  on T5-R1 (snap-run as dynamic user); (2) BONUS BUG FOUND:
  unconfined speech-dispatcher cannot reach the snap's redirected
  socket (standard-path pipewire-0 never exists) — this mute-ifies
  orca EVEN IN THE USER SESSION — fix = ~8-line
  speech-dispatcher.service.d drop-in with
  Environment=PIPEWIRE_RUNTIME_DIR=%t/snap.pipewire (libpipewire
  honors it; the landing agent must validate the env var against
  sd's actual audio backend before landing); (3) zero pipewire snap/
  gadget/fork changes. LANDING PLAN: folded into the post-T4
  core-base-desktop landing batch (with T5 phase 2's three drop-in
  edits) — one rebuild, one verification pass.
  [2026-11-09] T6b DONE + manager-verified (all four commits shown;
  snapd.snap 52781056 bytes, version 2.76.3+g56.c900c07). LANDED:
  snapd fork desktop/26 — 4f3c765ea6 desktop-legacy implicitOnCore:
  true (+StaticInfo test), 66e8b80e01 gsd-a11y-settings per-tag
  snippet (grants GetUnit/StartUnit/StopUnit/ResetFailed/
  Enable+DisableUnitFilesWithFlags on systemd1 + unit property
  reads + SessionManager RegisterClient/GetAll, all peer=unconfined
  — resolving T6's peer-label caveat; test extended; other gsd
  plugins' RegisterClient denials deliberately excluded), c900c079b9
  /{,usr/}bin/orca ixr in the apparmor template allowlist;
  ubuntu-core-desktop desktop/26 — 3e594e8 build.sh simple_plugs
  gains desktop-legacy (name-based connection; gadget snap-id entry
  from T6 preserved; repack simulated + yaml validated). Broad
  pre-fix denial sweep (44 denied sends + 9 signal/binds, 13
  members): gsd-a11y-settings showed EXACTLY the 4 T0b denials — no
  contradiction with T6; non-a11y backlog recorded in its own issue
  (`20261109-session-snap-dbus-denial-backlog.md`). snapd snap
  rebuilt clean after 4 runs (script kill + stale-version
  LXD-instance reuse, both diagnosed + documented;
  correctly-versioned final build); gocheck suites pass. CAVEATS:
  the enable-half grants (StartUnit+EnableUnitFilesWithFlags) rest
  on gsd-source/stock evidence, not live observation — T7's turn-ON
  check closes it. No session-snap change needed (gsd-a11y-settings
  already plugs systemd-user-control; connection is snap-wide via
  simple_plugs).
  [2026-11-09] T4 DONE + manager-verified (commit e8e6440 shown; snap
  listing spot-checked; orca shebang + orca.service + autostart
  condition extracted and read directly). LANDED: the full
  screen-reader stack in the base (orca, speech-dispatcher + espeak
  module, espeak-ng-data, brltty + xbrlapi — brltty-x11 correctly
  absent, espeak-ng CLI correctly absent per T1; python interpreter
  + python3-gi + 39 typelibs; orca-autostart.desktop; orca.service;
  speech-dispatcher socket enablement replicated via
  sockets.target.wants symlink; tmpfiles fragment dropped with
  rationale). Size 188.6MB -> 216.0MB (+26.15MiB, +14.5%), 0
  removals, 4659 additions. KEY FIX: orca's shebang rewritten to
  #!/usr/lib/python/python3 (hook 034 relocates the interpreter;
  without it orca could not exec at all).
  INTEGRATION ANALYSIS (manager): hook 034 moves python to a
  directory "unaccessible to snaps" (/usr/bin/python3 does not
  exist), so the template.go /usr/bin/python* ixr rule matches
  nothing — a CONFINED caller exec'ing /usr/bin/orca succeeds (T6b
  rule) but the shebang interpreter /usr/lib/python/python3 would be
  DENIED. Affected paths: only the user-session orca-autostart exec
  (confined gnome-session) and gsd's PATH-spawn fallback — BOTH are
  secondary: the primary paths (greeter chord, wizard toggle, user
  session toggle) all go gsd -> systemd StartUnit -> UNCONFINED
  orca, and the wizard session processes are unconfined (T5).
  DECISION: defer — T7 verifies orca starts in the user session; if
  the parallel gsd StartUnit does not cover it, the pre-analyzed fix
  is a NARROW per-tag interpreter ixr rule (NOT template-wide, which
  would undo hook 034's snap-isolation design). The expected
  autostart denial line is recorded for T7's journal sweep; also
  added to the denial backlog issue.
  [2026-11-09] CAVEATE ROUTED: xbrlapi's greeter autostart desktop
  file cannot land in the base (hook 002.9 symlinks /usr/share/gdm
  into the content snap) — dispatched T4b: one-file addition to
  gnome-desktop-runtime + content snap rebuild. Dispatched T5b
  landing batch (core-base-desktop): T5 phase 2's three drop-in
  condition removals + T9's pipewire un-skip (wizard + greeter) +
  speech-dispatcher PIPEWIRE_RUNTIME_DIR drop-in (env var to be
  validated against sd's actual audio backend before landing), one
  rebuild, full regression verification.
  [2026-11-09] T4b DONE + manager-verified (commit f892225 shown —
  one stage-packages entry + comment; built snap listing grepped:
  usr/share/gdm/greeter/autostart/xbrlapi.desktop present; desktop
  file byte-identical to the xbrlapi deb's sha256, verified by the
  checking agent). Content snap 372.3MB -> 370.5MB: +12 files =
  xbrlapi payload; -172 files = dpkg-family tooling, attributed to
  build-env drift in the shared snapcraft instance since the Oct 8
  reference snap (additions are monotonic; no stage-list commits in
  between). WATCH ITEM for T7: the T7 image will use this drifted
  content snap, not the audited Oct 8 one — if the image
  misbehaves, check the content snap drift first. xbrlapi binary/
  lib duplicates base payload (~286KB, inert — only the .desktop is
  consumed via the hook symlink). Commits are local-only like the
  rest; pushing origin/desktop/26 for CI is the user's call.
  [2026-11-09] T5b DONE + manager-verified (three commits shown on
  top of e8e6440; built snap extracted: A11ySettings override
  condition-free with snap-run ExecStart intact; speechd drop-in
  present; the 12 remaining 70-gdm-skip.conf entries are UNRELATED
  services (ssh-agent, ibus-portal, screencast, permission-store,
  user-session-migration) — correctly still skipped; the three
  pipewire ones are gone). Commits: 0149649 (3 greeter drop-ins —
  2 gsd + dconf; 14 gsd units untouched), c57dbc0 (pipewire un-skip
  both wizard+greeter, hook test updated), 4decc22
  (speech-dispatcher drop-in). CRITICAL CORRECTION vs T9's proposal:
  the backend validation gate proved sd 0.12.1's default
  AudioOutputMethod is PULSE (compiled default when libpulse
  present; Ubuntu build log confirms; spd_pulse.so links
  libpulse.so.0) — PIPEWIRE_RUNTIME_DIR would have been IGNORED.
  Landed Environment=PULSE_SERVER=unix:%t/snap.pipewire/pulse/native
  (socket path cross-checked against pipewire-snap's listen-stream
  and snapd's runtime-dir redirect; %t expansion confirmed). Size
  delta 0 (xz boundary). T4-class tmpfiles failure did not recur.
  CAVEATS for T7: R1 (snap-run as dynamic greeter user) now applies
  to six units (3 gsd + 3 pipewire) — shared M4 fallback; greeter
  effects are predicted, not observed (no live greeter was
  available). ALL COMPONENT SNAPS NOW LANDED — component inventory:
  base core.snap (29b3468+e8e6440+0149649+c57dbc0+4decc22), snapd
  (4f3c765ea6+66e8b80e01+c900c079b9), session snap (901e17f, STALE
  BUILD — needs rebuild), gadget (c8e74b4, STALE BUILD — needs
  rebuild), content snap (f892225, fresh), build.sh (3e594e8).
  [2026-11-09] T7a dispatched: session+gadget rebuilds, nouser+
  root-password image build, fresh-boot wizard-phase E2E (chord +
  gsettings-flip paths, a11y bus up for wizard user, speech
  pipeline, ubuntu_init AT-SPI error gone, DENIED sweep).
  [2026-11-09] T7a DONE + triage dispatched. Image build SUCCESS
  (direct build.sh with the usual wrapper values minus
  --user/--password/--autologin plus --root-password; session snap
  rebuilt to 20261109+git901e17f = HEAD; gadget rebuilt). Boot
  SUCCESS — the wizard-phase VM came up, root SSH available.
  WIZARD-PHASE VERDICTS: (a) org.a11y.Bus on wizard bus + GetAddress
  socket path PASS (pre-fix: ServiceUnknown); (b)
  at-spi-bus-launcher + registryd running PASS; (c)
  gsd-a11y-settings running, T0b's 4 denials GONE PASS (2 new
  downstream denials -> backlog); (d) pipewire trio active in
  wizard session, snap.pipewire sockets present, no restarts PASS —
  the T5b un-skip works live; (e) the pre-fix "ubuntu_init AT-SPI
  error" journal line GONE PASS; (h) SPEECH PIPELINE PROVEN
  END-TO-END: PULSE_SERVER in speechd environ,
  speechd<->snap.pipewire/pulse/native ESTABLISHED, pactl sees the
  auto_null sink + speechd clients, sink SUSPENDED->RUNNING during
  spd-say, espeak module utime grows — the T5b PULSE_SERVER fix
  works; (i) DENIED sweep: a11y chain CLEAN (0 accessibility-bus, 0
  orca exec, 0 audio-path denials; ambient backlog matches the
  known list); (j) xbrlapi.desktop wired PASS.
  ORCA SPAWN verified: systemd orca.service path, PPID=user
  manager, label UNCONFINED, cmdline "/usr/lib/python/python3
  /usr/bin/orca --replace" (T4 interpreter fix proven live).
  FAILURES TRIAGED: (f) chord alt-meta_l-s is a NO-OP in
  initial-setup mode (no journal trace) — LIKELY STOCK-EQUIVALENT
  (initial-setup mode may not bind the chord; stock's wizard chord
  was never tested live; the designed wizard path is the a11y page
  toggle — needs (g) fixed first); (g) REGRESSION: gsettings flip
  DENIED — dconf-service (confined session snap app) rejects
  ca.desrt.dconf.Writer.Change receive from unconfined peers;
  worked on the T0b stack. Blocks the wizard's own toggle + orca's
  own dconf writes. T7a-fix dispatched: profile diff old-VM vs
  new-VM (both still running — perfect bisection), attribution to
  the exact change (candidates: snapd fork profile composition or
  session snap plugs), live-patch confirmation, then land the
  source fix + rebuild the implicated snap. VM handoff: the T7a VM
  left running at the wizard with orca+speechd up (degraded-path
  spawn), key=false.
  [2026-11-10] T7a-fix DONE + manager-verified (commit 20ea9e3 shown;
  scratch profile diffs inspected). ATTRIBUTION CORRECTION
  (supersedes T7a's "regression" reading): the dconf denial was NOT
  caused by the session snap or snapd fork (both exonerated —
  profile delta has no plug/template cause; the old stack ran stock
  snapd; the fork's only template delta is the added orca rule).
  ROOT CAUSE: the T7a image build omitted the five provider snaps
  (provd, accountsservice, fprintd, bolt, geoclue) — the main
  repo's local build invocation didn't pass them (the base-swap
  worktree's nouser build and CI do) — so provd was absent, the
  provd:dbus-dconf -> ubuntu-desktop-session:dbus-dconf connection
  never happened, and snapd never generated the dconf-service
  profile's per-connection rules (the ca.desrt.dconf
  receive/send peer=(label="snap.provd.provd") block, verbatim
  identified from the old profile). PREMISE CORRECTION: T0b's "the
  flip worked" was an ARTIFACT — the old base ships no dconf GIO
  libs, so bare gsettings used the MEMORY backend (rc=0, readback
  true, no db file, zero journal lines); the unconfined-CLI dconf
  path never worked on any stack. CONFIRMATION: live-patching the
  missing rule onto the T7a VM's dconf-service profile made the
  flip succeed end-to-end (rc=0, key true, orca spawned VIA GSD
  unconfined — which also retroactively validates the gsd->
  StartUnit path), then fully reverted (md5-verified, key false,
  orca stopped, denial re-confirmed as control). TRAP recorded:
  gsettings exits 0 even when the dconf write is denied — never
  trust rc alone. LANDED: ubuntu-core-desktop desktop/26 20ea9e3 —
  build.sh require_provider_snaps() hard-fails GNOME builds missing
  any of the five provider snaps (logic unit-tested); the local
  build invocation fixed in place (untracked). No snap rebuild
  needed (no snap source changed; gadget connections bake at
  image-build time). FLAG FOR THE BASE-VARIANT DECISION: the
  main-repo base still raw-execs an UNCONFINED provd
  (launch-desktop-provision-init); the snap-routed-provd wizard
  unit exists only on the base-swap worktree base — which provd
  wiring is canonical gates the wizard-toggle path (T7b verifies
  empirically; if the unconfined-provd variant needs an extra
  unconfined-peer dconf receive rule, that is a small follow-up).
  KNOWN GAP to watch in T7b: an unconfined CLI gsettings flip may
  still be denied even with the connection in place (the generated
  rules are peer=snap.provd.provd) — stock-equivalent GUI paths
  (quick settings / Settings panel / provd) are the canonical
  flows; any CLI gap goes to the backlog issue, not the a11y fix.
  [2026-11-10] T7b DONE. IMAGE BUILDS: both pass the 20ea9e3
  provider-snaps guard with the fixed wrapper values (a wizard
  nouser variant and a user-seeded greeter-first variant; build.sh
  now seeds --user directly into extrausers, no seed.iso). PHASE 1
  wizard checks: (a) five provider snaps installed PASS; (b)
  provd:dbus-dconf -> ubuntu-desktop-session:dbus-dconf CONNECTED +
  desktop-legacy PASS; (c) the three
  peer=(label="snap.provd.provd") ca.desrt.dconf rules verbatim in
  the dconf-service profile (lines 5646/5652/5660) PASS; (d) BUT
  provd's actual wizard actor is the UNCONFINED raw-exec
  /usr/libexec/provd via launch-desktop-provision-init (main-repo
  base variant, as T7afix predicted) AND the snap-routed provd
  daemon crash-loops on gdm OpenSession/accounts-Ping/keyring
  mediation (852 denials — NEW backlog); (f) the flip on the fixed
  image: DENIED exactly per the T7afix caveat (verbatim journal
  denial captured; no live patch). => as shipped NO dconf writer on
  the image carries the snap.provd.provd label; manager decision:
  land the snap-routed-provd base variant or add an
  unconfined-peer receive rule. GREETER PHASE (image B, real
  dynamic gdm-greeter user): (g) gsd-a11y-settings + pipewire pair
  running at the greeter, a11y bus present-but-ON-DEMAND (activates
  on GetAddress), (i) speech PASS end-to-end (spd-say rc=0,
  PULSE_SERVER drop-in live, pipewire-pulse ESTAB, sink
  SUSPENDED->RUNNING); (h) GREETER CHORD SPLIT: chord→orca.service
  ACTUATED within 1s (the T4/T5b wiring works at the Core greeter)
  but orca CRASHES — first broken link: the confined greeter
  shell's wayland socket lives under
  /run/user/60578/snap.ubuntu-desktop-session/ while the
  user-manager env imported WAYLAND_DISPLAY against
  XDG_RUNTIME_DIR=/run/user/60578 → the unconfined orca.service
  finds no display → GDK keymap crash (wizard worked because its
  shell is unconfined). USER LOGIN (j): BLOCKED — three NEW
  image-level findings: (F1 P0) gnome-content-launch guard refuses
  content runtime for every non-GDM account while the shipped
  ubuntu.desktop uses the guarded alias path → "Session never
  registered" (designed path = --session-dispatch
  gnome-session-service); (F2 P1) PAM fail-open: pam_extrausers
  rejects YESCRYPT ("unrecognized ENCRYPT_METHOD") and pam_permit
  grants auth without password check; (F4 P1) the dispatched
  session stalls before gnome-shell (confined session-service can't
  see the ubuntu session definition; shell unit is
  RefuseManualStart). Matrix ran DEGRADED (t7b partial session: bus
  + at-spi on demand + pipewire trio + speechd wiring PASS;
  shell/gsd rows blocked): CLI flips rc=0-but-denied ×7 (verbatim;
  rc trap), same-snap positive control only proves keyfile
  persistence (snap run strips GIO_EXTRA_MODULES → gio keyfile
  fallback — trap documented), store app gnome-calculator installs
  + desktop-legacy AUTO-CONNECTS (implicitOnCore works), its label
  has 0 a11y denials (launch display-blocked), a11y chain denials
  0. VM handoff: the session VM left RUNNING at the greeter
  (documented state incl. the F3 ubuntu.desktop dispatch edit left
  in place); wizard VM shut down (image kept); old VMs untouched.
  [2026-11-10] MANAGER TRIAGE of T7b: (1) the two serious image
  findings F1 (P0 content-launcher guard refuses non-GDM accounts)
  and F2 (P1 SECURITY PAM fail-open — YESCRYPT rejected, pam_permit
  grants auth) + F4 (P1 session stall) are NOT a11y scope —
  recorded in their own issue
  (`20261110-image-login-findings-f1-f2-f4.md`); F2 deserves prompt
  attention. (2) DCONF DECISION (the T7b "manager decision" flag):
  land the minimal dconf receive rules for the session's
  legitimate writers — same-label (the snap's own apps:
  shell/gsd/Settings) AND unconfined-peer (provd-as-shipped, ssh
  CLI — stock parity: stock's dconf accepts any session writer) —
  via the snapd fork per-tag pattern (T6b precedent), NOT the
  snap-routed-provd base change (owned by the base-variant work;
  if that lands later the unconfined-peer grant becomes harmless
  surplus). (3) The greeter-chord orca crash (wayland runtime-dir
  mismatch) is an A11Y-CHAIN bug — the last one: fix as T7c.
  [2026-11-10] T7c dispatched (final a11y-chain fixes + re-verify):
  (1) orca wayland env fix (agent investigates: session-snap
  absolute WAYLAND_DISPLAY export vs base orca.service.d drop-in —
  evidence decides; must cover greeter AND user session); (2) the
  dconf per-tag snippet in the snapd fork + snapd snap rebuild;
  (3) re-verification: greeter chord -> orca ALIVE, wizard toggle
  via provd path, remaining user-session matrix rows on the T7b VM
  (using its documented workaround state, which is NOT a fix).
  [2026-11-10] T7c DONE. FIX 1 (greeter-chord orca crash):
  root-caused to the environment-broker (session snap's designed
  env chokepoint — journal-proven: confined gnome-session-service
  calls org.ubuntu.SessionEnvironmentBroker the same second the
  shell logs "Using Wayland display name 'wayland-0'") exporting
  the BARE name while the confined compositor's socket lives in the
  snap-private runtime dir. Rejected the base orca.service.d
  drop-in (no static %t path can cover confined AND unconfined
  compositors; the PULSE_SERVER precedent only works because the
  pipewire socket location is snapd-fixed). LANDED:
  ubuntu-desktop-session-snap desktop/26 319f0c4
  "environment-broker: absolutize the session's wayland display" —
  broker rewrites bare wayland-N to
  /run/user/<uid>/snap.<instance>/<name> (its own verified
  snap-private dir) for BOTH the user manager and dbus activation
  env; absolute values pass through; Go unit tests added.
  FIX 2 (dconf unconfined peers): profile categorization showed
  same-label writers ALREADY covered by the template's unbounded
  dbus (receive,send) peer=(label=snap.@{SNAP_INSTANCE_NAME}.*)
  rule (line 362) — landed ONLY the unconfined-peer rules,
  mirroring the generated provd block verbatim (incl. the send half
  so Notify isn't denied), hung on systemd-user-control per the
  66e8b80e01 per-tag pattern (dconf-service plugs it, connected).
  LANDED: ubuntu-core-desktop-snapd desktop/26 8cf1e13be4
  "interfaces/systemd-user-control: grant dconf-service unconfined
  peers" (+45, tests extended like the precedent). SNAP REBUILDS:
  session 20261110+git319f0c4, snapd 2.76.3+g57.8cf1e13 — GOTCHA:
  incremental snapcraft packed STALE version labels (cache-skipped
  version parts); fix = `snapcraft clean <version-part>` + repack.
  SIDELOAD (not fresh image): both snaps --dangerous on the T7b VM;
  gotchas documented (running-apps refusal needs session
  termination not gdm stop; snapd-session-agent.socket catch-22 if
  the user manager is stopped); profile regen verified (unconfined
  block at profile lines ~650). RE-VERIFICATION: GREETER CHORD PASS
  (the headline — chord at 14:11:52, orca.service started same
  second, orca alive 17min+ at handoff, label unconfined, absolute
  WAYLAND_DISPLAY in its env, at-spi registry + speech-dispatcher
  up, a11y-chain denials 0, no SIGSEGV — T7b §h's crash is fixed);
  user-session CLI flip as t7b PASSES at db level (service db
  created at flip moment, 331 B with the key, ZERO denials — T7b's
  7 denials gone) and spd-say now completes rc=0 (T7b row-5 stall
  gone); wizard VM (image COPY booted as a second VM, snapd
  sideloaded + dbus-dconf reconnect): wizard flip LANDS (db-level,
  0 denials) and wizard orca still works the unconfined way
  (relative name, standard socket — FIX 1 doesn't break the
  wizard); NEW BACKLOG for T8: the wizard/user-session
  "orca-autostart fires" follow-on is blocked by the pre-existing
  client/service dconf db split (unconfined readers see
  $HOME/.config/dconf which the confined service never writes —
  client readback false while the service db has the key; T7afix
  caveat now demonstrated end-to-end) + gsd-a11y-settings
  mid-session non-reaction (suspect the T7b row-8
  GIO_EXTRA_MODULES/keyfile trap inside snap run). VM handoff: the
  session VM left RUNNING, sideloaded snaps x2, greeter orca alive,
  F3 edit intact/untouched, old revisions kept (revert possible);
  wizard VM powered off (image copy kept); old VMs untouched.
  Reboot persistence of the sideloads not exercised (deliberately)
  — fresh-image run recommended for T8.
  [2026-11-10] T8 INDEPENDENT VERIFICATION DONE. 15 commits audited:
  15/15 diff-matches-claim, 15/15 message quality, 0 out-of-scope
  touches, 0 FAIL. VM scope-discipline CLEAN (inventory
  byte-matches, F3 workaround as documented, both reference VMs
  confirmed untouched). Chord independently reproduced OFF and ON
  (clean stop, clean 1s start, 0 denials both windows). 6/6
  sampled claims HOLD (stock chord, T4 snap contents, T5
  archaeology, T6 slot-provider lines, T1b FlViewAccessible, T9
  stock greeter pipewire). Todo log accurate. ONE REAL
  DISCREPANCY (D1): the five core-base-desktop a11y commits (+3
  siblings) sit on local desktop/26-fat, which has DIVERGED from
  desktop/26 (8 commits apart on each side; merge-base b9796f2;
  desktop/26 carries arm64/CI/keyring/Plasma work not on fat) —
  before any push/CI the branches need a deliberate merge decision,
  which belongs to the fat/thin variant work, NOT this issue. The
  commits are safe locally.

## RESOLUTION NOTES (2026-11-10) — state of the issue at T8

Work items vs outcome:
  Item 1 (reference VM): DONE pre-existing (regular26); T1 captured
  the stock baseline + gold-standard greeter chord evidence on a
  copy; T1b covered the installer side from the ISO.
  Item 2 (package parity diff): DONE (T2 + T1): all a11y daemons
  were absent from every snap; stock set enumerated; caribou
  confirmed absent from the stock seed (do not stage); espeak-ng
  CLI / brltty-x11 not in the stock set (lib+data / xbrlapi
  instead); OSK layouts are a gnome-shell gresource.
  Item 3 (at-spi2-core in base): DONE — 29b3468 (T3); bus
  activation verified live (T7a/T7b: org.a11y.Bus + GetAddress work
  in wizard, greeter and user sessions; the pre-fix ServiceUnknown
  symptom reproduced in T0b, gone post-fix).
  Item 4 (screen reader stack): DONE via option (a) — e8e6440 (T4):
  orca + speech-dispatcher(+espeak module +data) + brltty+xbrlapi +
  python/gi/39 typelibs; orca.service + autostart + socket
  enablement replicated; relocated-interpreter shebang fix; snapd
  orca exec allowlist (c900c079b9). Option (b) (snapd#16292
  accessibility-legacy port) remains the upstream-aligned follow-up
  — file it as its own issue when pursued.
  Item 5 (session-snap grants): DONE — 901e17f (11 apps), c8e74b4 +
  3e594e8 (wiring), 4f3c765ea6 (implicitOnCore — store-app
  auto-connect verified with gnome-calculator, 0 a11y denials),
  66e8b80e01 + 8cf1e13be4 (gsd-a11y-settings + dconf-service
  grants).
  Item 6 (greeter): DONE — 0149649 (chord-chain units at the
  greeter), c57dbc0 (pipewire at greeter/wizard), 4decc22
  (PULSE_SERVER for speechd), 319f0c4 (absolute wayland env).
  Greeter chord reproduces end-to-end (broken in T7b, fixed in
  T7c, independently reproduced both directions in T8).
  Item 7 (E2E matrix): MOSTLY PASS on Core — bus/GetAddress,
  process parity, chord+toggle activation, speech pipeline (ears-
  free proof), store app: PASS. Wizard: provider/wiring checks
  PASS; interactive Flutter-toggle usability = human verification.
  NOT yet verified: user-session GUI rows (gated by the
  out-of-scope F1/F2/F4 login bugs — see
  `20261110-image-login-findings-f1-f2-f4.md`), fresh-image bake of
  the two sideloaded fixes, reboot persistence, magnifier/OSK
  visual rows (SSH-unobservable by nature — T1 §6).
  Item 8 (speech verification path): DONE — ears-free proof
  established (PULSE_SERVER + pipewire-pulse ESTAB + sink
  SUSPENDED->RUNNING + spd-say + espeak utime); -audiodev NOT
  needed; braille parity = packages + xbrlapi greeter autostart
  (stock itself does not run brltty — the original "BrlAPI up" bar
  was wrong).
  Item 9 (re-audit trigger): STILL OPEN (conditional on the model
  resolving the store content snap).

Residual work before this issue can close:
  1. Fresh image with the T7c snaps baked (session 319f0c4, snapd
     8cf1e13be4) + one reboot-persistence pass of the a11y rows.
  2. F1/F2/F4 login bugs fixed (their own issue) -> then the
     user-session GUI rows of the matrix (quick-settings toggle,
     Settings panel, orca actually reading GUI apps, magnifier/
     OSK visuals) — ideally with a human/VNC pass.
  3. D1 RESOLUTION (user decision 2026-11-10): the a11y work belongs
     on desktop/26 (NOT a merge of desktop/26-fat — that line is
     legacy-layout; desktop/26 is the restructured variants/ line).
     The five a11y changes are being PORTED onto desktop/26 with
     path adaptation; desktop/26-fat stays untouched/unpushed as
     the historical record. Post-port: base snap rebuild from
     desktop/26 + full built-snap a11y checklist; fresh-image E2E
     (residual item 1) will then run against the desktop/26 build.
  [2026-11-10] T10 DONE. OUTCOME: only the 3 config-level commits
  port to desktop/26 — d5dd37e (greeter de-conditioning,
  variants/desktop/static/paths), f622a7d (pipewire un-skip: the
  skip is static drop-in FILES there, deleted + test), a43f5c2
  (speechd PULSE_SERVER drop-in, byte-identical). ALL VERIFIED in
  the rebuilt snap (zero collateral changes; build from
  confirmed-checked-out desktop/26; tools/build-variant.sh desktop
  used since the repo's default snap build builds the cloud-init
  variant). THE STRUCTURAL FINDING: the 2 packaging commits CANNOT
  port — desktop/26 is the THIN variant line: chisel-only rootfs
  closure, the gdm-packages stage-packages part removed BY DESIGN,
  chisel-ubuntu-core 26.04 has no slices for
  at-spi2-core/orca/speech-dispatcher/brltty/python3-gi/espeak-ng
  (404-verified), vendored ELFs rejected. I.e. the verified a11y
  stack is a FAT-LINE artifact; the E2E-proven images are fat-base
  + other repos' desktop/26 snaps. T10 also performed workspace
  hygiene (git-invisible empty dirs removed, 128 setgid dirs + 2
  drift files normalized — other worktrees may carry the same
  drift; hook-test 020 was failing on it). USER DECISION PENDING
  -> a11y-on-thin architecture question dispatched for an external
  design review (T11): the user's instinct is snaps-not-chisel (the
  thin direction is "payload into snaps"), with the org.a11y.Bus
  activation-chain question (base cannot carry the service file on
  a future stock core26 base) as the crux; upstream signal =
  snapd#16292 accessibility-legacy + sergio-costas/orca-snap
  (snapped orca) + snapd user daemons. Fat-line work stays
  verified and parked until the design lands.
  [2026-11-10] T11 DESIGN REVIEW DONE (external review; saved
  verbatim in the work log). VERDICT: APPROVE a snapped a11y
  provider as the target; REJECT "snap orca + port the grants" as
  a complete plan — the real work is a provider/client SECURITY
  CONTRACT, not package placement. KEY FINDINGS: (1) no structural
  blocker to snapped org.a11y.Bus activation — snapd's dbus
  interface + app `activates-on` generates the service file under
  /var/lib/snapd/dbus-1/services (validate.go + wrappers/dbus.go +
  snapd.session-services.conf cited); the private accessibility
  bus is NOT a snapd dbus slot (session/system only) and needs its
  own confined contract. (2) Recommended shape: ONE strictly
  confined, image-seeded ubuntu-desktop-a11y snap on stock core26
  with apps bus/orca/speech-dispatcher (+xbrlapi client); keep
  PipeWire separate; braille hardware = separate privilege domain,
  follow-up gate. (3) Orca lifecycle: snapd user daemon for the
  orca process, gsd-a11y-settings as actuator targeting
  snap.ubuntu-desktop-a11y.orca.service, GNOME setting stays the
  preference authority; temporary compat adapter (a unit invoking
  snap run) acceptable with an explicit removal plan. (4) Upstream:
  #16292 is draft/unmerged and its reference orca snap does NOT
  provide the bus (its launcher restores host XDG_RUNTIME_DIR) —
  extend its scope (bus ownership, confined private bus, relocated
  socket, Core connection policy) rather than assuming it covers
  us; do NOT upstream the per-tag dconf grants as long-term API;
  implicitOnCore alone is insufficient (peer labels change when
  the provider is confined). (5) Migration: reuse the grants
  plumbing/broker fix/provider guard/de-conditioning; retire base
  staging + host python/shebang + template orca exec once snapped
  paths own the work; intermediate step = snapped orca/speech
  against the fat host bus BEFORE switching bus ownership; never
  two providers competing in one session. (6) EIGHT BLOCKING
  GATES before production commitment (confined-bus prototype,
  store-app actual reading, dynamic greeter, wizard before
  account creation, settings coherence incl. db split, lifecycle
  refresh/revert, UID isolation, hardware/human). (7) FALLBACK if
  the confined bus proves structurally impossible: thin custom
  base + NEW chisel slices for at-spi ONLY, orca/speech snapped.
  BOTTOM LINE: time-boxed confined-provider spike, coordinated
  with #16292 — activation path exists today; the confined
  private bus + compat/lifecycle are what need proof.
  4. The client/service dconf db split + gsd-a11y GIO_EXTRA_MODULES
     keyfile fallback (T7c notes) — logged backlog.
  5. Base-variant decision (raw-exec vs snap-routed provd) — gates
     the provd-path cleanup; the unconfined-peer dconf grant is
     harmless surplus if provd goes confined later.
  6. Follow-up issues spawned:
     `20261110-image-login-findings-f1-f2-f4.md`;
     `20261109-session-snap-dbus-denial-backlog.md`.

All deliverables recorded in the work log (T0b, T1, T1b, T2, T3, T4,
T4b, T5, T5b, T6, T6b, T7a, T7afix, T7b, T7c, T8, T9).
  [2026-11-16] STATUS: the fat-line work above is FROZEN as the
  verified reference (the owner's direction: the thin line is the
  target). The current accessibility state lives in
  `20261110-thin-line-a11y-snapped-provider-spike.md` — read its
  [2026-11-16] handover-status section first if resuming: gates 1-7
  PASS on the thin line (the display, audio, greeter, and handshake
  all verified on a baked image), gate 8 (human testing) is the
  next step, and the remaining work is the shipping checklist (the
  9 T29 before-shipping items) plus the follow-ups listed there. A
  separate QEMU display-freeze investigation was CLOSED as
  misattributed (the freeze was our a11y stack's Xwayland wedge,
  fixed by T34/T35's session snap).
  [2026-11-20] CLOSED — the a11y parity work is COMPLETE: the
  fat-line reference above is frozen and verified; the thin-line
  implementation (the snapped a11y provider) was built through the
  spike issue's T12-T60 arc, verified end-to-end (gates 1-8, the
  zero-to-speaking chain including the automatic greeter speech),
  and PUSHED (all five repos, desktop/26, the Nov 20 push record in
  the spike issue). This issue's residual list is resolved or
  superseded: item 9's re-audit trigger remains conditional (until
  the model resolves the store content snap) and rides in the
  spike issue.
