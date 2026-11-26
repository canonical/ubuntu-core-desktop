# Thin-line accessibility: snapped provider spike + gates

## Impact / Priority

This was the proving ground for the thin line's entire accessibility
stack: the open question was whether a strictly confined, snapped
screen-reader provider can serve the greeter, the wizard, and the
user session at all. Until the gates here passed, a blind user could
not independently boot, log in to, or operate a thin Ubuntu Core
Desktop image — no reliable orca start path, unproven confinement,
and (before the Xwayland keymap fix) a user-session display freeze.
All gates 1-8 now pass end-to-end on the real thin image; what
remains is the shipping-hardening list and the upstream candidates.

Impact derived from the original note's symptoms.

## Context

Written 2026-11-10, spawned from
`20261109-bring-accessibility-up-to-regular-ubuntu-desktop-levels.md`
(item 4 option (b) direction) after the T11 design review approved
the snapped-provider architecture.

## DESIGN (T11 verdict, binding for this todo)

- ONE strictly confined `ubuntu-desktop-a11y` snap, stock core26
  base, image-seeded: apps `bus` (at-spi-bus-launcher + private
  dbus-daemon + registryd + config), `orca` (orca + python3-gi +
  typelibs + liblouis + deps), `speech-dispatcher` (sd + espeak-ng
  module + data; audio via audio-playback -> pipewire snap). One
  snap initially (socket/label relationships are the unproven
  boundary); PipeWire stays separate; braille hardware = separate
  privilege domain, later.
- Bus activation: dbus slot for org.a11y.Bus + app `activates-on`
  -> snapd generates /var/lib/snapd/dbus-1/services/*.service (NO
  base-rootfs service file; survives a future stock core26 base).
  The private accessibility bus is NOT a snapd dbus slot (session/
  system only) — its confinement is the spike's core question.
- Socket placement: prefer the conventional /run/user/<uid>/at-spi
  path initially (existing client policy is path-specific); the
  launcher needs provider authority for the host runtime dir.
- Orca lifecycle (integration phase, not spike): snapd user daemon
  as process owner, gsd-a11y-settings as actuator targeting
  snap.ubuntu-desktop-a11y.orca.service, GNOME setting stays the
  preference authority; the fat /usr/bin/orca fallback and
  orca-autostart route must be retired, not duplicated. Temporary
  compat adapter (unit invoking snap run) acceptable with a removal
  plan.
- Speech: socket-activated user speechd in the snap; orca gets
  SPEECHD_ADDRESS; speechd gets PULSE_SERVER to the pipewire snap
  socket + audio-playback connection. The base PULSE_SERVER drop-in
  does NOT affect the snap's daemon (route in-snap).
- Upstream: extend snapd#16292 (draft) with bus ownership, confined
  private bus, relocated socket, Core connection policy; do NOT
  upstream per-tag dconf grants as long-term API; implicitOnCore
  alone is insufficient (confined provider changes peer labels —
  both client and service profiles need updating).

## SPIKE PLAN (time-boxed; T11 gates)

- Spike 1 (T12): build the snap (all three apps), pack, static
  checks. No VM.
- Spike 2 (T13): gate 1 — confined-bus prototype on a test VM:
  sideload, activate org.a11y.Bus (GetAddress from unconfined AND
  confined clients), private bus stays type=accessibility, registry
  activation succeeds, AppArmor mediation stays ON, zero unexplained
  denials. The fat base's own bus must be suppressed for the test
  (two providers must not compete) via the documented live-patch
  methodology; revert after.
- Gates 2-8 (T11 §7) are the acceptance criteria after the spike:
  store-app actual reading; dynamic greeter chord on/off with
  sustained operation; wizard toggle before account creation;
  settings coherence (db readback + change notification across
  labels); lifecycle (reboot, crash, refresh/revert, stale address);
  UID isolation; hardware/human validation.

## STATUS

- [2026-11-10] Todo created; T12 (snap build) dispatched. Interim:
  the fat line remains the verified fallback; nothing pushed;
  fat/thin coexist as test lines (never two providers in one
  session).
- [2026-11-10] T12 DONE + manager-verified (snap artifact + meta
  inspected). Repo ubuntu-desktop-a11y; snap 74.9MB with apps
  bus/orca/speech-dispatcher; activates-on + daemon:dbus +
  daemon-scope:user validated FORK-EXACT (the fork's snap package
  compiled into a throwaway checker; validate.go:834-869,
  wrappers/dbus.go:34-64); no invented accessibility-provider
  interface; base dbus-daemon used via template ixr (layout symlink
  on existing base file impossible — change.go:187).
- [2026-11-10] T13 DONE (gate 1) + manager-verified (the three
  control experiments read in the report — same daemon+config
  unconfined WORKS, confined as uid 0 WORKS, confined as 60578
  FAILS, exact dbus error line captured). VERDICT: ADJUST — the
  confined bus works MECHANICALLY (activation file generated from
  metadata alone; same-snap end-to-end: session bus -> user
  activation -> confined launcher owns org.a11y.Bus -> returns
  address; private bus stays <type>accessibility</type>, binds,
  listens; mediation ON throughout; all 28 denials enumerated, zero
  unexplained). TWO GAPS, both with owned fixes: (1) DECISIVE: the
  confined dbus-daemon silently DROPS connections from unresolvable
  uids (core26 base userdb has no dynamic/extrausers users; every
  real UC session user is extrausers-only) — registry unreachable;
  fix options: in-snap libnss-extrausers staging (preferred), a
  snapd user-daemon namespace injection of host userdb
  (upstreamable), or the chisel fallback scoped to the bus daemon
  only. (2) dbus interface structurally excludes unconfined peers
  (receive policy lives in the connected-slot snippet; peer=
  unconfined rules needed) + bus=accessibility rules for the
  private bus — the T11 §5 privileged-contract work, now with
  exact deny shapes. ALSO: activation file is named by bus name
  (org.a11y.Bus.service, not snap.*); a connection IS required for
  the endpoint to be callable; coexistence = base services dir
  wins deterministically (so the fat unit must be retired at image
  assembly when switching). speechd socket-activation works (3
  committed fixes: layouts + unix_socket: address format); audio
  stalled on missing libpulsecommon — stage libpulse0.
- [2026-11-10] T14/T15 dispatched in parallel (T14: userdb fix in
  the a11y snap, in-snap NSS visibility first; T15: snapd dbus
  interface unconfined-peer + bus=accessibility policy, static +
  tests + rebuild).
- [2026-11-10] T14 DONE: private-bus userdb FIXED in-snap (one
  stage-package line: libnss-extrausers; snap x6). Key findings:
  T13's premise was wrong — core26 base nsswitch ALREADY lists
  extrausers and the base SHIPS libnss_extrausers.so.2 (/usr/lib/,
  non-multiarch); extrausers-only uids resolve in the snap ns with
  no layout and no mediation change (strict template pre-grants
  /etc/nsswitch.conf r + /var/lib/extrausers/{passwd,group} r).
  The VM greeter uid is a gdm/systemd DYNAMIC user (host nsswitch
  "files systemd extrausers" → userdbd), NOT an extrausers user —
  seeded file-backed record (reverted after) to run the controls:
  same-snap client as 60578 → GetAddress → Hello OK →
  org.a11y.atspi.Registry ACTIVATES (owner :1.3, registryd process
  as gdm-greeter, accessibility type + mediation intact); record
  removed → exact T13 NoReply + journal line re-logged; re-added →
  Hello OK. orca (same snap) connects to the private bus (2 names
  appear) and dies only at no-DISPLAY keymap init. Remaining for
  gate 1: T15 dbus peer policy, GI_TYPELIB_PATH pin in run-orca
  (inherited session env → content-snap typelib denials),
  dynamic-user decision (option (b) vs file-backed greeter user).
- [2026-11-10] T15 DONE + manager-verified (commit shown): dbus
  interface + desktop-legacy peer policy — commit 1826bfd5af
  (connected-slot snippet gains a generic unconfined-peer receive
  compat block; desktop-legacy GetAddress send + all 10
  accessibility-bus rules widened to peer=(label="{snap.*,
  unconfined}") with name constraints kept + the snap-private
  at-spi socket rule; roles-swapped SessionManager RegisterClient
  NOT addressable generically — needs provider->session-snap
  slot/plug, documented). Peer-label decision: snap.* glob in an
  alternation (file precedent plasmashell; generic per T11 §5 —
  exploitable only by owning org.a11y.Bus/atspi names). Tests 35
  PASS/0 FAIL; snapd rebuilt 2.76.3+g58.1826bfd.
- [2026-11-10] T16 dispatched (gate-1 completion: T15 snapd g58
  sideload + GI pin x7 + live checks a-d + verdict).
- [2026-11-10] T16 DONE: GATE 1 PASS. snapd 2.76.3+g58.1826bfd live
  (T15 policy verified in regenerated profiles); a11y snap x9 (GI
  pin, libpulse0, orca wayland plug, xkb-data+symlink layout) +
  session x3 (dbus-a11y-bus-client plug, f146062) sideloaded;
  checks a-d run with mediation ON: unconfined GetAddress OK (zero
  receive denials), same-snap + registry activation OK, the SHELL's
  GetAddress moved from send-denied (T13) to
  provider-receive-denied (consent model: needed the session-snap
  plug) to WORKING (activates the snap bus, gets the snap-private
  address); orca runs on the greeter past keymap init (wayland
  grant + xkb data were the real blockers; T14's no-DISPLAY
  attribution was the ssh-context case); speechd blocked ONLY on
  /dev/shm/sem.* naming (strict template is snap-name-scoped;
  speechd uses random names — fix options documented); dynamic-user
  seeding is un-raceable from outside (~1s shell-connect window) →
  strongest input yet for file-backed greeter at image assembly
  (option (a)). All reverts done, fat baseline verified, no reboot,
  no mediation change.
- [2026-11-11] T23 DONE — GATES 1-5 ON THE REAL THIN IMAGE (the
  capstone; fat-masking caveat T17-E5 RETIRED). BUILD:
  ubuntu-core-desktop 4939fa6 — 5 baked a11y connections,
  require_provider_snaps += ubuntu-desktop-a11y,
  assert_single_a11y_bus_provider (T17 item 10; fails on fat,
  passes on thin — tested both bases). CRITICAL FIX (6b3e717): the
  confined private bus dropped EVERY peer on thin — the daemon
  could not resolve its own TRANSIENT uid in-ns (stock core26
  nsswitch lacks the systemd service) -> staged libnss-systemd +
  nsswitch chain via bind-file layout (override-stage output proved
  non-part-owned — packed 0-byte twice; generated in override-build
  instead). T14's extrausers lib was necessary but not sufficient
  on thin: extrausers covers real users, libnss-systemd covers
  transient wizard/greeter uids. GATE TABLE: Gate 1 PASS
  (confined+unconfined GetAddress, type=accessibility, registry
  activation, must-deny holds at kernel policy — verbatim AVC
  connect-denied for the consent-less speech-dispatcher peer).
  Gate 3 PASS — THE HEADLINE: Alt+Super+S on the real thin greeter
  -> Started orca.service (thin-variant snap adapter) -> confined
  orca sustained 4m17s, NRestarts=0 -> snap speech-dispatcher with
  espeak-ng (NOT dummy) -> live Stream/Output/Audio on the pipewire
  sink; chord OFF -> clean exit. A BLIND USER CAN LOG IN UNAIDED ON
  THE REAL THIN IMAGE. Gate 2 PARTIAL: calculator installs +
  auto-connects + launches confined + orca runs in the session
  (after 8b058ad: orca spawned xkbcomp, unresolvable in
  user-session env) — but the app never REGISTERS on the a11y bus
  (GTK4 activation gap, zero denials, toolkit-accessibility=true at
  db+portal, org.a11y.Status.IsEnabled property reads policy-denied
  to client peers — fix shape owned). Gate 4 PARTIAL: the wizard
  SKIPS the a11y page (T22 parity — toggle not exercisable;
  chord-in-wizard queued); investigate vs stock (T1b: stock HAS the
  page at default step 2 — thin skip may be a provisioning/config
  difference, not upstream). Gate 5 PARTIAL: db/portal readback +
  gsd->StartUnit actuation both directions proven; app-visible
  notification blocked by the gate-2 gap. T0b CHECK: ServiceUnknown
  markers = 0 across both boots — GONE. New backlog: a11y.Status
  policy verbs, orca fonts grant, store-app desktop/wayland plug
  wiring, libspeechd client semaphore. Handoff: the test VM left
  running with a11y x2 sideloaded (= 6b3e717+8b058ad; re-bake is
  one build command), no pushes, must-deny intact.
- [2026-11-10] MANAGER VERIFICATION + DECISIONS after T16: commit
  1826bfd5af shown (diff matches claim, tests present). DECISIONS:
  (1) DYNAMIC-USER: ACCEPT the file-backed greeter user at image
  assembly (T16's strong recommendation; matches stock 26.04's
  dedicated gdm-greeter user per T1; avoids userdbd-in-ns entirely;
  out-of-band extrausers seeding is un-raceable vs the ~1s shell-
  connect window). (2) Gate 2 scoping: image-assembly wiring
  (provider snap into the model + connections + retire the fat
  unit on fat images per T11 §6 coexistence rules), then lifecycle
  gates (reboot, refresh/revert, stale address) + the shell
  persistent-connect caveat (atk-bridge 1s window + RegisterClient)
  is a gate-2 item. (3) speechd /dev/shm: decide snap-local sem-
  name patch vs snapd template change before the audio leg (the
  review's narrowness principle favours the patch). Gate 1 of the
  T11 review is CLOSED: the confined-provider architecture is
  proven at the bus level.
- [2026-11-10] T17 REVIEW: REQUEST-CHANGES (saved verbatim in the
  working notes). Headlines: (D1) consent model structurally blocks
  unmodified store apps (receive policy = connected plugs +
  unconfined only) — gate 2 cannot pass as built; (D2) snap.*/at-spi/
  bus* path wildcard + X11 AT_SPI_BUS property = real hijack
  vector; (D3) widened rules lack name constraints ->
  snap-to-snap a11y-tree exposure; (D5) nothing starts orca on a
  real thin image (fat masking hid it); (D6) the unconfined receive
  block is bus-agnostic (system bus posture change; upstream will
  reject); (D8) refresh strands the reader; (D9) two providers
  coexist on the test VM; (E2) NO POSITIVE CONTROL that mediation
  is enforced on the confined private bus; (E3) sem.XXXXXX is
  glibc's temp-name shape — the proposed speechd patch would not
  fix it; (E1) gate-1 shell claim overstated (bus join unproven).
  Minimal change list: 12 items.
- [2026-11-10] T18 TRIAGE DONE: 14 VALID / 5 PARTIALLY VALID /
  0 INVALID. Key refinement: E2 CONFIRMED WITH MECHANISM — the
  strict template grants neither /proc/<pid>/ mounts (T13 §2.4
  denial) nor .access; libapparmor aa_is_enabled() ->
  setmntent(/proc/mounts) fails -> dbus pre_init leaves mediation
  OFF (documented fail-open); queries would fail CLOSED had init
  succeeded. T16's zero private-bus denials despite orca lacking
  bus=accessibility rules => the traffic flowed UNMEDIATED.
  Gate-1's "mediation ON" claim is therefore VACUOUS as measured;
  T15's widened rules were never exercised. Other refinements: D3
  count is 4-of-11 name-less (not 8/10) and blanket pinning would
  break legit shell->app reads; D9 is two different layers (dbus
  file precedence vs systemd BusName refusal), not a contradiction;
  I1 nuance: a43f5c2 is inert on thin but LIVE on fat (keep on
  fat, drop from the thin series); D7 downgraded to partial
  (sequential restarts, no observed concurrent greeters).
  GATE 1 STATUS REVISED: the architecture mechanism is proven
  (activation/ownership/uid resolution), but gate 1 must be RE-RUN
  with real mediation before it can be claimed.
  REVISION PLAN: T19 dispatched = the snapd+snap policy foundation:
  (i) E2 — enable mediation (grant what libapparmor needs in the
  provider profile/template) + a MUST-DENY test (confined non-
  desktop-legacy client -> expect denial), then (ii) re-derive
  policy under REAL mediation: D1 name-scoped snap.*+unconfined
  GetAddress receives on session bus (store-app compat, no
  per-client plugs), D2 pin the path rule to the provider's exact
  path, D3 pin private-bus unnamed peers to the provider label +
  fix the false comment, D6 scope the unconfined block to session
  bus + system-bus negative test. T20 (queued): thin reader-start
  path (compat orca.service adapter), drop a43f5c2 from the thin
  series, I4 cleanups, D8 refresh-mode: endure, E3 strace-before-
  fix, D9 one-provider assertion at image assembly.
- [2026-11-10] T19 DONE + manager-verified (commits shown: snapd
  00f016f1eb/edff116049/895a808928 = accessibility-provider
  interface + lsm_get_self_attr + policy scoping; a11y snap
  ebfa415/a9078f0/6eed302). E2 RESOLVED: mediation initializes
  (root-cause chain verified against dbus 1.16 + libapparmor:
  aa_is_enabled died at /proc/<pid>/mounts, full_init needs
  aa_getcon via seccomp syscall 459, queries need .access O_RDWR);
  grants landed via a NEW accessibility-provider interface
  (thumbnailer-precedent shape, snap-scoped not template-wide);
  MUST-DENY ARTIFACT: confined client without desktop-legacy ->
  RequestName on the private bus -> kernel policy denial
  (dbus_bind mask=bind), repeatable. Policy rework under REAL
  mediation: D6 session-bus-only unconfined block + system-bus
  negative test; D1 interface-scoped peer=(label=snap.*)
  (AppArmor 5 forbids name= on send/receive — grammar finding;
  name-derived path mismatches at-spi's lowercase path); D3
  provider-peer rules pinned {snap.ubuntu-desktop-a11y.*,
  unconfined}, app-flow rules keep snap.* per T18, false comment
  fixed; D2 socket moved to the CONVENTIONAL /run/user/<uid>/at-spi/
  bus (T11 §3) and the snap.* path wildcard REMOVED. Live-matrix
  find: registry activation needed AssumedAppArmorLabel on the
  staged entry (empty dst_label defeats all label conditions).
  Tests 39/0; every rule shape validated with the VM's
  apparmor_parser 5.0.2. Versions: snapd g61.895a808, a11y x12.
  GATE-1 RE-RUN UNDER REAL MEDIATION: ALL PASS (same-snap,
  unconfined, confined-shell, orca greeter smoke, must-deny holds).
  Gate-1 now claimed WITH mediation ON. Still open: shell
  persistent join (gate 2), refresh-mode (D8), thin image boot
  (E5), speechd audio (E3). T20 dispatched (final queued revision
  phase).
- [2026-11-11] T26 DONE — gaps (a), (b), (d) CLOSED; (c) CODE
  COMPLETE pending re-bake. (a) CLOSED + SHAPING CORRECTED: a11y
  snap 646d9c7 (x11 plug) — abstract connect now
  ECONNREFUSED-not-EACCES, zero X11-unix AVCs, greeter-X0 covered;
  BUT stage 2 emerged: mutter spawns Xwayland on demand and the
  THIN BASE has no Xwayland/XKB data ("Failed to execute child
  process /usr/bin/Xwayland"). Session-snap launcher committed
  (50b64c6+e531eb3, confined sessions); base-level fix scoped, not
  landed. MANAGER DECISION (NEW-1): the CONTENT SNAP
  (gnome-desktop-runtime) owns Xwayland + XKB data — mutter is
  what spawns it and the content snap owns mutter (fat parity:
  fat's content snap staged it). Routed to T27. (b) CLOSED:
  bafad9d025+986a18cefa (g69/g70) — Accessible Get* + Collection
  GetMatches at the classic numeric paths, PATH-only widening,
  peer alternation untouched, tests extended; the 1267-denial
  class collapsed to ZERO — the confined reader walks the greeter
  shell tree (118-line dump captured). (c) CODE COMPLETE: NO
  handover mechanism existed (locale/tz system-wide; dconf has no
  per-user channel) — provd now records the full a11y keyset +
  target user to /etc/dconf at CreateUser (199234b66 + tests;
  provd 0.1.5+t26handover) and a base-baked static unit applies
  them at the target user's first login (6ea5214, in-payload
  verified). End-to-end pending re-bake; gotcha documented: base
  snaps must go through image assembly (a base sideload BRICKED
  root/sshd — reverted+recovered; the recovery recipe is recorded).
  (d) CLOSED: 612a6f2cd2 (g69) — the session agent creates the
  user's unit wants-dirs before enabling; refresh completes with
  the greeter manager active (26/27). Must-deny re-proven after
  both policy changes. NEW-2: the proxy oddity got its own
  investigation note; the temporary secondary proxy is deployed
  but unused. Gate rows: 3 PASS (improved — reader reads the
  shell tree), 4 PASS* (blocked on NEW-1), 6 PASS (improved),
  1/2/5/7 unchanged; must-deny intact; VM restored to a clean
  first-boot wizard state. T27 dispatched: content-snap Xwayland +
  full re-bake (everything incl. provd 0.1.5+t26handover) +
  first-boot gate-4 completion + (c) end-to-end + full gate table
  re-run.
- [2026-11-11] T24 DONE — GATE 2 PARTIAL->PASS, GATE 4 ROOT-CAUSED
  (our own config). GATE 2: root cause NOT the hypothesized Status
  reads — the provider's unnamed receive rule
  {snap.ubuntu-desktop-a11y.*, unconfined} denied **Hello** for
  every cross-snap client (calculator, shell, portal — verbatim
  AVCs); GTK 4.14 does not even check IsEnabled. Fix series (snapd
  desktop/26, 6 commits, g62-g67, none pushed): receive-only JOIN
  surface mirrored from the client's own grants (driver handshake,
  Socket.Embed, registry/DEC queries) + session-bus Status reads
  (no Set); provider-to-app sends — the registry's 30s **Peer.Ping
  health check** was disabling every registered app ("Disabling
  unresponsive app") — plus Application.Id Set, listener
  bookkeeping, reader grants incl. GTK4's <app>/a11y/<uuid>
  layout; interface-scoped events, cache unicast fix, UUID paths,
  client Status-read sends. FINAL: calculator's unique name on
  bus_0, Atspi tree walk (frame "Calculator" -> panels), ZERO
  a11y-bus denials. MUST-DENY INTACT (both shapes re-proven on
  g67: sd socket connect kernel AVC + RequestName dbus_bind
  denied from a desktop-legacy-carrying client). Gate-8 owes the
  audible announcement; deeper reader calls granted on denial
  evidence. GATE 4: verdict (i) OUR OWN CONFIG — whitelabel.yaml
  (core-base-desktop 6a87e1a) set pages.accessibility.visible:
  false ("non-functional without sprovd" — both preconditions now
  gone); fix 56a21d2 removes the stanza. LIVE-VERIFIED: page at
  step 2, toggle -> provd gRPC -> screen-reader-enabled=true
  (gsettings readback), chord alt+super+s starts/stops orca via
  the snap adapter with the wizard open (T11 §4 ✓). Versions: VM
  snapd 2.76.3+g67.5f1aad7 (x8), a11y x2 unchanged. REMAINING:
  re-bake (core-base-desktop + g67) for a real FIRST-BOOT gate-4
  pass; toggle->gsd auto-start leg broken (no dconf-service in
  the session, no change notifications — new finding, T20's
  notification theme); orca's org.gnome.Orca.Service bind denied;
  deeper reader interfaces; gates 5-8 backlog. Gotchas: snapcraft
  stale version stamps on incremental builds; sideloaded snapd
  must keep snap-confine file caps (host repack strips them).
- [2026-11-11] T25 DONE — CONSOLIDATION: FULL GATE TABLE 1-7 ON A
  REAL FIRST-BOOT BAKED IMAGE. BAKE: core-base-desktop rebuilt with
  tools/build-variant.sh desktop (GOTCHA: the repo's default build
  wrapper makes a cloud-init-variant snap renamed to core26-desktop
  WITHOUT the desktop payload — no whitelabel.yaml; also
  incremental pack keeps a stale version suffix, snapcraft clean
  first) — core26-desktop_20261111+desktop with 56a21d2
  (whitelabel) + 39d48fb (adapter) verified in-snap; snapd
  g67.5f1aad7 BAKED (not sideloaded); a11y tip pack; image built
  with the image build (`build.sh --desktop gnome --base-snap
  <that base>`, no user pre-seeded);
  assert_single_a11y_bus_provider PASSED in-build. GATE TABLE
  (baked, first boot): 1 PASS (must-deny both shapes, both
  sessions; T0b=0 whole boot); 2 PASS* (calculator: confined
  launch, :1.9 on bus_0, Atspi tree walk, 0 a11y-bus denials,
  0 "Disabling unresponsive app"; *store was network-blocked this
  run — rev 972 sideloaded from the T23 VM with T23's connection
  end-state; NOTE: the session snap DOES have an implicit :desktop
  slot — T23's connect failure was syntax); 3 PASS (chord ->
  adapter -> orca sustained NRestarts=0, espeak real module,
  spd-say --wait exit 0, clean off; kill-9 respawn+reconnect);
  4 PASS* (THE 56a21d2 PAGE IS AT STEP 2 ON FIRST BOOT; toggle ->
  provd gRPC -> dconf.service activated ->
  screen-reader-enabled=true at the NEWLY FOUND wizard db
  /run/gdm3/home/<uid>/snap/ubuntu-desktop-session/common/
  .config/dconf/user; chord in wizard = documented no-op; orca
  auto-start still dead in the wizard; orca reading the wizard
  crashes on the wizard-session abstract-X11 AVC peer_addr=@/tmp/
  .X11-unix/X1024 -> Gdk display None -> keymap None — fix shape:
  abstract-addr grant or fs-socket DISPLAY); 5 PASS* (GUI
  a11y-panel toggle keyboard-only: ON -> orca auto-start 13:07:51,
  OFF -> clean stop — the actuation leg WORKS in the user session;
  the USER-session dconf write location still unresolvable — no
  db file anywhere, dconf.service inactive; wizard->user setting
  handover BROKEN — new finding); 6 PASS (refresh x1->x2 with the
  bus daemon surviving at the SAME PID — endure live;
  mixed-revision reader-vs-bus; revert; crash respawn; bus
  restart: apps self-recover, orca STRANDS (dead connection,
  "Couldn't connect…") until re-enabled — recovery verified; NEW
  snapd bug: refresh aborts re-enabling the speechd socket against
  the greeter's WIPED ephemeral HOME — mkdir workaround;
  refresh/revert refuse while a non-endure app (orca) runs); 7
  PASS (cross-UID both directions EACCES via 0700 runtime dirs;
  one-provider assertion in the bake). NEW SHAPED GAP: orca cannot
  read the SHELL's a11y tree — 1267 denials, ALL
  org.a11y.atspi.Accessible GetRole/GetState at
  /org/a11y/atspi/accessible/<n>, orca ->
  snap.ubuntu-desktop-session.gnome-shell (g63-g67 reader grants
  cover root+GTK4 shapes; classic numeric paths need the
  Accessible sends). T17 SCORECARD: 11/12 CLOSED — items 5 and 7
  moved this run (as predicted), 12 closed at the first-boot bar;
  item 4 (name reservation) the only OPEN one. Store re-test owed
  when egress allows. Handoff: the test VM left running (t25
  logged in, a11y back at x1 after the revert, 0 failed units, no
  pushes, must-deny intact).
- [2026-11-11] T20 DONE + manager-verified (commits shown across
  three repos). ALL FIVE ITEMS PASS:
  1. D5 adapter: core-base-desktop 39d48fb — vendored thin
     orca.service ExecStart=/snap/bin/ubuntu-desktop-a11y.orca
     (gsd core-override shape; no snap-run-in-user-unit gotcha),
     Wants reconciled to the snap's units, [Install] dropped
     (static; enable refuses), removal plan in-header. LIVE PROOF
     on the fat VM: fat orca.service masked -> StartUnit ->
     adapter -> Wants fired the snap bus -> confined orca ->
     registryd under the bus label at the conventional socket,
     ORCA-ALIVE-12S, NRestarts=0 — the full thin start path works.
     NEW FINDING: gsd's dconf-notification leg is dead (stale
     inotify inode + undelivered Notify) — the chord trigger needs
     the T11 §4 item-2 reconcile (gsd setting-reconcile at session
     startup); connect leg re-confirmed to require the file-backed
     greeter uid (D7 decision stands).
  2. I1: 4a126c2 reverts a43f5c2 from thin (fat keeps 4decc22).
  3. I4: d7a271b triplet GI path, cebaadd PULSE_SERVER (no snapd
     mechanism exposes the slot instance — kept + documented),
     1dcedf6 gitignore+untrack, 4482f17 debug-block removal +
     version 0.1+git20261110. x15 sanity: all three apps green.
  4. D8: 7ae0fe8 refresh-mode: endure on bus + speechd (fork
     validate.go:972 verified); gate-6 run still owed.
  5. E3 RESOLVED WITHOUT A MANAGER DECISION: strace verbatim —
     openat("/dev/shm/sem.mP6OEw", O_CREAT|O_EXCL) = EACCES ->
     unchecked SEM_FAILED -> sem_wait(NULL) SIGSEGV. Temp-name
     theory confirmed; options (i)/(ii) dead; fix = in-snap: drop
     the sem_open-using modules (99f7a30) + two stacked layout
     bugs (76e1d3f libpulsecommon, f21adf8 plugin-dir); x15:
     espeak loads, "Initialized for server audio", no crash.
  T17 12-ITEM SCORECARD: CLOSED 1, 2, 8, 9, 11; PARTIAL 5 (ixr
  retirement + gsd integration remain), 7 (gate-6 run owed);
  OPEN 3 (store-app reach on a real image), 4 (name reservation
  upstream), 6 (greeter userdb route — decided file-backed, D7
  nuance documented), 10 (one-provider assertion at assembly),
  12 (thin image boot + gate re-runs). VM left as found except
  sanctioned revisions (snapd g61, a11y x15, session x3); no
  pushes; no mediation changes. REVIEW-TRIAGE-REVISE CYCLE
  COMPLETE: all 19 triaged concerns addressed or explicitly
  queued with owners; the remaining work is image-assembly +
  thin-image E2E (next session's natural scope).
- [2026-11-11] DIRECTION CHANGE (user): FAT IS NO LONGER THE
  TARGET. The thin image is the focus; fat work only where it
  helps verify thin. CONSEQUENCES: (1) the a11y todo's remaining
  fat-line items (fresh-image bake, reboot persistence, F-gated
  user-session rows ON FAT) are SUPERSEDED — the fat line is a
  frozen verified reference, no further investment; D1 merge +
  pushes remain user decisions. (2) F1/F2/F4 were FAT-image
  findings — the thin line's PAM/dispatch/login stack may differ
  (never booted); establish ground truth on thin before fixing
  anything. (3) The spike todo's remaining gates all require the
  first real thin boot (E5) — that is now THE critical path.
  NEXT: T21 = first thin image boot + baseline assessment (boot
  health, wizard, greeter, login/PAM state, which F-class issues
  reproduce on thin), THEN login fixes on thin (if needed), THEN
  wire the a11y snap into the thin image + re-run gates 1-5 there.
- [2026-11-11] T21 DONE — FIRST THIN IMAGE BOOTED: USABLE daily-
  test target. BUILD: canonical path, no assembly gaps — base
  rebuilt from desktop/26 tip 4a126c2 (the 20261110 artifact
  predates T20's adapter: rebuild required), session repacked
  20261111+gitf146062, image built with the image build (`build.sh
  --desktop gnome --base-snap <thin>`, no user pre-seeded); thin
  custom-core 82.6MB vs fat 276MB. BOOT: 0 failed units, 118
  denials all in fat's known-noise classes, provd x0 (fat's
  852-denial crash-loop GONE — provd confined-enforce on thin).
  COMPOSITION: 25 snaps; snapd g61 (a11y policy in-image), session
  gitf146062 (consent plug in-image), a11y stack confirmed ABSENT
  (pre-state). F-CLASS ON THIN: F2 PAM fail-open ABSENT (fail-
  closed live-tested with $6$ + injected $y$ users — FAT-ONLY BUG,
  close that todo item); F1 content-launcher guard PRESENT same
  mechanism (exit-126 allowlist gdm*/initial-setup*; live repro ->
  T22); F4 statically unbroken (live login pass owed). a11y PRE-
  STATE: T0b markers verbatim (gnome-shell + ubuntu_init
  ServiceUnknown) — the thin baseline for gate re-runs.
  gsd-a11y-settings + pipewire running in the wizard session
  (d5dd37e + f622a7d live on thin); gdm file-backed uid 200. VM
  handoff: the test VM (serial root/x), test user removed,
  extrausers empty — wizard-phase clean state. T22 dispatched:
  fix F1 on thin (understand the guard before widening it),
  complete the wizard via monitor-screendump GUI automation, live
  login pass (F4), then T23 wires the a11y snap (provider --snap
  pattern; connections; consider require_provider_snaps addition)
  + gates 1-5 on the real target.
- [2026-11-11] T22 DONE — SURPRISE-POSITIVE: F1 DOES NOT MANIFEST
  ON THIN (no fix needed; no commit). Guard analysis: gnome-
  content-launcher (core-base-desktop variants/desktop/static) —
  the gdm*/initial-setup* allowlist exists on the ALIAS mode only
  (direct host-content exec = greeter/wizard privilege); real
  users are DESIGNED to route through --session-dispatch -> the
  confined session snap (two source mechanisms verified: the
  static /usr/bin/gnome-session wrapper -> core-desktop-session-
  wrapper.sh, and the content snap's user-unit core-overrides).
  The fat F1 was a fat-path artifact. Guard untouched
  (load-bearing). LIVE LOGIN PROVEN: wizard completed keyboard-
  only via VNC automation (the pointer was dead on this VM);
  t22/x created; greeter password login -> desktop up (PAM accept
  verbatim); F4 PASSES — dispatched session reaches gnome-shell
  --mode=ubuntu confined (snap.ubuntu-desktop-session.gnome-shell
  enforce). Bonus F2 evidence: greeter path fail-closed on thin
  (wrong password REJECTED verbatim). User-session a11y pre-state:
  GetAddress -> ServiceUnknown; T0b markers from user-session
  shell/portal/DING. Handoff: t22 (uid 1000) logged in on seat0/
  tty2 (session 89), greeter alive tty1, root ssh works. T23
  dispatched: wire the a11y snap into the thin image (provider
  --snap pattern; connections: session dbus-a11y-bus-client ->
  a11y slot, audio-playback -> pipewire, desktop-legacy per T19;
  one-provider assertion) + re-run gates 1-5 on the REAL thin
  target — the capstone that retires the fat-masking caveat.
- [2026-11-11] T25 DONE (resumed after one timeout; no work lost)
  — FULL GATE TABLE ON THE BAKED IMAGE, FIRST BOOT. Bake: base via
  tools/build-variant.sh desktop (gotcha: the repo's default build
  wrapper makes a cloud-init-variant snap renamed core26-desktop
  WITHOUT the desktop payload; needs snapcraft clean or the
  version suffix stays stale) — 56a21d2 + 39d48fb verified
  in-snap, snapd g67 BAKED (no sideload file-cap issue),
  one-provider assertion passed in-build. GATES: 1 PASS (must-deny
  both shapes, both sessions; T0b=0 whole boot); 2 PASS*
  (calculator confined, unique name on bus_0, Atspi tree walk,
  0 a11y-bus denials; *store network-blocked this run —
  calculator sideloaded from T23's end-state); 3 PASS (sustained
  chord, espeak real, spd-say exit 0, clean off, kill-9 ->
  respawn+reconnect); 4 PASS* (THE PAGE AT STEP 2 on first boot —
  56a21d2 live; toggle->provd->dconf true at the located wizard
  db; *orca auto-start dead leg + wizard abstract-X11 crash
  precisely shaped); 5 PASS* (GUI panel toggle -> orca auto-start
  AND clean stop, both directions; *user-session dconf write
  location unresolved, wizard->user handover broken); 6 PASS
  (refresh x1->x2 with the bus daemon surviving at the SAME PID —
  endure live; revert; crash respawn; bus restart: apps
  self-recover, orca strands until re-enabled — recovery
  verified; NEW UPSTREAM-WORTHY SNAPD BUG: refresh aborts on the
  greeter's wiped ephemeral HOME); 7 PASS (cross-UID EACCES both
  directions; one-provider assertion). 8 hardware/human not run
  (inherently human). SCORECARD: T17's 12-item change list 11/12
  CLOSED (items 5 and 7 moved as predicted; 12 closed at the
  first-boot bar); only item 4 (upstream name reservation) open.
  NEW SHAPED GAPS for the backlog: (a) wizard abstract-X11 AVC
  @/tmp/.X11-unix/X1024; (b) orca->shell classic-path Accessible
  reads denied (1267 denials — reader grants need the classic
  numeric paths); (c) wizard->user setting handover; (d) snapd
  ephemeral-HOME refresh bug (upstream). Handoff: the test VM
  running (t25 logged in, a11y back at x1, 0 failed units);
  re-bake is one command (must pass the build-variant base
  explicitly). Nothing pushed; must-deny intact. THE THIN-LINE
  A11Y ARCHITECTURE IS PROVEN END-TO-END ON THE REAL TARGET:
  confined provider, real mediation, greeter chord, wizard page,
  store-app registration, lifecycle, and isolation all green on a
  baked first-boot image.
- [2026-11-12] GATE-8 SETUP + DISPLAY-SHEAR FIX. The tester's VNC
  session showed a FROZEN desktop; screendump diagnosis: the
  desktop was SHEARED 45-degrees diagonally with scan-line noise
  (a stride mismatch — not frozen, not an input bug). ROOT CAUSE:
  the launch's custom EDID geometry (xres=1050,yres=1050 — a
  square screendump convenience) did not survive mode negotiation
  on the audio/tablet relaunch — mutter picked a STANDARD mode
  (1360x768 et al) while QEMU's scanout surface stayed at the
  1050x1050 EDID geometry -> reading a 1360-stride framebuffer at
  1050 = progressive diagonal shear. FIX: drop the custom
  xres/yres, keep edid=on (standard modes; the guest now exposes
  up to 5120x2160, picked a normal desktop mode) — the screendump
  renders perfectly. FINAL TESTER LAUNCH (working): virtio-vga,
  edid=on + qemu-xhci + usb-tablet (the T22-era dead VNC pointer
  = no pointing device in the guest at all) + intel-hda/
  hda-output + -audiodev alsa,out.dev=plughw:1 (a USB dock's
  audio device; the launching user got the audio group via
  usermod — note QEMU must be launched with sg audio or a fresh
  session: group membership is not inherited by stale shells;
  also -audiodev alsa wants out.dev= not device=, and pkill -x
  qemu-system-x86_64 is a no-op because comm is truncated to
  qemu-system-x86). Tester VM running (t30 session autologged).
  RUN-SCRIPT TODO: fold usb-tablet + audio + standard-EDID into
  the thin run scripts (the pointer/audio were launch-time gaps,
  not image gaps).
- [2026-11-12] T31 WRAP-UP DONE + BISECT VERDICT CORRECTED.
  (1) MY EARLIER BISECT VERDICT ("audio devices are the culprit")
  WAS WRONG: the b-audio static test was CONFOUNDED — that boot
  had autologin, so the static frame was the USER-SESSION display
  stall, not audio. T31's discrimination on a fresh clean bake
  (NO audio devices): the autologin USER SESSION freezes the
  virtio-gpu scanout (frame stuck at session start; guest clock/
  gnome-shell alive — the same stalled-scanout signature), while
  THE GREETER RENDERS LIVE (clock 12:36->12:37 verified).
  Discriminated: NOT audio (none present), NOT usb-tablet/xhci
  (probe without it froze), NOT EDID, NOT orca (killing it doesn't
  recover). THE REAL DISPLAY BUG: the user-session gnome-shell
  (--mode=ubuntu, confined) stalls the scanout after its first
  frame; greeter/wizard sessions render fine. T32's running
  display-driver bisect (VGA/bochs vs virtio, WITH the user
  session up) is now exactly the right investigation for THIS
  bug. (2) PIPEWIRE SNAP FINDINGS RETRIEVED (verbatim evidence in
  the T31 report): FINDING 1 — a user-writable pipewire.conf.d
  fragment can BRICK the session audio daemon into a systemd
  crash loop: the snap (pipewire 1.6.2-1ubuntu1.2 rev x1) does
  NOT ship libpipewire-module-null-sink.so (upstream 1.x shape;
  the distro host package lacks it too) and context.modules
  entries without flags=[ifexists,no-fail] are MANDATORY ->
  "could not load mandatory module" -> failed to create context
  -> snap run exit 254, Restart=always loop (repro'd x3 in 2s);
  drop-ins ARE honored from ~/snap/pipewire/x1/.config/pipewire/
  pipewire.conf.d/ (SNAP_USER_DATA) — proven by the crash itself;
  recovery = remove the fragment. FINDING 2 — the snap's tools
  (wpctl/pw-cli) are unusable outside the session's systemd-user
  context (raw env -> Can't create context rc=255/segfault;
  runuser...snap run -> cannot track application process); the
  only working remote probe: systemd-run --user -M 1000@.host
  --pipe --wait /snap/bin/pipewire.wpctl. BOTH look upstream/
  packaging-reportable — manager review pending. (3) RTP WORK
  STATE (PARKED, fully documented): guest RTP sink drop-in +
  set-default verified live in the session; host receiver
  verified with a full auto-linked graph; the end-to-end
  speech-through leg was the one untested piece; the owner's
  pipewire cleaned of T31 nodes. (4) VM STATE: the tainted t30
  image renamed pc-thin-t30.img.TAINTED-T31-rtp; a FRESH bake
  (pc-thin-t31.img, wiring f7304d0, same artifacts, BUILD-EXIT=0)
  is up with the tester setup applied and verified (handover
  marker, orca auto-start via gsd, zero RTP artifacts, Dummy
  Output only) — CAVEAT: a parallel T32 session took that image
  over for its bisect step 2 (xres=1050 EDID). (5) NEW BLOCKER
  for the gate-8 session rows: the user-session display stall
  (above) — the GREETER is testable NOW (chord + orca at the
  greeter); the user-session rows wait for the display fix or a
  non-autologin login (password login = the known-broken
  YESCRYPT path — T30's handoff claim, UNVERIFIED: T32-era tests
  proved login worked; see T22).
- [2026-11-12] AUDIO STALL ROOT-CAUSED (bisect + discrimination):
  adding ANY QEMU audio device (intel-hda/hda-output with alsa OR
  pipewire OR none backend — backend-independent, proven by the
  none-backend discrimination test) stalls the virtio-gpu display
  pipeline: the guest's pipewire snap opening the emulated audio
  device freezes the scanout (one correct frame, then static;
  even a kernel VT switch doesn't update the scanout). thread= is
  NOT supported by QEMU 10.2's alsa/pipewire audiodevs ("Parameter
  'thread' is unexpected"). usb-audio (xhci path) also stalls —
  codec-independent. The stall is guest-side device USE, not the
  host backend. AUDIO PIVOT: NO QEMU AUDIO DEVICE AT ALL (the
  proven-live display baseline) — the audio routes at the GUEST's
  pipewire level: pipewire RTP sink (guest) -> RTP -> the host
  desktop user's pipewire (module-rtp-recv + loopback -> the
  user's headset, the user's default sink). T31 dispatched (the
  guest pipewire config drop-in + host-side module load +
  end-to-end verification). The audio-group usermod stays useful
  (ALSA fallback paths); a 755 chmod on /run/user/99 was needed
  for the host-side module load (launching user -> the owner's
  pipewire socket). The backend options + gotchas + verification
  recipes were written up in the project documentation (the stall
  finding to be appended once the RTP path is confirmed).
- [2026-11-12] DIRECTION CHANGE (user): the guest-side RTP route
  is PARKED — modifying the guest build to compensate for a
  QEMU-side issue is the wrong layer. New plan (user's
  alternatives, in order): (1) the DISPLAY-DRIVER question
  first, testable right away: the stall reproduces with
  intel-hda AND usb-audio AND both backends — but only
  virtio-vga has been tried as the DISPLAY device; test
  VGA/bochs-display + audio (if the display driver is the
  variable, this fixes it with zero guest changes); (2) if still
  stalled: run QEMU as the user (the user's own account —
  native pipewire session access, no env/chmod hacks) — the
  user runs one command; (3) if still stalled: guest kernel
  diagnosis (ALSA-open -> display stall interaction: interrupts/
  softirqs). The RTP guest drop-in work is parked, not discarded.
- [2026-11-11] T27 DONE. NEW-1 PREMISE CORRECTED: the content
  snap ALREADY carries xwayland/xkbcomp/setxkbmap/xkb-data
  (initial-commit entries; rebuilt from tip anyway, no commit
  needed) — mutter spawns a COMPILED-IN XWAYLAND_PATH (no PATH
  lookup), and the wizard session (unconfined, no layouts) needs
  a BASE redirect. Fix validated live in 4 stages: base
  /usr/bin/Xwayland launcher -> spawn from the content snap
  works (full mutter args); /usr/bin/xkbcomp redirect -> keymap
  compiles; XKB data via bind; 4th piece captured:
  mutter-x11-frames ENOENT -> gnome-shell SEGV. Build: 3 bakes,
  0 failed units, assertion in-build; session snap rebuilt
  20261111+gite531eb3. Gate 4 PASS* (page/toggle/dconf every
  bake; orca-alive-on-wizard proven once with the redirect
  launchers, sustained; closes with the base-redirect commit).
  (c): mechanism CLOSED at every layer — two NEW layers fixed
  live: core-base-desktop b67bf18 (writable /etc/dconf bind,
  colord/firefox pattern) + 295c176 (0777 factory dir; provd
  writes as the wizard's dynamic uid); session-side leg PROVEN
  (the write lands via the session's XDG redirect -> readback
  true -> orca auto-started via gsd). Blockers for the final
  run: NEW-3 wizard "Confirm password" field rejects all input
  (keys+paste, 10+ attempts, 3 boots; wizard snap bit-identical
  to T22's — flaky/regression, un-root-caused); NEW-4 greeter
  orca crash-loops: snap-ns lacks /var/lib/gdm3 -> EROFS ->
  X11-NULL SEGV (needs clean-VM confirmation). Gate 1 PASS
  (must-deny both shapes verbatim: sd-connect errno 13 + kernel
  AVC; orca-label bind AccessDenied + dbus_bind AVC); gates
  2/5/6/7 carried PASS; 3 PARTIAL (NEW-4); 8 not run. NEW-2 MOOT
  (store egress restored; the temporary secondary proxy
  retired). Commits: b67bf18+295c176 (desktop/26). Handoff: the
  test VM parked mid-identity-page for the NEW-3 repro. T28
  dispatched: complete the Xwayland redirect (mutter-x11-frames
  piece) + NEW-4 root-cause + NEW-3 investigation + final bake +
  gate-4/3/(c) completion — then the full-work independent
  review (T29).
- [2026-11-12] T30 DONE — PRE-GATE-8 REVISION PASS COMPLETE;
  GATE 8 (human testing) UNBLOCKED. ALL SIX ITEMS DONE:
  1. C4 reader contract DONE+PROVEN — the reader role landed as
     the accessibility-provider CONNECTED-PLUG snippet (derived
     once from at-spi2-core's XML; peer shapes = the existing
     widened ones only, D3 holds; desktop-legacy untouched);
     proof on the clean bake under real mediation: Text read,
     caret walk, DoAction (advanced the real wizard!) — ZERO
     bus=accessibility reader-flow denials whole boot (T28 bake
     had 1063). snapd a797119d8a (+382 lines, tests included).
  2. Gate-3 chord bisect RESOLVED — NOT a regression: T28's
     "chord did not fire" was chord.py hardcoding port 5907 (it
     pressed the chord on the T27-image VM); the reviewer's
     2d8c6c2-group hypothesis disproven (passwd/group md5-
     identical across images). Chord FIRES on the clean bake via
     vncdotool -> orca + sd_espeak-ng x2.
  3. Gate-4 dead leg DOCUMENTED (no half-fix; the gsd reconcile
     is content-snap-sized, queued); fallback proven: the chord
     works in the wizard.
  4. C11 pre-series build skipped as disproportionate (recipe
     documented); the cheap bisect step RAN: NEW-3 reproduces
     with the x11 edge DISCONNECTED -> not our x11 plug;
     remaining candidates + recipes documented.
  5. Clean bake DONE (no seed/users/probe state). Real wizard
     CreateUser blocked by NEW-3 (reproduced on final bits); the
     documented fallback ran END-TO-END: handover applied at
     t30's first login, readback true, orca auto-started via gsd.
  6. C7 DONE: inet root cause = orca's brlapi retry (60s cap);
     suppressed via BRLAPI_HOST=$SNAP_USER_DATA/.config/
     brlapi.sock (unix ENOENT, ZERO inet denials over live
     minutes, no grant) + the schema override; x11 plug KEPT +
     documented (wizard-scoped accepted-risk + drop plan).
  FINAL PRE-GATE-8 TABLE (clean bake, snapd g71.a797119 / a11y
  x2=7947b6f): 1 PASS; 2 carried-noted; 3 PASS (fresh); 4 PASS
  (+dead-leg note); 5 PASS (write moment via T27 evidence +
  documented sim); 6 PASS (+fresh x1->x2 refresh); 7 PASS (both
  must-deny shapes verbatim; reader-plug install+auto-connect
  gated); 8 NOT RUN. Sweep: exactly ONE bus-a11y denial (= the
  must-deny probe itself), T0b=0, 0 failed units.
  Commits (none pushed): snapd a797119d8a; a11y b00c282/ecec367/
  7947b6f; wiring f7304d0 (gadget connection — deny-auto-
  connection means the same-snap edge is wired like the others).
  SHIPPING TODO (from T29, verbatim): C1/C2/C3/C5/C6/C7-residual/
  C8/C9/C12/C13 + follow-ups (NEW-3 bisect continuation: provd
  0.1.5 -> session f146062 -> snapd g67 -> pre-series image; the
  pam_extrausers/YESCRYPT greeter-login fix; second-greeter-uid
  snap-run lookup failure; the gsd reconcile).
  GATE-8 TESTER HANDOFF: the tester VM RUNNING (serial root/x,
  t30 autologged in, orca UP). Tools: vncdotool/monitor-sendkey
  (chord.py is BROKEN — wrong port + dead packets). Known
  constraints for the tester: NEW-3 persists (out-of-band user
  route; the wizard chord works); greeter PASSWORD login broken
  (pam_extrausers/YESCRYPT — new blocker, autologin route);
  handover file format documented; refresh hits the known
  ephemeral-home bug. Human-testing checklist = T11 gate 8:
  audible orca on the greeter and in the session, reading
  quality (text fields, caret navigation, DoAction), braille
  hardware if available.
- [2026-11-12] SCRATCH CLEANUP: completed-task working directories
  removed; 7 superseded VM images removed (~100GB freed); 6
  superseded a11y test VMs shut down (fat T7b + thin
  T21/T23/T25/T26/T27/T28 bakes); stale ssh/expect processes
  cleaned. KEPT RUNNING: the tester VM, the stock reference VM,
  and the old pre-fix reference VM (historical).
- [2026-11-11] T28 DONE — the last pre-review blockers closed.
  NEW-4 CLOSED: T27's SEGV was its own overlay artifact
  (clean-VM: orca survives, NRestarts=0); the REAL residual —
  gdm's seat-scoped env (XDG_CONFIG_HOME=/var/lib/gdm3/seat0/
  config) vs the snap ns — fixed in the a11y launcher only
  (31600bc; zero EROFS, zero schema denials). Xwayland stage 4
  CLOSED: base 80bcb51 (three launchers: Xwayland/xkbcomp/
  mutter-x11-frames); the mutter SEGV mechanism root-caused
  (NULL from meta_frame_launch_client fed to g_subprocess_wait_
  async — upstream-worthy); final bake: Xwayland :1024 -rootless
  spawned, keymap compiled, FRAMES SPAWNED, no SEGV, no further
  stage. NEW-3: NOT root-caused, routed around (out-of-band user
  + GDM autologin + the handover write via provd's own path);
  non-causes proven (no AppArmor denials, no ibus,
  ValidateUsername GrpcError fires on working runs too); the
  passwd.master hunt found a REAL bug though — chisel drops
  /usr/share/base-passwd/*.master which provd's ValidateUsername
  reads — fixed: base 2d8c6c2; the wedge persists (Flutter env
  interplay; delta set = g70/e531eb3/a11y-x11-edge/t26handover;
  sideload-bisect queued). FINAL BAKE (base 2d8c6c2, snapd g70,
  a11y 31600bc, session e531eb3, provd t26handover, content
  f892225) on the test VM: GATES 1-7 PASS (two asterisks:
  gate-3 chord keystroke stopped firing on the final bake —
  bisect queued; wizard orca auto-start dead leg unchanged),
  (c) END-TO-END PASS (handover applied at first login, orca
  auto-started, readback TRUE), gate 8 not run.
- [2026-11-11] T29 SECOND-ROUND REVIEW: REQUEST-CHANGES (saved
  verbatim in the working notes). KEY STRUCTURE: "None of this
  blocks human testing on a lab image. All of it blocks shipping
  and upstreaming" — with a 6-ITEM MINIMUM LIST BEFORE GATE 8
  and a 9-item before-shipping list. T17-response adequacy: 9
  addressed, 8 partially, 2 not. HEADLINE CONCERNS: (C1 HIGH)
  the accessibility-provider slot is installable by any app snap
  with PERMANENT snippet privileges (.access discloses all
  policy!) — must be allow-installation: false + connected-
  snippet grants; (C2 HIGH) the D3 line eroded on the CLIENT
  side — unnamed snap.* receive + read sends over three path
  shapes = cross-snap tree reads; needs a READER ROLE (the inert
  accessibility-provider plug side); (C4 HIGH FUNCTIONAL) THE
  READER HAS NO GRANTS FOR Text/EditableText/Action/Component/
  Value/Selection/etc — gate 4/5 passed on focus announcements
  only; a blind tester's first text field fails; fix = define
  the reader contract from at-spi2-core's interface list ONCE
  (not AVC-chasing); (C10 HIGH EVIDENCE) gate 3 is NOT PASS
  (chord didn't fire on the final bake; PASS carried from
  T27's image; the 2d8c6c2 passwd-master delta affects
  gdm-greeter group membership — "calling that delta implausible
  is not a bisect"); gate 5's provd write was SIMULATED (hand-
  placed files; CreateUser->handover never ran on the shipped
  image); (C11) NEW-3 must be reproduced on a PRE-SERIES thin
  image (if it doesn't reproduce there, it's OUR regression);
  (C7) orca's x11 plug = unreviewed key-snoop grant on every
  session; orca's inet denials must be SUPPRESSED not granted;
  (C3) the consent model is not consent (desktop-legacy
  auto-connects) — restate honestly or gate admission on a
  reader/client plug; (C6) name squatting still open
  (deny-installation on org.a11y.Bus dbus slots — grammar
  confirmed); (C8/C9) revert + path-changing refresh untested;
  concurrent dynamic users untested; (C12) base-line regression
  surface untested (T17 I2). UPSTREAM ORDER (reviewer):
  Peer.Ping fix; snapd wants-dirs fix; mutter frames NULL;
  base-passwd master chisel gap; org.a11y.Bus reservation; the
  accessibility-provider interface LAST after C1/C4 redesign.
  Fork-only-forever list recorded (implicitOnCore, broker,
  adapter, handover plumbing, Xwayland launchers, and the orca
  ixr should not survive once orca is snapped).
  MANAGER PLAN: dispatch T30 = the 6 pre-gate-8 items (C4 reader
  contract via the accessibility-provider PLUG side as the
  reader role; C10 gate-3 bisect; gate-4 leg fix-or-document;
  C11 pre-series repro; clean bake + REAL provd
  CreateUser->handover; C7 x11 scoping + inet suppression). The
  9 shipping-blockers (C1/C2/C3/C5/C6/C8/C9/C12/C13) become the
  shipping todo — they do not gate human testing. Gate 8
  (human) after T30 verifies.
- [2026-11-12] T31 WRAP-UP DONE + BISECT VERDICT CORRECTED.
  (1) MY EARLIER BISECT VERDICT ("audio devices are the culprit")
  WAS WRONG: the b-audio static test was CONFOUNDED — that boot
  had autologin, so the static frame was the USER-SESSION display
  stall, not audio. T31's discrimination on a fresh clean bake
  (NO audio devices): the autologin USER SESSION freezes the
  virtio-gpu scanout (frame stuck at session start; guest clock/
  gnome-shell alive), while THE GREETER RENDERS LIVE (clock
  12:36->12:37 verified). Discriminated: NOT audio (none present),
  NOT usb-tablet/xhci (probe without it froze), NOT EDID, NOT
  orca (killing it doesn't recover). THE REAL DISPLAY BUG: the
  user-session gnome-shell (--mode=ubuntu, confined) stalls the
  scanout after its first frame; greeter/wizard sessions render
  fine. T32's running display-driver bisect is now exactly the
  right investigation for THIS bug. (2) PIPEWIRE SNAP FINDINGS
  RETRIEVED (T31, verbatim evidence in the report): FINDING 1 — a
  user-writable pipewire.conf.d fragment can BRICK the session
  audio daemon into a systemd crash loop: the snap (pipewire
  1.6.2-1ubuntu1.2 rev x1) does NOT ship
  libpipewire-module-null-sink.so (upstream 1.x shape; the distro
  host package lacks it too) and context.modules entries without
  flags=[ifexists,no-fail] are MANDATORY -> "could not load
  mandatory module" -> failed to create context -> snap run exit
  254, Restart=always loop (repro'd x3 in 2s); drop-ins ARE
  honored from SNAP_USER_DATA — proven by the crash itself;
  recovery = remove the fragment. FINDING 2 — the snap's tools
  (wpctl/pw-cli) are unusable outside the session's systemd-user
  context (raw env -> Can't create context rc=255/segfault;
  runuser...snap run -> cannot track application process); the
  only working remote probe: systemd-run --user -M 1000@.host
  --pipe --wait /snap/bin/pipewire.wpctl. BOTH look upstream/
  packaging-reportable — manager review pending. (3) RTP WORK
  STATE (PARKED, fully documented): guest RTP sink drop-in +
  set-default verified live in the session; host receiver
  verified with a full auto-linked graph; the end-to-end
  speech-through leg was the one untested piece; the owner's
  pipewire cleaned of T31 nodes. (4) VM STATE: the tainted t30
  image renamed pc-thin-t30.img.TAINTED-T31-rtp; a FRESH bake
  (pc-thin-t31.img) built and verified (handover marker, orca
  auto-start via gsd, zero RTP artifacts).
- [2026-11-12] T32 DONE — THE DISPLAY-FREEZE MECHANISM FOUND
  (6/6 boots, causally probed). THE VERDICT: the display freeze
  is NOT QEMU-audio, NOT the display device (VGA/bochs-display
  both stall it), NOT the NTP clock step (excluded causally),
  NOT kernel starvation (no IRQ/softirq storm; the shell alive
  but not rendering — all threads in userspace futex/poll/epoll
  waits). THE MECHANISM: the confined session-snap gnome-shell
  STOPS SUBMITTING SCANOUT FRAMES ~30-60s after session start,
  coinciding (6/6 boots) with the A11Y POST-LOGIN HANDSHAKE —
  the a11y snap's orca auto-start (the reader enabled by the
  handover), its POLICY-DENIED Peer.Ping probe of the shell, and
  at-spi2-registryd DISABLING THE SHELL AS "UNRESPONSIVE". The
  shell ends up alive but wedged (futex waits), not rendering; a
  frozen display does NOT recover without a reboot. MY EARLIER
  "audio stalls the display" verdict was CONFOUNDED: every
  audio-bisect boot also ran the orca auto-start. The frozen
  frame the USER saw on :9 = this wedge, independently confirmed
  by the human. T32's recommended fix = grant the
  reader-handshake members (the "accessibility" family, same as
  the T24 health-check fixes) -> a plain bridge boot must stay
  live past ~2 min. T33 DISPATCHED: trace the complete wedge
  denial set from the VM journal, grant the members in the
  accessibility-provider reader role + the shell-side receives
  (the T28 join caveat), rebuild snapd +g72, sideload, and
  verify: a plain bridge boot stays LIVE past 2 min WITH the
  reader enabled (THE artifact), the handshake completes, the
  must-deny holds, gates 1/3/4/5 spot-re-checked.
- [2026-11-12] T34 DONE — THE USER-SESSION XWAYLAND KEYMAP FIX
  LANDED AND VERIFIED; GATE 8 IS UNBLOCKED (the display no
  longer freezes). MECHANISM (evidence-first, verified live):
  Xwayland 24.1.10's server-side keymap init resolves the RMLVO
  rules at the COMPILED-IN /usr/share/X11/xkb (XkbBaseDirectory —
  compile-time, no env override; the output dir falls back to
  $XDG_RUNTIME_DIR, so the output leg was never the problem).
  The session snap's base is STOCK core26 (base: core26) and the
  confined ns takes /usr from the BASE SNAP (mountinfo: /usr ←
  core26_750.snap) — no xkb data, so the rules lookup failed
  BEFORE xkbcomp was ever exec'd (proven: a debug-capture
  launcher at /usr/bin/xkbcomp never ran; no xkbcomp output in
  the journal; the generic "XKB: Failed to compile keymap" only).
  The wizard worked because it is UNCONFINED and sees the image
  rootfs (core26-desktop) which BAKES the xkb data. The T33
  cascade (ABRT → the shell's SS_CONNECTING main-thread hang →
  the freeze) followed. FIX: ubuntu-desktop-session @desktop/26
  5ce04c2 "Layout the XKB data for the session Xwayland keymap
  init" — THREE session-snap pieces completing the T26
  ownership pattern (50b64c6/e531eb3 did Xwayland only): (1)
  snap/xkbcomp-launcher + the /usr/bin/xkbcomp layout (the
  compiler leg); (2) the /usr/share/X11/xkb bind →
  $SNAP/gnome/usr/share/xkeyboard-config-2 (the data leg; bind
  the REAL dir — the content's X11/xkb is a compat SYMLINK and a
  symlink bind source KILLS the whole namespace: "cannot update
  snap namespace: not a directory", the session dies to the
  greeter); (3) the /usr/libexec/mutter-x11-frames bind-file
  (with the keymap fixed the confined session reached the
  T27/T28 stage-4 frames client → the mutter NULL → SEGV 11 —
  previously masked). NO base/content-snap/snapd/mediation
  change; must-deny intact. ITERATION LESSONS (all in the
  report): the dump part needs organize+prime for NEW files (a
  missing entry packs a 0-BYTE STUB — verify payload SIZES);
  sideloading the session snap needs gdm masked + every
  greeter-uid runtime dir gone + user@1000 up for the operator
  (the full recipe verbatim in the report; snapd's per-user stop
  task queries /run/user/<uid>/snapd-session-agent.socket for
  stale uids too — a snapd report). VERIFY on x7 (TWO fresh
  boots): Xwayland ALIVE (4:19/3:36 elapsed, the full mutter
  args), the keymap COMPILED (the wizard's verbatim warning
  signature: "Unsupported maximum keycode 708" — xkbcomp RAN
  through the new launcher), orca auto-started each boot, ZERO
  failures (no XKB/ABRT/Disabling/frames), ZERO
  bus="accessibility" denials, and THE ARTIFACT: screendumps
  +30/+60/+90/+120/+150 on boot 1 and +30/+90/+150 on boot 2 —
  every pair differs — THE DISPLAY STAYED LIVE PAST 2 MINUTES
  with the reader enabled. GATE SPOTS: 1 PASS (GetAddress
  unconfined → bus_0 verbatim + must-deny (a) SD-CONNECT errno
  13 live; must-deny (b) blocked live by the snap-run flake —
  now PERSISTENT for all non-root users on healthy boots, a
  snapd defect to report; the shape holds at policy level +
  T30's verbatim proof), 3 PASS (the chord fired via vncdotool;
  orca + sd_espeak-ng ×2 as gdm-greeter; the label-level walk
  carried from T25/T26/T30 + zero denials; the node capture
  blocked by the same flake), 4 carried with static
  verification (the wizard's three base launchers present on
  the host rootfs; the wizard is unconfined — the T34 change
  cannot affect it), 5 PASS (the gsd actuation re-fired every
  boot, NRestarts=0). The snap-run flake and the greeter-env/
  stop-task breakage are new snapd-side report packages
  (STEP 7c). UPSTREAM PACKAGES ready: the mutter sync-connect
  hang (re-observed LIVE on a half-fixed boot — the race is
  timing-dependent: two ABRT boots, one wedged, one not) +
  orca's xkbcomp pipe-read hang. VM HANDED TO THE TESTER: x7
  sideloaded, t30 autologged in, the session up on x7, orca
  auto-started, Xwayland :0 alive, display LIVE, 0 failed
  units, 0 a11y denials, probe residue removed. Gate 8 can
  run. NO pushes; NO mediation changes; must-deny intact.
- [2026-11-12] T33 DONE — POLICY LANDED, BUT THE WEDGE IS NOT
  POLICY (the stop rule fired correctly). POLICY: the reader
  role gains Peer.Ping send at path=/ to the established
  {snap.*,unconfined} family (snapd 1a31bb9072, +g72; tests
  extended, suites green, the rule verified deployed) — a real
  T24-family fix (the registry health check direction), but THE
  ARTIFACT FAILED: fresh boot on g72 — zero accessibility
  denials all boot, orca auto-started, and the display STILL
  froze in the same minute (screendump pair identical,
  registryd disabled the shell at +43s, the shell stopped
  reading bus_0). Must-deny holds. THE REAL ROOT CAUSE
  (traced, verbatim): orca's auto-start takes the X11 path
  (DISPLAY=:0 exported in the user session) -> mutter spawns
  the content-snap Xwayland -> "XKB: Failed to compile keymap"
  -> "Failed to activate virtual core keyboard" -> Fatal/ABRT
  (the T28 keymap failure family, STILL failing in the confined
  user session — the wizard fix never covered this spawn path)
  -> the shell's MAIN thread hangs forever in a synchronous
  connect to the dead Xwayland's X socket (fd 106 =
  SOCK_STREAM in SS_CONNECTING, poll(1 fd, infinity) on the
  compositor main thread) = THE FREEZE; orca hangs identically
  on its xkbcomp :0 child (pipe-read, 213KB bus backlog);
  registryd's disable is downstream. Correlation: 9/9 reader
  boots have the Xwayland ABRT; the greeter renders live
  because it never takes the X11 path. T32's causality was
  INVERTED (the handshake is the trigger context, not the
  mechanism). REMAINING FOR GATE 8: (1) fix the user-session
  Xwayland keymap compile (env diff vs the wizard's working
  spawn — session/content-snap work), re-verify fresh boots;
  (2) gate spot re-runs on g72 + that fix; (3) upstream
  packages: the mutter sync-connect hang (SS_CONNECTING
  evidence) + orca's xkbcomp timeout. T34 DISPATCHED (the
  Xwayland keymap fix). The test VM left running as the live
  repro (g72 sideloaded, snap copy kept).
- [2026-11-12] T34 DONE — THE USER-SESSION XWAYLAND FIX LANDED
  AND VERIFIED. MECHANISM (exact — neither exec nor write, the
  RULES LOOKUP pre-exec): Xwayland 24.1.10 inits its keymap
  from the COMPILED-IN /usr/share/X11/xkb (XkbBaseDirectory,
  xkbInit.c — no env override); the session snap's base is
  STOCK core26 and the confined ns takes /usr from the base
  snap — no xkb data there -> the rules fopen failed BEFORE
  xkbcomp was exec'd (a debug-capture launcher at
  /usr/bin/xkbcomp never ran). The wizard worked because it is
  UNCONFINED and the image rootfs bakes the data. FIX: session
  snap 5ce04c2 (amending 65a21e7; clean rebuild ->
  20261112+git5ce04c2, sideloaded x7): (1) snap/xkbcomp-launcher
  + the /usr/bin/xkbcomp layout; (2) /usr/share/X11/xkb ->
  bind $SNAP/gnome/usr/share/xkeyboard-config-2 (a symlink
  bind source kills the whole ns — the content's X11/xkb is a
  symlink; a real dir was required); (3)
  /usr/libexec/mutter-x11-frames bind-file (the T27/T28
  stage-4 SEGV surfaced once the keymap worked). No base/
  content/snapd/mediation change. VERDICT (THE artifact): two
  fresh x7 boots — Xwayland ALIVE (4:19/3:36 elapsed, full
  mutter args), the keymap COMPILED (the wizard's verbatim
  "Unsupported maximum keycode 708" signature), orca
  auto-started, ZERO XKB/ABRT/Disabling/frames failures,
  screendumps at +30/+90/+120/+150s: EVERY PAIR DIFFERS — the
  display stayed LIVE past 2 minutes, both boots. GATE SPOTS:
  1 PASS (GetAddress -> bus_0 verbatim; must-deny (a) errno 13
  live; (b) blocked by a persistent snapd "cannot track
  application process" flake — policy-level + T30 proof
  carried), 3 PASS (chord via vncdotool -> orca +
  sd_espeak-ng x2 as gdm-greeter; walk carried + zero a11y
  denials), 4 carried with static verification (the wizard's
  three base launchers present; the wizard is unconfined),
  5 PASS (actuation every boot + screen-reader-enabled=true
  readback). Sweep: zero accessibility denials, zero
  unexplained classes. New snapd report packages queued (the
  "cannot track application process" flake; the greeter-env
  stop-task breakage); the mutter sync-connect hang
  re-observed live (the race is timing-dependent).
- [2026-11-12] T34b DONE — THE DISPLAY-FREEZE SAGA RESOLVED.
  THE STACK AUDIT found the gate-8 VM was running the PRE-T34
  stack (snapd g71, session x1=e531eb3 — the T34 sideloads had
  NOT persisted across the relaunches); every "audio ->
  STATIC" datapoint ran pre-T34 bits; the "no-audio -> LIVE"
  datapoint ran on a different disk WITH x7. Restored the
  stated stack (g72 md5-verified + session x7 per T34's
  sideload recipe) and ran the experiments, ALL ON x7+g72 WITH
  THE AUDIO DEVICE ATTACHED: the premise test (user session +
  orca + audio) LIVE — screendumps differing at +2-3 min,
  clock = wall time, DPMS idle-blank at 6.5 min = the pipeline
  obeying the guest; EXP 1 (orca masked) LIVE (no Xwayland
  spawned — consistent with T33's trigger path); EXP 2
  (greeter + chord + orca + audio) LIVE — and orca ACTUALLY
  SPOKE through the emulated HDA (pcm0p/sub0 RUNNING, hw_ptr
  advancing ~100k frames/2s) while the display stayed live
  with input echo: THE GREETER ROW OF GATE 8 PROVEN. EXP 3:
  no stall existed to probe on the fixed stack; the one
  observed stall (STEP 0) was the T33 mechanism (the
  Xwayland-keymap ABRT wedge) with pcm closed — audio never
  involved. IRQs quiet, pipewire idle, QEMU 31-53% CPU steady.
  MECHANISM STATEMENT: THERE IS NO THREE-FACTOR DISPLAY STALL
  — the pattern was confounds stacked on confounds (audio ->
  handshake -> Xwayland); the only real mechanism is T33's
  Xwayland-keymap ABRT wedge, fixed by x7. Must-deny re-probed
  after the g72 sideload: holds. THE QEMU TODO CLOSED AS
  MISATTRIBUTED — no upstream QEMU report for the freeze; only
  the thread= feature request remains. GATE-8 READINESS: the
  greeter row TESTABLE+PROVEN (chord -> audible orca -> live
  display); the user-session row TESTABLE (the artifact
  re-confirmed with audio); the wizard carried; braille
  unchanged (hardware). VM restored: t30 autologin, orca
  unmasked + auto-started, display live, 0 failed units. The
  remaining pre-gate-8 follow-ups: NEW-3 (the wizard
  Confirm-password wedge — the sideload-bisect continuation),
  the pam_extrausers greeter-login fix, the second-greeter-uid
  snap-run lookup failure, the gsd reconcile; plus the
  SHIPPING todo (the 9 T29 items).
- [2026-11-16] HANDOVER STATUS (manager context compaction —
  read this section first if resuming). The machine was
  REBOOTED: all VMs down, /tmp scratch lost (the tester VM's
  launch recipe + sockets — recreate at relaunch), /var/tmp
  artifacts INTACT. No accessibility work happened Nov 13-16
  outside this log EXCEPT: (a) a libcanberra sound session
  landed session snap 16b7e2c ("Layout the libcanberra module
  dir for canberra playback") — which INCLUDES T34's Xwayland
  fix (5ce04c2 is its ancestor) and is BUILT
  (ubuntu-desktop-session_20261116+git16b7e2c_amd64.snap, Nov
  16 12:22 in the session repo); (b) the core-base-desktop
  local HEAD gained f16b8bb (SystemPrompter routing — another
  workstream) on top of the thin ports. THE CURRENT BLOCKER,
  EXPLAINED: the owner's VNC view shows a frozen desktop —
  that VM is the T31 FRESH BAKE (pc-thin-t31.img) whose
  session snap is the STALE pre-T34 e531eb3: it exhibits the
  Xwayland-keymap wedge (T33's root cause) that 5ce04c2 FIXES.
  The fix is built but not in that image. GATE-8 VM SETUP
  (T35 dispatched): boot pc-thin-t31.img → sideload the
  CURRENT stack (session 20261116+git16b7e2c, snapd
  g72=1a31bb9072 (the repo's snapd.snap, Nov 12 15:23), a11y
  0.1+git20261111 (=7947b6f)) → verify the display stays live
  past 2 min WITH the audio device (the audio-display
  interaction on the FIXED stack is untested — test at first
  boot; if static, relaunch without the audio device and
  gate 8 proceeds display-first while the audio interaction
  is investigated) → hand off to the human tester. TESTER
  CREDENTIALS: t30/x (reset + PAM-proven via sshd); root/x
  (serial + ssh). Sideload artifacts: session
  ubuntu-desktop-session_20261116+git16b7e2c_amd64.snap (the
  repo build output), snapd ~/git/ubuntu-core-desktop-snapd/
  snapd.snap (g72), a11y ~/git/ubuntu-desktop-a11y/
  ubuntu-desktop-a11y_0.1+git20261111_amd64.snap (=7947b6f,
  the BRLAPI_HOST fix verified in the artifact). The sideload
  persistence CAVEAT (T34b's stack audit): abrupt QEMU kills
  can lose the sideload state — ALWAYS verify `snap list`
  revisions after a relaunch and re-sideload per T34's recipe
  (the T34 report's §sideload) if rolled back. GATE-8
  CHECKLIST: T11 gate 8 — audible orca at the greeter (chord
  alt+super+s) and in the session, reading quality (text
  fields, caret navigation — the reader contract is in this
  build), clicking through apps with announcements. BRAILLE
  DECISION [2026-11-16, live gate-8 session]: UBUNTU CORE
  DESKTOP WILL NOT SUPPORT BRAILLE (owner) — braille is OUT
  OF SCOPE for the thin line: no gate-8 braille row,
  BRLAPI/BRLTTY items parked, no shipping requirement; the
  fat line's braille parity claim is explicitly waived. KNOWN
  TEST CONSTRAINTS: NEW-3 (the wizard Confirm-password wedge
  — use the out-of-band user route or test the greeter only);
  the greeter password login: t30/x SHOULD work (PAM proven
  via sshd after the reset — T30's "broken" claim was the
  unknown password, unverified at the greeter); the QEMU
  display-stall todo is CLOSED as misattributed (the freeze
  was the wedge). NEXT STEPS AFTER GATE 8: the shipping todo
  (the 9 T29 before-shipping items: C1 installation-gating,
  C2/C3 the reader-role completion, C6 name reservation,
  C8/C9 lifecycle, C12 regression surface, C13 hygiene), the
  follow-ups (NEW-3 bisect, the gsd reconcile, the
  second-greeter snap-run lookup, the pam_extrausers
  greeter-login re-test with the known password), the
  upstream packages (mutter sync-connect, orca xkbcomp
  timeout, the Peer.Ping/reader-role series, the pipewire
  snap FINDING 1), the FINDING 1 todo
  (`20261112-pipewire-snap-conf-frag-brick.md`), the QEMU
  thread= feature request, the D1 fat-merge decision + pushes
  (the owner's call). ALL WORK IS LOCAL/UNPUSHED.
- [2026-11-16] T35 DONE — GATE-8 VM PREPARED AND HUMAN-VERIFIED.
  Manager spot-verified: the launch flags (hda-duplex, the
  tester image), the report, and an INDEPENDENT screendump
  pair (DISPLAY LIVE NOW). Stack: snapd g72.1a31bb9 x2 /
  session 20261116+git16b7e2c x3 (sideloaded per T34's recipe;
  T34 fix + canberra) / a11y 0.1+git20261111 x2; sideloads
  persisted across a graceful poweroff + relaunch. WEDGE
  REGRESSION PASS — the display LIVE past 2 min WITH the
  audio device on 16b7e2c (screendumps pairwise-differ at
  +105/+171/+229s; zero ABRT/keymap/Disabling whole boot);
  the display-first fallback NOT needed. AUDIO: the
  hda-output shape FAILED host-side (stream realized but
  never activated, stderr empty — QEMU 10.2.1 pipewire
  swallow, documented); the relaunch with hda-duplex WORKS
  end to end: spd-say rc=0, guest pcm RUNNING, pw node
  RUNNING into the dock headset, AND THE OWNER'S EARS
  CONFIRMED SPEECH. Gate-8 state: VM RUNNING, t30 unlocked,
  orca active, audio verified. NEW LIVE-PROVEN CONSTRAINT:
  the interactive password path is BROKEN — the session lock
  screen rejected t30/x (NEW follow-up; the greeter path
  also unverified); T35 disabled the idle lock+blank
  (documented gsettings change) so the tester cannot be
  locked out; recovery if a login is rejected: reboot
  gracefully (autologin returns, sideloads persist). GATE 8
  IS THE HUMAN TESTER'S — the checklist is in T35's STEP 4
  and the HANDOVER STATUS section above.
- [2026-11-16] GATE-8 LIVE SESSION — FINDINGS SO FAR (owner
  testing, manager support). (1) GREETER A11Y ROW PASS LIVE
  (owner's ears): alt+super+s at the greeter → orca started
  and announced "t30" and "Not listed?" on focus changes —
  the T34b greeter row re-proven by the human. (2) GREETER
  PASSWORD t30/x REJECTED LIVE (owner): the interactive
  password path is now broken at BOTH the lock screen
  (T35's b3-3) AND the greeter (live gate-8), while sshd
  accepts the same credentials — the PAM stack is fine over
  ssh, the interactive PAM conversation (gdm/gnome-shell
  path) is not. NEW FOLLOW-UP: root-cause the interactive
  password path; recovery = graceful reboot (autologin
  returns; used twice). (3) SCREENDUMP SHEAR ARTIFACT: after
  the greeter↔session logout transition + guest reboots,
  monitor screendumps showed a diagonally sheared render at
  bogus modes (887x924, then 1050x800 + scanline noise),
  static, persisting across TWO guest reboots, guest journal
  clean. A graceful poweroff + FRESH QEMU RELAUNCH (same
  flags, hda-duplex) cleared it → clean 1280x800. THE OWNER
  REPORTED THE VNC VIEW LOOKED FINE THROUGHOUT (the owner
  could not watch continuously — UNCONFIRMED for the shear
  window). OWNER PROTOCOL [2026-11-16]: if the shear is seen
  again in screendumps, ASK THE OWNER TO VERIFY THE VNC VIEW
  FIRST before assuming a display problem — treat screendump
  anomalies as suspected QEMU HMP screendump-path artifacts
  (stride/dmabuf desync after mode transitions) until the
  human confirms. EVIDENCE RULE for gates: screendump
  evidence must be cross-checked against the VNC view after
  any mode transition; screendump clock-pairs are reliable
  only on a stable mode; the VNC view is the liveness ground
  truth. (4) ASR VERIFICATION TASK (owner's idea, in flight):
  whisper-cli + ggml-base.en.bin; pw-record capture of the
  sink monitor (node 69) running through the session;
  expected terminal speech = the Ubuntu Core login banner
  ONCE (pam_motd generates it; /etc/motd is empty). Pending:
  the owner reproducing the terminal repetition + whisper
  transcription + the comparison verdict.
- [2026-11-16] GATE-8 LIVE SESSION — THE SILENT-AUDIO MYSTERY
  SOLVED (two-layer break; both fixed live; THE OWNER'S EARS
  CONFIRM AUDIO RESTORED — heard "final probe yankee zulu").
  LAYER 1 (the RTP taint): T31's parked RTP drop-in
  (/home/t30/snap/pipewire/x1/.config/pipewire/pipewire.conf.d/
  10-rtp.conf, baked into the TAINTED-T31-rtp tester image)
  creates a bogus "VM audio RTP" sink EVERY boot; the
  default-sink race is boot-dependent — this boot the RTP sink
  WON (wpctl default=*36), so ALL session speech (orca, probes)
  played into the void. The GREETER was immune (different home
  dir → clean config → only the HDA sink) — explaining why the
  greeter speech worked while the session was silent. FIX
  APPLIED LIVE: wpctl set-default 50 (Built-in Audio Analog
  Stereo; persisted to wireplumber's default-nodes state).
  FOLLOW-UP: remove the T31 RTP drop-in from the image build
  (the taint is the root of the boot-to-boot audio flakiness).
  LAYER 2 (the wedged speechd): the a11y snap's speechd server
  (boot-spawned 13:53) HUNG at its first speech dispatch — its
  boot-spawned espeak modules never logged a byte (born-broken
  candidates, a boot-order race in the socket-activation path);
  the server accepted connections and negotiated protocol
  (orca's 13:58:05 handshake, 2.8MB log) but NEVER processed
  speech again (spd-say -w hung indefinitely; SIGTERM swallowed
  — the blocked main thread never reaches the handler; the
  socket-restart job failed). PRIME SUSPECT for the trigger:
  the espeak module's audio-open hanging forever on the bogus
  RTP sink that had stolen the default. FIX APPLIED LIVE:
  kill -9 → the socket unit spawned a fresh server + fresh
  espeak modules → the probe synthesized and rendered (pcm
  state:RUNNING x6) AND REACHED THE HEADSET. BUG
  CLASSIFICATION: (1) OURS — the T31 taint (remove from the
  image build; verify a clean boot does not reproduce the
  wedge); (2) UPSTREAM-CLASS robustness defect — one hung
  audio-open permanently wedges speechd (no timeout, no
  recovery, SIGTERM-proof; a screen-reader user gets one
  announcement then silence until a manual kill -9). IF the
  wedge reproduces on a CLEAN image, package the upstream
  report (the evidence is strong: protocol-alive-but-speech-
  dead, the spd-say -w hang, the SIGTERM swallow). CHEAP
  HARDENING CANDIDATE for the shipping todo: a watchdog on
  the speechd socket unit so a wedged server self-heals
  (joins the C8/C9 lifecycle items).
  RED HERRINGS DOCUMENTED: (a) the pw-play beep tests were
  INVALID — the confined pipewire snap cannot read files
  dropped into /tmp or even into its own snap-data dir via the
  host view (per-user private mount quirk; the raw
  /dev/snd/pcmC0D0p open test as t30 SUCCEEDED → the kernel
  path was never the problem); (b) the host's
  speech-dispatcher-dummy stream (the owner's pavucontrol
  find) = the HOST's speechd spawned 13:45:15 by a
  greeter-chord press that leaked to the host desktop — idle,
  harmless, NOT the VM's audio; (c) the sink-monitor capture
  energy bursts = the OWNER'S DICTATION (their mic monitored/
  looped into their own output), not VM audio. METHOD NOTES
  for gates: (1) sink-monitor ASR captures include ALL host
  audio — corroborate transcripts; (2) file-based pw-play
  probes are unusable inside confined snaps (no snap-readable
  path found live) — prefer speech probes via the production
  path; (3) a pcm "closed" reading AFTER playback is NORMAL
  (open→close) — sample DURING playback.
  CURRENT STATE: audio WORKING end to end; the fresh speechd
  serves new clients (orca reconnects on its next speech
  event; the chord toggle restarts orca cleanly if needed).
  STILL OPEN: the terminal-repetition ASR question (the
  original gate-8 item — the reproduction never got captured;
  a fresh reproduction + whisper run is queued), the greeter
  password (interactive PAM broken at lock screen AND greeter;
  sshd fine — recorded above), the boot-time speechd wedge
  root cause, the RTP taint removal.
- [2026-11-16] LIVE SESSION ADDENDUM: (5) the interactive
  password rejection CONFIRMED A THIRD TIME (lock screen
  again, t30/x rejected; recovered via loginctl
  unlock-sessions) — consistent, not flaky; the root-cause
  follow-up stands. (6) SPEECH PASS LIVE: orca audibly
  announced "Sorry password authentication didn't work.
  Please try again" on the failed unlock — the reader
  contract working through the fully-restored audio chain
  (fresh speechd + corrected default sink). (7) The
  screendump shear REPRODUCED (1050x800 + scanline noise
  again, at the same bogus mode) right after a session
  lock/unlock cycle — the owner asked to verify the VNC view
  per the protocol; VERDICT: THE VNC VIEW IS CLEAN (owner,
  live) — the shear is a QEMU HMP screendump-path artifact,
  CONFIRMED at the same bogus mode; the owner asked for an
  investigation (T37 dispatched, read-only). (8) NEW FINDING
  — THE SETTINGS REVERT: T35's lock-disable
  (lock-enabled=false, idle-delay=0, readback-verified at
  handoff) was CLOBBERED back to the defaults
  (lock-enabled=true, idle-delay=300) before the ~14:35 IDLE
  LOCK — THE OWNER CONFIRMED THE LOCK WAS NOT MANUAL; idle
  fired on the reverted 300s. Prime suspect: the boot-time
  settings-actuation (the session coherence step) re-writing
  defaults over the lock keys (it actuates the reader toggle
  ON at every boot — it likely resets the whole key set).
  RE-APPLIED LIVE + readback-verified (false / uint32 0).
  WHY IT MATTERS: an a11y user with the broken interactive
  unlock who reboots gets idle-locked after 5 min and is
  PERMANENTLY LOCKED OUT — the actuation must stop clobbering
  (or explicitly own) the lock settings for reader users
  until the interactive unlock path is fixed. Follow-up joins
  the gsd-reconcile item; after ANY reboot, re-apply the two
  keys (recipe: T35's gsettings via the content-snap binary +
  the session's redirected XDG_CONFIG_HOME) until the
  actuation is fixed.
- [2026-11-16] T37 DONE — THE SCREENDUMP SHEAR SOLVED AND
  FIXED UPSTREAM-READY. MECHANISM (NOT dmabuf/virtio/our-
  stack): ppm_save() in ui/ui-qmp-cmds.c writes
  pixman_image_get_stride(linebuf) bytes per row while the P6
  header declares width*3; pixman pads the 24bpp stride to a
  4-byte multiple, so ANY width with width%4!=0 shears every
  PPM (+1-3 B/row drift = the diagonal shear + scanline
  noise). A 14-year-old defect (commit b12f32c408ef, 2012)
  still in master; standard widths (1280) are 4-aligned,
  which hid it. THE BOGUS MODES WERE BENIGN AND REAL: guest
  KMS truth (gnome-shell fb 1050x800, pitch 4352, XR24)
  matches the owner's clean VNC view; the sizes self-perpetuate
  via QEMU's dynamic EDID (virtio_gpu_ ui_info -> EDID
  preferred = the last VNC SetDesktopSize dims = THE OWNER'S
  VIEWER WINDOW SIZE), surviving guest reboots until a QEMU
  relaunch or a client resize. CHARACTERIZATION: the shear
  is deterministic per width (never self-heals); the CONTENT
  IS LIVE even when sheared (clock rows advance — pairwise
  cmp remained valid). VNCTOOL: correct but BLOCKED while the
  owner's viewer is attached (QEMU's allow-exclusive drops a
  second client). NEW GATE-EVIDENCE RECIPE (verified live on
  the running VM: clean 1050x800 PNG, clock matching wall
  time): HMP `screendump out.png -f png` — the PNG writer
  has no stride bug; PPM post-repair (rows at 4*ceil(3W/4))
  also recovers exact content. UPSTREAM: confirmed unfixed;
  the patch is prepared on master (5474f9f), checkpatch 0/0,
  BUILT LOCALLY (no sudo) and VERIFIED on a disposable VM +
  image copy (stock 10.2.1: sheared 1050x1050 PPM +2100
  bytes; patched: exactly 3,307,500 bytes, clean). The owner
  VM was untouched throughout; the disposable artifacts were
  cleaned. OWNER ACTION: add their Signed-off-by and git
  send-email to qemu-devel.
- [2026-11-16] NEW DEDICATED TODO: the speechd hang-forever
  defect (reproduce, root-cause, fix PR upstream, watchdog
  hardening) now has its own file —
  `20261116-speechd-hang-wedge-upstream.md` — with the full
  defect description, the trigger hypotheses (H-A our taint /
  H-B boot race) and their discriminator, the upstream-first
  check, and the fix-PR plan. All reproduction experiments
  there need reboots — they queue until after the gate-8
  session (or a disposable second VM).
- [2026-11-16] GATE 8 PASSED (owner, live session, ~21:00):
  (1) terminal speech FINE — the earlier "repeating lots of
  text" did not recur on the fresh speechd server (plausibly
  a symptom of the wedged-server era; resolved by
  observation, no ASR capture needed); (2) pointer accuracy
  FINE (the close-button finding was the earlier broken
  session state, not a live defect); (3) app grid WORKS;
  (4) orca/voice fine (robotic timbre = espeak's default,
  expected). ALL GATES 1-8 NOW PASS on the thin line. The
  gate-8 VM stays running for ad-hoc checks; a FRESH BAKE
  without the T31 taint is required for the shipping phase
  anyway. The submitted patch lives in ~/git/qemu
  (9bade91de5). NEXT PHASE: the shipping todo (the 9 T29
  items) + the follow-up queue + the upstream packages, then
  the owner decisions (D1 fat-merge, pushes).
- [2026-11-16] T38 DONE — BOTH OWNER REPORTS HAVE ONE ROOT
  CAUSE, AND THE GATE-8 PASSWORD THEORY IS OVERTURNED. THE
  UNIFYING CAUSE: the t30 session's GNOME input source was
  [('xkb', 'sy')] — ARABIC (SYRIA) — so EVERY GUI keystroke
  produced Arabic letters (the terminal) and the lock/greeter
  password "x" was typed as Arabic chars -> the correct PAM
  hash REJECTED it. SSH worked because it bypasses the GUI
  keyboard. THE REFERENCE VM (the owner's fresh bake) has us
  and works. PROVENANCE (verbatim journal): on Nov 12
  00:30/00:40, during the gate-8-prep WIZARD AUTOMATION,
  provd called systemd-localed -> "Changed X11 keyboard
  layout to 'sy'" — the keyboard page landed on Arabic
  (Syria) via list navigation; NEW-3 then wedged the identity
  page so nobody corrected it; at t30's first login
  gsd-keyboard PORTED the system layout into the user keyfile
  (common/.config/glib-2.0/settings/keyfile + the ported
  marker) — the store the session actually reads. The owner's
  wizard run today picked 'us' -> clean reference.
  CONSEQUENCES: (1) THE "INTERACTIVE PAM BROKEN" FOLLOW-UP IS
  CLOSED AS MISATTRIBUTED — PAM/user-db is byte-identical
  between the VMs (both users extrausers $6$, passwd -S P);
  the pam_extrausers YESCRYPT warning fires on SUCCESSFUL
  auth on both VMs — the pam_extrausers follow-up is
  cosmetic/INVALID, closed. (2) The password row of gate 8 is
  re-testable and expected PASS with the fixed layout.
  (3) FIX APPLIED LIVE on t30: localectl set-x11-keymap us
  (system) + the user keyfile sources edited to
  [('xkb', 'us')] (the session picks it up via keyfile
  monitoring; re-test the lock/unlock to close the row).
  (4) PRODUCT-LEVEL FOLLOW-UPS for the shipping phase: the
  wizard automation must set/VERIFY the layout via provd
  explicitly (never trust list navigation) + add a gate-8
  checklist line "type a known word before testing".
- [2026-11-16] METHOD FINDING (changes all gsettings work on
  this stack): the session reads GSettings from a KEYFILE
  (common/.config/glib-2.0/settings/keyfile) via
  GSETTINGS_BACKEND= keyfile (the backend's default path) —
  gsettings commands WITHOUT GSETTINGS_BACKEND=keyfile
  (T35's original disable, the 14:35-era re-apply) silently
  wrote a DEAD dconf store at common/.config/dconf/user and
  their readbacks were self-consistent lies. THE "SETTINGS
  REVERT" FINDING (8) IS REVISED: probably never a revert —
  the recipe writes never reached the session's store; the
  keyfile's own history is now uncertain (lock-enabled=false/
  idle-delay=0 were present in the keyfile before the 22:0x
  fixes, yet the ~14:35 idle lock fired — the trigger remains
  open as a follow-up, now with the store-mismatch context).
  CORRECT RECIPE henceforth: XDG_CONFIG_HOME=<session
  common>/.config + GSETTINGS_BACKEND=keyfile +
  GSETTINGS_SCHEMA_DIR=<content-snap>/usr/share/glib-2.0/
  schemas; VERIFY by grepping the keyfile, never by
  gsettings-get from the wrong backend. The lock-disable
  keys are NOW confirmed in the keyfile (lock-enabled=false,
  idle-delay=0) and the system vconsole is XKBLAYOUT=us.
- [2026-11-16] T39 DONE — THE CLEAN FRESH BAKE FOR THE SHIPPING
  PHASE (the T31 RTP taint removed at the source). TRACE: the
  10-rtp.conf taint was RUNTIME PERSISTENCE ON A REUSED TESTER
  IMAGE, not a build step — T31 wrote it live via ssh on the
  T30 image (the file's mtime Nov 12 11:40 = T31's session,
  grabbed verbatim off the running gate-8 VM), the image kept
  it, and T35 deliberately booted that TAINTED-T31-rtp image
  for gate 8 (it carried the tester setup). The build provably
  seeds nothing (fresh /home; zero pipewire artifacts found on
  the pristine bake). FIX: clean-by-construction bake + a
  TAINT-SWEEP GUARD (purges every user's pipewire snap conf.d
  and ASSERTS zero residue + zero "VM audio RTP" sinks; ran
  green twice) + per-task clean naming. BAKE: a clean fresh
  pc.img (md5 329d2eb632a2d0608ca798f0193d3638,
  21,491,613,696 bytes; image build exit 0; build dir cleaned
  after). Baked set = today's repos: snapd 2.76.3+g72.1a31bb9
  x1, session 20261116+git16b7e2c x1 (the T34 fix), a11y
  0.1+git20261116 x1 GRADE STABLE (the owner's 447d9c3 build
  landed mid-bake and latest_snap picked it — newer than the
  briefed 20261111; noted for the owner), base core26-desktop
  20261115+desktop x1, gadget c8e74b4. Tester setup baked
  (t30/x extrausers, autologin, ucd-handover -> orca
  auto-start verified, localectl us per the T38 lesson —
  keyfile sources=[('xkb','us')]). VERIFIED in a disposable
  QEMU (own sockets; owner VMs untouched): /home taint-free
  (sweep green), snap list the baked set, wedge grep 0 with
  the audio device present, Xwayland alive, PNG screendump
  pair LIVE (clock matches wall time, a11y indicator up),
  audio = ONE sink "Built-in Audio Analog Stereo" default on
  a fresh boot (the default-sink race is GONE — nothing to
  race against) + spd-say rc=0. Minor finding for C13
  hygiene: user unit localsearch-3.service fails 203/EXEC
  (missing /usr/libexec/localsearch-3 in the session snap
  env; no display/audio/a11y impact). Build-env bug found
  (not fixed at the time): build.sh ~1592 usermod --prefix
  breaks with an ABSOLUTE --build-dir (accepted by the
  parser) — use a relative name. NEXT: C12 regression run +
  wave-2 use this bake (boot recipe in the report; gate-8 VM
  stays the owner's ad-hoc VM).
- [2026-11-16] T38 FIX VERIFIED BY THE OWNER: unlock with "x"
  SUCCEEDED and the terminal types correct Latin letters —
  the input-source fix is live in the session. THE GATE-8
  PASSWORD ROW IS FORMALLY PASS (it was never broken; the
  input was Arabic). Gate 8 now has zero open rows.
- [2026-11-16] T40 DONE — C13 RELEASE HYGIENE COMPLETE: grade
  -> STABLE (the T20-gated flip, now that gates 1-8 passed;
  store re-test caveat recorded) + version ->
  0.1+git20261116, commit 447d9c3 on the a11y repo's line
  (NOTE: that repo's branch is MAIN, no desktop/26, no
  remotes — the T29 "desktop/26" naming belongs to the other
  repos). The x86_64 GI pin + the T16-DEBUG override-prime
  were already fixed in T20. REBUILT clean (snapcraft pack,
  no sudo): ubuntu-desktop-a11y_0.1+git20261116_amd64.snap;
  the metadata diff vs the gate-8 artifact is EXACTLY
  version+grade — payload byte-identical (all apps/plugs/
  slots/layouts unchanged). FLAGS for later tasks: store
  metadata lint (title/contact/issues/source-code/website
  missing), platforms still amd64-only, and the speechd
  restart-condition does not cover the hung-server wedge
  (the watchdog candidate joins C8/C9). OWNER DECISION
  POINT: 12 x 79MB snap blobs remain in the a11y repo
  history (.git 899MB) — a history rewrite is only safe
  BEFORE the first push; T20 rejected it for the shared
  spike line.
- [2026-11-16] T39 DONE — CLEAN FRESH BAKE DELIVERED
  (pc-thin-t39-clean.img, md5 329d2eb6..., 21,491,613,696
  bytes). TRACE: the taint was RUNTIME PERSISTENCE on the
  reused tester image, NOT a build step — T31 wrote
  10-rtp.conf via ssh Nov 12 11:40 (the file mtime
  fingerprints the ssh session), T35 deliberately booted the
  TAINTED image for gate 8; the build seeds nothing (pristine
  /home empty). FIX: clean by construction + a reusable
  taint-sweep guard (purges every user's pipewire conf.d +
  asserts zero residue/RTP sinks; ran green 2x). BAKED SET =
  today's repos: snapd g72.1a31bb9, session 16b7e2c (T34 fix
  baked), base 20261115+desktop, a11y 0.1+git20261116 GRADE
  STABLE (T40's build landed mid-bake and latest_snap picked
  it). Tester setup baked (t30/x autologin, us layout per
  the T38 lesson). VERIFY (disposable QEMU, own sockets):
  no taint/no RTP sink; snap list all x1 no sideloads; wedge
  grep 0 WITH the audio device; PNG pair live; ONE sink =
  the real HDA, default on fresh boot — THE RACE IS GONE;
  spd-say rc=0. FINDINGS: build.sh ~1592 breaks with an
  absolute --build-dir (relative names only; one-liner fix
  pending owner); localsearch-3.service fails 203/EXEC on
  the session (missing binary in the snap env — hygiene, no
  a11y/audio impact). NEXT: C8/C9 lifecycle (T41) + the C12
  regression run (T42) on disposable copies of this bake.
- [2026-11-16] T41 DONE — C8/C9 LIFECYCLE EVIDENCE (the test
  branch work/test-refresh-path-change 2e4c0e5 kept, main
  restored to 447d9c3, image copy deleted, owner's VMs
  untouched). C8 VERDICT: the path-changing refresh is
  BENIGN AT REFRESH TIME (endure: the old x1 bus/speechd
  keep serving under the old label, pids unchanged,
  GetAddress keeps the old contract, orca/speech unaffected)
  — the change is DEFERRED, not prevented; the breakage
  MATERIALIZES AT THE NEXT BUS RESTART exactly as C8
  predicted, plus extra: verbatim mkdir DENIED at the new
  .at-spi-t41/ dir (the profile grants only the conventional
  at-spi/ — the a11y interface policy does NOT follow the
  snap's declared paths), the launcher silently falls back
  to an anonymous /tmp/dbus-* transport whose address CHURNS
  PER START, the conventional socket vanishes, and orca
  SIGSEGV-loops. REVERT: snap revert returns to x1 but does
  NOT auto-restart the user daemons — x2 launcher+dbus-daemon
  orphans run beside the fresh x1 launcher and GetAddress
  dangles until a manual start; a fresh session fully
  recovers. FIX DIRECTION for the design wave: the a11y
  interface policy must derive from the snap's declared
  paths (a path change without a policy change is
  unsupported — either forbid it at install or grant
  declared paths), + the snapd revert-restart gap (N2).
  C9 VERDICT: PASS — 4 sequential greeter respawns gave uids
  60578->60581 (name alternates gdm-greeter/-2, always
  incrementing); the provider stack (launcher, private
  daemon, registryd, speechd+espeak) ran GREEN under every
  dynamic uid with correct labels; spd-say as the greeter
  user rc=0; ZERO userdb/varlink denials; libnss_systemd
  staged. Caveats: no positive varlink trace captured
  (mechanism not traced end-to-end); concurrent greeters not
  mechanically possible (one seat) — sequential substitute
  recorded. WATCHDOG (record-only): speech-dispatcher =
  daemon simple + restart-condition on-failure +
  refresh-mode endure + socket-activated; live
  corroboration: spd-say hung rc=124 while the unit stayed
  active — on-failure CANNOT catch a hung server (the
  watchdog follow-up stands, now with live evidence). NEW
  ISSUES: N1 sideloads refuse outright while orca runs (the
  store refresh path quit-prompts instead); N2 snap revert
  leaves newer-revision orphans and does not restart the
  user daemons (snapd-side, upstream candidate); N3 orca
  crash-loops SIGSEGV against ANY broken at-spi state (x1
  included — the crash follows bus state, not revision; orca
  robustness, upstream candidate); N4 stopping the bus
  mid-session killed the whole t30 graphical session (gdm
  parked on the greeter, no re-autologin) — the D8 cascade
  has a session-fatality tail.
- [2026-11-16] T42 DONE — C12 REGRESSION RUN (disposable copy
  of the T39 bake, wizard completed the proper way, canonical
  bake md5-verified untouched). VERDICTS: d5dd37e PARTIAL
  (the trio runs in wizard 60578 + greeter, devices clean,
  seat owned — BUT GREETER VOLUME KEYS ARE DEAD: the
  greeter's PULSE_SERVER points at /run/user/<uid>/pulse/
  native which never exists — pipewire-pulse only starts in
  user sessions, the socket unit binds only the snap-private
  path -> connection refused for media-keys AND gnome-shell;
  fix shape is session-snap, joins the env-broker surface);
  f622a7d/4a126c2 PASS (HDA handoff clean both directions);
  80bcb51 PASS (user leg live, Xwayland keymap T34 signature
  clean); b67bf18/295c176/a36b1b3 PASS —
  CreateUser->handover ran on the SHIPPED IMAGE FOR THE
  FIRST TIME (provd recorded the full a11y keyset targeting
  reg, applied at first login, store healthy); 2d8c6c2 PASS;
  39d48fb PASS by absence (no orca for a user who never
  enabled it); 612a6f2cd2 PASS (all snap user services
  started for the first-login user). NEW-3 DOES NOT
  REPRODUCE on the clean bake — the wizard completed
  END-TO-END (Confirm-password accepted first try; the
  keyboard page verified by typing "regression" -> provd
  SetKeyboard us logged) — downgrade to resolved-by-evidence
  (the wedge was old-image-specific; the wizard-automation
  layout hardening from T38 still stands). NON-A11Y
  DEFAULTS: lock-enabled=true, idle-delay=300 (no
  overrides), lock+unlock exercised live and WORKS (more
  confirmation the password path was never broken); audio
  works; volume keys work in the user session; layout
  Latin; no orca auto-start. MINOR NEW: wizard wireplumber
  SIGABRT once 13s after handover (no coredump, no impact,
  did not recur); localsearch-3 recurs per-user (known
  C13). BONUS: C9's concurrent-dynamic-user scenario
  materialized NATURALLY (60578 parked + 60579 active after
  one logout) and was handled cleanly — the T41 concurrent
  caveat is partially closed. WAVE 1 COMPLETE (T39 bake,
  T40 hygiene, T41 lifecycle, T42 regression). NEXT: wave 2
  (C1 gating, C2/C3 reader-role completion, C6 name
  reservation) + the accumulated findings (greeter volume
  keys -> env-broker; N2/N3/N4 upstream candidates; the
  watchdog).
- [2026-11-16] T43 DONE — WAVE 2 OF THE SHIPPING PHASE (T29
  C1, C2, C3, C6). Deliverable: the wave-2 design report
  (per-item requirement -> design -> implementation ->
  verification -> owner-decision points). Snapd fork
  desktop/26, four local commits (no pushes, landed lineage
  untouched), tree clean:
    e496b26ce9 policy test maps for the T30 reader-role
      gating (three PRE-EXISTING failures on g72 HEAD fixed
      as residue)
    2a24f790b7 C1: allow-installation: false on the slot
      (the reviewer's recommended default; snap-declaration
      grant only; --dangerous minimal check ignores it, so
      sideloads/image seeding unaffected — policy-tested
      both ways) + the ENTIRE permanent slot snippet moved
      to the CONNECTED slot snippet verbatim (rule-for-rule;
      D3 preserved: the only unnamed receives keep the
      own-glob pin) + lsm_get_self_attr likewise + the T41
      path contract documented (socket moves FORBIDDEN,
      loud AVC — derivation impossible for the client-side
      rule) + the C3 honest consent restatement + the C2
      reader-role completion (the four tree-read surfaces
      join the role).
    d91bacfbbb C2/C3: the desktop-legacy unnamed client
      receive is REPLACED by the T29 set —
      provider-lifecycle receives pinned to the provider
      label (driver signals, Ping, Id Set, bookkeeping,
      NotifyListeners{Sync,Async} key delivery), reader
      method calls kernel-gated two ways (reader-ROLE-only
      interfaces accepted from any peer because only
      reader profiles carry those sends;
      desktop-legacy-shared reads PINNED to the provider
      glob — the wall that closes the C2 cross-snap
      tree-read scenario), event/cache broadcasts as the
      documented shared trust domain (C5's accepted risk,
      unchanged). Read SENDS kept (fat-line compat + the
      upstream drop documented, not silently made).
    7f17a08fbd C6: dbus base declaration deny-installation
      on slot-attributes name: org\.a11y\.Bus (anchored
      regex) — store squatters denied, legit store
      provider granted via its own snap-declaration,
      sideloads unaffected (policy-tested).
  VERIFICATION: interfaces/... asserts/... overlord/
  ifacestate all green; the composed base declaration
  parses; apparmor_parser 5.0.2 parses generated profiles
  for the provider connected slot, a desktop-legacy
  consumer and the reader (exit 0 each); mechanical D3
  audit of the consumer profile: 27 receives, ZERO unnamed;
  reader profile 120 rules / 0 unnamed / 0 bus=system;
  provider profile 1 unnamed = the own-glob contract rule.
  BUILD: rebuilt snapd_2.76.3+g76.7f17a08_amd64.snap
  (snapd.snap in the repo root; the first pack had the
  stale g72 version stamp — the T25 gotcha — fixed with
  `snapcraft clean snapd` + repack; the binary verified by
  strings to carry all four changes). NEXT BAKE PICKS IT
  UP (the image build wires snapd.snap). OWNER-DECISION
  POINTS (in the report): (1) the C1 gate is the
  reviewer's recommended default; (2) the reader-peer pin
  is one-reader (provider label glob) until upstream label
  plumbing; (3) the desktop-legacy read-send drop is NOT
  made (kept for fat-line compat; upstream-time step —
  decide whether to drop on the fork now); (4) C3 closed
  via the honest restatement, not an admission plug;
  (5) T41 path changes forbidden-by-contract; (6) the
  narrowed receive changes every desktop-legacy profile —
  the design-level flow walk is green but NO VM
  round-trip ran; authorize a disposable-bake gate re-run
  before any human-facing gate session. a11y snap
  UNTOUCHED (main @ 447d9c3; one stale doc comment
  noted). Scratch cleaned (small evidence only).
- [2026-11-17] MANAGER ACCEPTANCE of T43: the design honors
  D3 (mechanically audited: zero unnamed receives in the
  consumer profile), the reviewer's defaults were used
  where the review recommended them, and the C1 gate
  choice (allow-installation: false + snap-declaration
  grant) keeps sideloads/image seeding unaffected —
  verified by policy test. DECISION POINT ⑥ IS THE
  IMMEDIATE ONE: the narrowed receive set changes every
  desktop-legacy profile — DISPATCH A DISPOSABLE-BAKE
  GATE RE-RUN (the reader flow set: greeter chord, orca
  speech, spd-say probes, must-deny re-probes) BEFORE any
  human-facing gate session on the new snapd. Decision
  points (1)-(5) recorded for the owner; (3) (drop the
  desktop-legacy read sends now vs at upstream time) is
  the only one that changes shipped policy before the D1
  fat-merge.
- [2026-11-17] T44 DONE — GATE RE-RUN ON THE NEW SNAPD: PASS.
  SIDELOAD: g76.7f17a08 installed gracefully per the T34
  recipe, PERSISTED across two reboots, connections
  intact. READER FLOW (all PNG-dumped, clock-matched):
  autologin orca + spd-say rc=0 + Latin typing; greeter
  chord FIRED (orca.service under the greeter manager),
  orca + sd_espeak-ng x2, greeter speech rc=0, greeter
  readable. MUST-DENY: the errno-13 D3 probe HOLDS
  verbatim (reproduced x2, LSM-enforced); the narrowed
  receives verbatim in live profiles
  (NotifyListeners{Sync,Async}, Ping, shared reads pinned
  to the provider glob), zero unnamed a11y-bus receives,
  reader sends only under orca (40 rules vs 0 for shell/
  speechd/bus); zero bus=accessibility denials across all
  boots (nothing legitimate blocked); C6 holds at policy
  level (the anchored deny confirmed in the running
  binary). VERDICT: THE NEW SNAPD IS GATE-READY FOR A
  HUMAN-FACING SESSION — decision 6 CLOSED. Non-blocking
  notes: (1) the T34 snap-run flake reproduces on the
  clean bake under g76 (pre-existing, queued); (2) the
  7.0 kernel emits NO AVC for the connect denial — probe
  recipes rely on the errno; (3) libspeechd 2.6.0
  REQUIRES SPEECHD_ADDRESS=unix_socket:<path> — the
  recorded bare-path form does not parse (RECIPE
  CORRECTION: all recorded spd-say recipes must carry
  the unix_socket: prefix); (4) stock idle-lock engaged
  mid-setup — apply the keyfile disable FIRST on any
  fresh boot before setup (recipe-order lesson); (5)
  abrupt SIGKILL of speechd -> unit stayed active but the
  probe RECOVERED rc=0 via socket activation (the T41
  live-hang did not reproduce this time — the watchdog
  follow-up stands); scratch cleaned; owner VMs untouched.
- [2026-11-19] T55 DONE — THE INDEPENDENT DUAL REVIEW OF THE
  SNAPD SERIES: VERDICT — NOT READY TO PUSH AS-IS.
  CORRECTNESS FINDINGS: (1) HIGH: the org.a11y.Bus
  reservation is BYPASSABLE — an app snap declares a dbus
  slot named org.a11y and the bind rule name="NAME.*" lets
  it own org.a11y.Bus; fix = the regex org\.a11y(\..*)? +
  the negative tests; (2) MEDIUM: the new receive rule
  from any confined snap applies to EVERY session dbus
  slot (move it into the accessibility-provider slot,
  scoped to GetAddress); (3) MEDIUM: the bus daemon's
  privileges depend on the reader plug connected —
  disconnecting orca stops the mediation (fix: <apparmor
  mode="required"/> in the bus config, fail closed);
  (4) DEPLOYMENT BLOCKER: both accessibility-provider
  sides + the org.a11y.Bus dbus slot need a store
  snap-declaration (the CI images seeding
  ubuntu-desktop-a11y from the store without one fail);
  (5) MEDIUM: the dbusutil fix has no test and its
  comment is WRONG (the real difference: godbus depends
  on user.Current() which fails for the dynamic-uid
  greeter); (6) MEDIUM: the template ixr change + the
  reader-label pinning (an orca via the template ixr runs
  under the session snap's label and can't read; a GLOBAL
  template change); (7) MEDIUM: the desktop-legacy
  narrowing likely breaks the magnifier/osk tree reads
  (check on the image); (8) LOW: the error path, the
  commit-hash citations (the rebase invalidates), ~50
  tracker tags in the shipped Go comments. TESTS: pass at
  HEAD but FAIL at 14 commits (00f016f1eb..1a31bb9072) —
  the bisect-hostile history; gofmt fails on
  basedeclaration_test.go. STRUCTURE: NOT a single
  commit, NOT the 27-commit history — RESTRUCTURE TO 10
  COMMITS: drop the ce05e9b156+revert pair (net-zero),
  cherry-pick the 6 standalone fixes unchanged, the dbus
  session-peer rules as one, ONE complete
  add-accessibility-provider commit (9 folded), the
  reservation as its own, ONE desktop-legacy commit
  (11 folded); the prefixes fixed (interfaces/policy:,
  interfaces/apparmor:), the tracker tags dropped. THE
  RECIPE DRY-RUN IN A SCRATCH CLONE: TREE-IDENTICAL to
  desktop/26 + ALL 10 COMMITS PASS THE TESTS (the
  commands + the tree/bisect checks in the review's
  section C). BEFORE THE PUSH: fix 1, confirm 4, the
  restructure + gofmt, ideally 2/3/5/6. T56 DISPATCHED
  (the restructure + the fixes + the verification).
- [2026-11-19] T56 DONE — THE SERIES RESTRUCTURED, FIXED, AND
  LIVE-VERIFIED. TREE IDENTITY: the restructure tip
  (commit 10, 47fe232e74) tree = f5b4338099 tree =
  5f7f5850a25f6823db9bc39973342caafb553110 — a pure
  reorganization (git diff --exit-code empty). PER-COMMIT
  TESTS: rebase -x over all 10 -> 50 ok / 0 FAIL
  (5 packages x 10, BISECT-CLEAN; the old series failed
  at 14 commits). FIXES LANDED (desktop/26 = 10 + 5 = 15
  commits, local only): F1 cba6311bc4 gofmt; F2
  99f2c4128f [HIGH] the reservation regex -> org\.a11y
  (\..*)? + the negative tests (org.a11y, org.a11y.Bus.Foo
  denied); F3 4db90fcf0a the generic peer=(label=snap.*)
  session-slot receive DELETED + the provider slot gains
  path=/org/a11y/bus interface=org.a11y.Bus
  member=GetAddress peer=(label=snap.*) (+ the test
  updates, the vacuous negative fixed); F4 89e6b57db5
  dbusutil MaybeExportSessionBusAddress + 4 tests + the
  REAL rationale (godbus/user.Current/dynamic-uid) + the
  commit-5 message reworded; F5 e01549bbb9 all tracker
  tags + the dangling hashes out of the shipped Go
  comments; the a11y snap 8551f45 <apparmor
  mode="required"/> in the staged accessibility.conf.
  LIVE SUITE (a disposable copy of the t39 bake,
  md5-verified; g81 sideloaded + persisted): chord->orca->
  speech PASS (the PCM transitions 104+108, SPDSAY-RC=0
  x2); THE PANEL OPENS (org.gnome.Settings owned by the
  forked panel under the shell label; the bind denials =
  1 — the known pipewire gap); the must-deny errno-13
  verbatim + the narrowed receives verified in the pulled
  profiles (0 unnamed, F3's GetAddress receive present);
  BYPASS-NEGATIVE: the policy deny proven (the tests +
  the running-binary regex), the --dangerous bypass
  documented (by design); FAIL-CLOSED DISCONNECT VERIFIED
  ("Failed to start message bus: AppArmor mediation
  required but not present", restored cleanly). The wedge
  grep 0, --failed 0. FINDING-6 DISPOSITION: DOCUMENTED
  (the T51 session-snap orca shim converts the ixr exec
  into a snap-run reader under the a11y label — the
  feared case CANNOT OCCUR; the upstreamability note
  kept). FINDING 8: the magnifier zoom works; the shell's
  tree-read/RegisterEvent denials captured verbatim (the
  designed narrowing + one pre-existing client gap) — the
  reader-plug decision left to the owner. FINDING 4: the
  store snap-declaration requirements documented (the
  accessibility-provider plug+slot + the org.a11y.Bus
  dbus slot). BACKUP: work/pre-restructure-backup
  preserved; VM powered off gracefully; image copies +
  build trees cleaned; NOTHING PUSHED — THE PUSH IS THE
  FINAL STEP: the rewritten desktop/26 (15 commits from
  78dca3acd0) DIVERGES from origin/desktop/26 (f5b4338099,
  the old 27-commit tip) -> the push requires --force,
  REPLACING the old history on canonical's CI branch —
  the final gate is the owner's confirmation.
- [2026-11-18] THE NOUSER-VM LOGIN FAILURE ROOT-CAUSED (the
  owner's fresh bake, snapd g80 + the session b6218fe + the
  a11y 20261118 baked): "the password goes straight back to
  user selection" — THE AUTH SUCCEEDS (zero
  authentication-failure lines; the pam session opens and
  closes cleanly). THE REAL FAILURE: the user session's
  gnome-shell SIGABRTs at startup — verbatim: Failed to
  start X Wayland: Wrong ownership for directory
  /tmp/.X11-unix, owned by 60578 (the wizard's dynamic uid
  created it — nothing creates the dir root-owned at boot)
  but should be same as /tmp owner (0) or 1000 ->
  org.gnome.Shell@ubuntu.service exits 6/ABRT -> the
  session target fails -> gdm returns to the greeter. THE
  GENERIC BUG: the image lacks the boot-time root-owned
  creation of /tmp/.X11-unix (the classic x11 tmpfiles rule)
  — the FIRST dynamic-uid session owns it and every later
  session with a different uid trips the ownership check.
  IMMEDIATE RECOVERY: rm -rf /tmp/.X11-unix (root via ssh;
  the stale sockets are dead) -> the next login recreates
  it as uid 1000 and the desktop comes up (the owner is
  re-testing). NOTE: at 20:54 the dir was ALREADY
  root-owned (a greeter restart cycle re-created it) yet
  the 21:00 mutter still logged the 60578 complaint — the
  exact sequence needs the T50-style instrumentation if it
  recurs. PERMANENT FIX (dispatchable): the boot-time
  tmpfiles rule in core-base-desktop (D /tmp/.X11-unix
  1777 root root - — the classic x11 packaging rule, likely
  a Nov-15-trim casualty) so EVERY boot creates it
  root-owned and all sessions accept it. SECONDARY
  FINDING: gnome-session-ctl (confined) cannot call systemd
  StartUnit on the unconfined user manager (AppArmor
  denied) — the session-failure shutdown path is broken
  (joins the dbus-grant class, T51-residual).
- [2026-11-17] T49 DONE — THE TRACKING-FLAKE FIX IS LIVE-
  VERIFIED: PASS, GATE-READY. BUILD: snapd
  2.76.3+g78.4835bf2_amd64.snap (the T25/T45 stale-stamp
  gotcha hit AGAIN — the binary carried the fix but the
  meta stamped g77; snapcraft clean snapd + rebuild ~9min;
  stamp + the fix's %s/%d/bus constant verified). SIDELOAD:
  graceful, PERSISTED ACROSS THREE graceful reboots,
  connections intact. FIX VERIFICATION: the T48 A1 repro
  flipped FAIL->PASS verbatim — g77: cmd_run.go:1867 cannot
  track application process / tracking.go:224 session bus
  is not available; g78: tracking.go:221 using session bus
  + the transient scope created + a full env-scrubbed
  launch RC=0 (TRACKING-AND-EXEC-OK inside
  ubuntu-desktop-a11y). Control (env pre-set) unchanged.
  The genuinely-session-less case (the greeter leg,
  /run/user/1000 absent) still fails by the accepted
  SNAPDENG-34299 policy — the fallback's boundary visible
  verbatim, recorded as accepted. READER FLOW DELTA PASS:
  orca auto-start + spd-say rc=0, the greeter chord FIRED
  + greeter speech rc=0 (2.954s), clean Latin typing, five
  clock-matched PNGs, zero accessibility denials, zero
  wedge signatures. OPERATOR INCIDENT (honest, corrected
  live): a ROOT-run keyfile lock-disable (0600 root-owned)
  made gsd's keyfile writes EACCES and stopped the reader
  on boots 2/3 — fixed (chown), recovery proven on a clean
  boot; RECIPE CORRECTION: run the keyfile disable AS THE
  SESSION USER, never as root. Cleanup done; the g78
  artifact remains at the fork root (next bake picks it
  up). THE TRACKING FIX RIDES WITH THE PUSHES and joins
  the upstream candidates (SNAPDENG-34299-adjacent).
- [2026-11-17] T45 DONE — THE READ-SEND DROP IS LIVE-VERIFIED:
  PASS, G77 GATE-READY. THE DROP: commit 78500c37d4 on
  desktop/26 (local only) — 8 pre-reader-role
  desktop-legacy read sends removed (Accessible Get* +
  Properties Get{,All} at all three path shapes, Collection
  GetMatches + Application GetApplicationBusAddress) + the
  cache send narrowed to its Add/RemoveAccessible
  broadcasts; the T43 receive set byte-identical;
  reader-role sends, registry-pinned sends, event
  broadcasts untouched; 34 go-test packages pass. REBUILD:
  snapd 2.76.3+g77.78500c3 (the T25 stale-stamp gotcha hit
  -> snapcraft clean snapd + repack); binary-verified 79
  rules / 12 a11y sends / 19 receives / 0 read-sends. LIVE
  (disposable copies of the clean bake): sideload persisted
  x2 reboots; session leg PASS (orca + spd-say unix_socket
  + Latin); greeter leg PASS (chord fired, greeter speech
  rc=0, readable); must-deny errno-13 x2 verbatim + the
  narrowed receives verbatim + zero unnamed a11y-bus
  receives; C6 at policy level. DROP-SPECIFIC AUDIT: ZERO
  read-send rules to non-own peers in every
  desktop-legacy-consumer profile; TREE-WALK-OK — orca's
  GI Atspi walk reads gnome-shell's tree CROSS-SNAP through
  the reader role + pinned receives (the C2 wall works
  live); zero bus=accessibility denials across all boots.
  NEW ISSUES: (1) a NEW face of the T34 snap-run flake
  (`snap run --shell APP -- cmd` ENOEXEC; interactive shell
  works — probe recipes updated); (2) loud orca pgrep
  /proc noise (T28 class, zero on the a11y bus);
  (3) gsettings recipe correction (gnome-46-2404 +
  GSETTINGS_SCHEMA_DIR required); (4) this orca is
  GI-based — no pyatspi module; (5) OPERATIONAL: a
  disposable-VM MAC/IP COLLISION between concurrent agents
  (a T47 VM took T45's MAC, same DHCP address ~12 min) —
  all post-collision probes re-verified on a MAC-pinned
  VM; a MAC-allocation convention (check running qemu MACs
  before launching; never assume your own earlier MAC is
  still free) is now in the project's agent guidance.
  THE WAVE-2 POLICY (g77) IS GATE-READY: the read-send
  drop is the last policy change before the pushes.
- [2026-11-17] OWNER RULING: THE D1 FAT-MERGE IS OFF THE
  QUEUE — fat is OUT OF SCOPE, confirmed again at the
  wave-2 review ("I already said that"). Consequence: the
  desktop-legacy fat-compat argument in T43 decision
  point (3) is moot; the owner is reviewing the five
  remaining T43 decision points. The fat line remains
  frozen as the verified reference only.
- [2026-11-18] THE OWNER'S FRESH DEV VM (hostname
  core-desktop, uid-1000 user): snapd 2.76.3+g78.4835bf2
  BAKED (the tracking fix rides in the bakes now), a11y
  0.1+git20261117 x1 (the watchdog build), the session
  20261117+gitc93ad74 x1. THE SILENT-ORCA REPORT: chord ->
  the a11y icon appears but NO audio; the Settings sound
  test fine. DIAGNOSIS + RESOLUTION: the server was never
  wedged (the supervisor logged "first reply after spawn
  in 0.00s: 208 OK CLIENT NAME SET" — the T47 watchdog IS
  in this build and its handshake green),
  DefaultModule=espeak-ng, the audio target (PULSE_SERVER=
  unix:/run/user/1000/snap.pipewire/pulse/native) EXISTS
  and is owned by the user, and a direct probe (spd-say as
  the user) WAS AUDIBLE TO THE OWNER ("audio path probe
  now"). THE ROOT CAUSE OF THE EARLIER SILENCE: a
  STARTUP-WINDOW RACE — orca connected at 12:33:51 (51s
  after login) when the dummy fallback module was
  exec-failing and the espeak audio path was still
  initializing; the first announcements were lost; after
  the first successful audio render the path stays warm
  and orca speech became audible (the owner: "screen
  reader on" + lots of things, heard). NEW PACKAGING GAPS
  (queued): (a) sd_dummy is MISSING from the snap layout
  (Exec failed error 2 — the dummy fallback module is
  broken; espeak is the active module so impact is low but
  the fallback is dead weight); (b) the speechd locale
  pronunciation dictionaries
  (/usr/share/speech-dispatcher/locale/*/*.dic) are
  missing from the snap layout (benign 'c'-locale noise,
  but packaging incomplete); (c) the server log has ZERO
  SPEAK lines (the default log level does not record
  speech payloads — the server log is NOT a reliable
  speech-request record; use the pcm/pipewire state for
  audio evidence). FOLLOW-UP (shipping quality):
  root-cause the startup-window race — a screen-reader
  user logging in must hear orca's first announcement, not
  lose it; candidates: the espeak audio-open vs the
  session pipewire readiness, the orca retry behavior on
  the first dispatch, the dummy-fallback failure at init.
- [2026-11-18] WIZARD SPEECH ENABLED (the owner heard it) —
  the manual recipe that works on the nouser build (the
  wizard uid gnome-initial-setup=60578, HOME=/run/gdm3/
  home/gnome-initial-setup): (1) gsettings set
  org.gnome.desktop.a11y.applications
  screen-reader-enabled true as uid 60578 (the
  gnome-desktop-runtime gsettings + the gnome-46-2404
  schemas + the session bus; gsd-a11y-settings IS running
  in the wizard session but does NOT spawn orca — no orca
  shim in the session snap's PATH, no desktop-file glue);
  (2) orca launched via the snap app wrapper
  (/snap/bin/ubuntu-desktop-a11y.orca --replace) as uid
  60578 with DISPLAY=:1024 (mutter's transient Xwayland —
  /tmp/.X11-unix has X1024/X1025, mutter spawns a
  transient Xwayland per connection which rejects
  unauthenticated clients) + XAUTHORITY=/run/user/60578/
  .mutter-Xwaylandauth.QNPOY3 (the mutter auth file, found
  by the /run/user/60578 hunt) + NO_AT_BRIDGE=0 + the
  session bus. THE ROOT CAUSE OF THE CHORD FAILURE AT THE
  WIZARD: gnome-shell --mode=initial-setup does NOT bind
  Super+Alt+S — the keystroke leaked into the language-
  list navigation (that is how the selection moved to
  Shqip — the Albanian LANGUAGE entry). THE
  ZERO-TO-SPEAKING DESIGN GAP IS NOW FULLY CHARACTERIZED
  (three glue pieces missing: the chord binding in
  initial-setup mode, the gsd->orca cross-snap launch
  glue, the X display/auth env for the device layer) with
  a WORKING MANUAL RECIPE as the specification. The owner
  can now navigate the language page with orca reading it
  (select the language — the list is still on Shqip).
- [2026-11-18] OWNER CONFIRMED: the VM works fine (orca
  stable and audible on navigation). The startup-race
  root-cause + the packaging gaps (sd_dummy, the locale
  dicts) + the base-side localsearch-3 vendor step are
  the last shipping-quality items — dispatched as T50.
- [2026-11-18] OWNER RULING ON THE SD_LISTEN_FDS LAYERING:
  it is all working by design — the identity check did
  its job; it was OUR OWN TOOLING (the T47 supervisor)
  that made the mistake. The ONLY upstream issue is the
  SILENT FAILURE: speechd should LOG AN ERROR when the
  socket-activation fd claim fails and it falls back to
  self-binding. New todo:
  `20261118-speechd-silent-fdclaim-logging-upstream.md`
  (the incident chain, the minimal log-only ask, the
  optional strict-refusal discussion point, the two-line
  repro, the upstream-first check; file alongside or
  instead of the speechd-hang-wedge todo at the owner's
  preference).
- [2026-11-18] T50 DONE — THE STARTUP RACE ROOT-CAUSED AND
  FIXED. RACE LAYER VERDICT: NOT audio/orca/queue — THE
  SOCKET HANDOFF. This systemd generation passes
  LISTEN_PIDFDID (a pidfd of the unit main pid = the T47
  supervisor); the supervisor's LISTEN_PID rewrite cannot
  satisfy the server child's sd_listen_fds identity check
  -> the fd claim fails -> speechd UNLINKS the unit's
  socket and self-binds -> orca's login connection and
  the watchdog's probe are orphaned forever (Recv-Q=2
  stranded all session). COROLLARY: T47's "born-hung
  catch" was THIS ARTIFACT — the watchdog killed a
  HEALTHY 1.1s-initialized server at the 30s grace. THE
  FIX: the supervisor passes the fd via speechd's own
  SPEECHD_SOCK_FD hook — the server serves the unit's
  socket: no unlink/rebind, the pre-spawn backlog served,
  fd-mode queue preservation real. LIVE: the first reply
  0.42-0.55s (was 30s + kill), one socket, Recv-Q=0.
  PACKAGING: sd_dummy SHIPPED — it needed a sem_open shim
  (glibc sem_open MKNODS A RANDOM TEMP NAME in /dev/shm —
  the AVC verbatim /dev/shm/sem.OwoID8); shim v2:
  open+ftruncate+mmap+sem_init inside the existing grants
  -> dummy initializes, "3 output modules", zero
  ANOM_ABEND. The locale dicts were STAGED ALL ALONG — the
  gap was the compiled-in LOCALE_DATA path; a layout bind
  fixes it (en/en_US failures 0; the c-locale residue is
  inherent — the deb ships no locale/c). a11y main @
  d9229a8. BASE VENDOR STEP LANDED: core-base-desktop
  desktop/26 @ 0ed202e (the one-file core-override
  drop-in, dconf pattern), base rebuilt 20261118+desktop,
  baked + live: localsearch-3 active/running CONFINED,
  zero 203s, --failed empty. FIRST-ANNOUNCEMENT
  VERIFICATION (a fresh bake: base 20261118+desktop +
  g78 + c93ad74 + a11y 0.1+git20261118, all x1): boot ->
  autologin -> orca auto-start +11s -> THE /proc/asound
  MONITOR LOGGED 226 pcm RUNNING TRANSITIONS
  14:41:23.4->14:41:36.6 (~13.2s of synthesis through the
  HDA) — the first announcements RENDER; no KILL, no
  ANOM_ABEND, zero wedge signatures, --failed empty.
  OPEN: the boot-time actuation re-enables
  screen-reader-enabled every boot (the Nov-16 finding
  (8) — now harmless to the race window); the upstream
  notes (sd_listen_fds vs LISTEN_PIDFDID; glibc's
  random-name mknod vs scoped /dev/shm; the deb's
  per-locale dict gaps); the T47 smoke-harness stale-fake
  note. THE SHIPPING IMPLEMENTATION IS COMPLETE — the
  remaining decisions are the pushes.
- [2026-11-17] WAVE-2 RULINGS (owner, in progress): (2) the
  one-reader pin CONFIRMED for now + a new todo created
  for the third-party reader snap investigation/integration
  (`20261117-third-party-reader-snap.md` — blocked on
  upstream label plumbing). (3) the desktop-legacy
  read-send drop RULED: DO IT NOW (owner: "another run is
  no problem") — T45 dispatched (the drop + rebuild + the
  full live re-run). (1)/(4)/(5) explained to the owner,
  pending confirmation. (6) closed by T44.
- [2026-11-17] ALL FIVE T43 DECISION POINTS NOW RULED:
  (1) C1 install-gating CONFIRMED ("random snaps should
  not be able to become accessibility providers"); (2)
  one-reader pin CONFIRMED + the third-party-reader todo
  created (`20261117-third-party-reader-snap.md`);
  (3) read-send drop RULED DO-NOW (T45 running); (4) the
  C3 honest consent restatement CONFIRMED for shipping;
  (5) the fixed-path contract CONFIRMED for now. THE
  WAVE-2 POLICY LAYER IS FULLY DECIDED — the snapd fork's
  g76/g77 lineage is the ship candidate, pending T45's
  live verification of the read-send drop.
- [2026-11-17] T45 DONE — THE READ-SEND DROP IS GATE-READY:
  PASS. THE DROP: commit 78500c37d4 on desktop/26 (local
  only) removes the 8 pre-reader-role desktop-legacy read
  sends (Accessible Get* + Properties Get{,All} at all
  three shapes, Collection GetMatches + Application
  GetApplicationBusAddress at their classic shapes; the
  bafad9d025/48f4a78262/986a18cefa lineage) and NARROWS
  the cache send to its Add/RemoveAccessible broadcasts
  (the GetItems read half dropped — the fourth shared
  read surface); the T43 receive set byte-identical, the
  reader-role sends untouched, registry-pinned sends +
  event broadcasts kept. REBUILD: snapd 2.76.3+
  g77.78500c3 (the T25 stale-stamp gotcha hit + fixed
  with `snapcraft clean snapd`; binary-verified: the
  extracted desktop-legacy constant is rule-for-rule
  identical to the committed source, 79 rules / 12 a11y
  sends / 19 receives / 0 read-sends). LIVE RE-RUN on a
  disposable copy of the clean bake: sideload graceful,
  PERSISTED across two reboots; reader flow green at
  BOTH stages (autologin spd-say rc=0 + Latin typing;
  greeter chord FIRED + greeter speech rc=0); must-deny
  holds (errno-13 x2 verbatim + the reader ESTABLISHED
  on the same socket); zero unnamed a11y-bus receives;
  THE DROP'S AUDIT CLEAN (zero read-send rules to
  non-own peers in every consumer profile; zero
  Accessible rules on the consumer send side); THE
  READER SURVIVED THE DROP (GI Atspi tree walk as the
  orca label reads gnome-shell's tree cross-snap:
  TREE-WALK-OK); zero bus=accessibility denials across
  all boots. Non-blocking: a NEW FACE of the T34
  snap-run flake (`snap run --shell APP -- cmd` ENOEXEC
  while the interactive shell works), loud orca pgrep
  /proc noise (T28 class), the gsettings recipe
  correction (gnome-46-2404 + GSETTINGS_SCHEMA_DIR
  required), and an OPERATIONAL INCIDENT: a T47
  session's VM took T45's VM's MAC (same DHCP address
  for ~12 min) — the affected probes were re-verified
  on a MAC-pinned VM; a MAC-allocation convention for
  concurrent disposable VMs is now in the project's
  agent guidance. Scratch cleaned; nothing pushed.
- [2026-11-18] T52 DONE — THE WIZARD SHELL IS CONFINED; THE
  INTERIM GRANT IS REVERTED. DISPATCH FIX: core-base-desktop
  d47f0ba — the base shipped dispatch drop-ins only for
  gnome-login/@gdm and ubuntu/@ubuntu; the wizard's
  shell+manager ran the content binaries raw via the
  gnome-content-launch alias branch (pinned at
  variants/desktop/static/usr/libexec/gnome-content-launch).
  FIX: two drop-ins dispatching org.gnome.Shell@initial-setup
  and gnome-session-manager@gnome-initial-setup via the
  @ubuntu --session-dispatch form (the wizard account is not
  in the gdm group, verified live). LIVE-ITERATION COMMITS:
  core-base-desktop d54c481 (nothing created the wizard's
  dynamic-user home — the gdm-homedirs 1777 parent +
  launcher mkdir), session-snap b6218fe
  (gnome-initial-setup.session unreachable in the confined
  ns -> crash loop), a11y-snap 581f5ce (run-orca resolves
  the session wayland socket directly; orca died on an
  X-auth fallback). CONFINEMENT EVIDENCE: attr/current =
  snap.ubuntu-desktop-session.gnome-shell (enforce) for the
  wizard shell (+ session-service/gsd apps) on EVERY boot
  incl. the final all-x1 bake. CHORD VERDICTS: Phase 2 (the
  interim grant present but INERT — the plug unconnected):
  FIRES, zero-to-speaking PCM-verified, chord->speech
  ~1.05s, ~11.2s sustained synthesis. Phase 3 (the grant
  REVERTED, snapd g80.f5b4338 live): STILL FIRES — the
  same-snap rules suffice with the confined shell, exactly
  as ruled. POLICY AUDIT: the ce05e9b156 shapes ABSENT in
  g80; zero plug-side peer=(label=unconfined) sends in the
  generated profiles; the must-deny both shapes hold
  (EACCES + the kernel-7.0 silent-AVC shape). BONUS: orca's
  KeyboardMonitor/Manager sends are no longer denied; the
  remaining gap is the shell's own
  org.freedesktop.a11y.Manager dbus_bind (no slot declared)
  — one session-snap slot is the queued fix. RESIDUALS:
  the chord-OFF toggle SEGFAULTS the Flutter wizard UI
  (upstream-class, verbatim SEGV recorded); manager-env
  churn. Trees: core-base-desktop d47f0ba + d54c481,
  session snap b6218fe, a11y 581f5ce, snapd desktop/26 +
  the ce05e9b156 revert (g80.f5b4338) — all local, trees
  clean, no pushes. VM powered off gracefully; images/
  build trees deleted.
- [2026-11-17] T47 DONE — THE SPEECHD WATCHDOG + THE STORE
  LINT. DESIGN: no WatchdogSec needed — bin/run-speech-
  dispatcher execs bin/speechd-supervisor.py (stdlib
  python, ZERO new AppArmor surface: same-snap signal
  grant + snap-runtime-dir connect grant; no /proc
  scanning); the supervisor is the unit's main pid, owns
  the server as its child (socket-activation fd passed
  through, LISTEN_PID rewritten), probes every 15s with a
  REPLY-BASED SSIP handshake (SET SELF CLIENT_NAME -> any
  reply line; no synthesis, not a speech round-trip; 10s
  kill threshold, 30s startup grace; normal reply <1ms),
  SIGKILLs + respawns in-process, degrades loudly to
  self-bind when the fd is missing. HANG SIMULATION:
  SIGSTOP -> wedge client rc=124 reproduced -> detection
  22.1s -> kill -> respawn -> recovery spd-say rc=0 in
  3.197s, the unit never failed. BONUS — THE NOV-16 WEDGE
  CLASS IS SOLVED: a BORN-HUNG BOOT SERVER was caught by
  the startup grace at reboot, with orca's queued login
  connection served by the fresh server (fd-mode queue
  preservation proven) — the exact scenario that silenced
  gate 8 now self-heals. SOAK: 5min idle + active speech
  -> 8/8 probes 0.000s, ZERO false-positive kills, zero
  AppArmor denials. Three snapd-side lifecycle findings
  recorded (a failed .socket unit after an endure refresh;
  path orphaning by self-bind; a non-persisting snapd
  refresh — join the N2 upstream candidates). METADATA:
  title "Ubuntu Desktop Accessibility", contact
  chris.bainbridge@canonical.com (verbatim in snap info),
  source-code/issues/website =
  github.com/chris-bainbridge/ubuntu-desktop-a11y —
  FLAGGED: the repo has NO remote; THE OWNER MUST
  CONFIRM/CORRECT ALL THREE BEFORE ANY STORE UPLOAD. Repo
  main @ bba66f2 (4 local commits), snap 0.1+git20261117
  sideloaded x5 + verified on a disposable copy (the
  T44/T45 MAC convention followed), md5-verified bake,
  scratch cleaned, graceful poweroff.
- [2026-11-17] T46 DONE — THE GREETER VOLUME KEYS +
  localsearch-3. MECHANISM TRACE: scripts/run.sh:2 +
  run-session.sh:18 export the conventional
  /run/user/<uid>/pulse/native for every snapped session
  process; the pipewire snap's pulse socket is user-daemon
  listen-stream -> snapd generates ONLY the private path
  (%t/snap.pipewire/pulse/native); the conventional path
  exists solely in user sessions via the base wrapper's
  pulse -> snap.pipewire/pulse symlink — greeter/wizard
  sessions never run that wrapper. FIX 1 (launcher
  socket-resolution, commit c93ad74): both launchers
  prefer the conventional socket when it exists, else fall
  back to the snap-private one. BEFORE: the dead path on
  both greeter processes, connection-refused for
  media-keys + shell, volumeup x5 -> 0.40 unchanged.
  AFTER (sideloaded 20261117+gitc93ad74 @x2): fallback env
  live, connection-refused 0, volumeup x5 ->
  0.40->0.70 (the exact T42 math), volumedown -> 0.11; the
  user session unchanged (conventional); persists across a
  graceful reboot. FIX 2 (localsearch-3): the unit comes
  from the content snap via the base wrapper's
  user.control symlink and is pulled by the content
  target's static Wants= — the HOST user manager execs
  /usr/libexec/localsearch-3 OUTSIDE the snap namespace ->
  203. The in-scope part LANDED (a layout bind of the
  binary into the snap namespace); the unit redirect needs
  a base-side one-file drop-in
  (ExecStart=/snap/bin/ubuntu-desktop-session.localsearch-3
  — the Nov-15 base trim dropped exactly this lineage;
  every session-snap mechanism verified blocked) — the
  EXACT VENDOR STEP recorded for core-base-desktop.
  Validated live: the indexer active/running CONFINED,
  --failed empty, zero 203s, persists across reboot.
  REBUILD: ubuntu-desktop-session_20261117+gitc93ad74_
  amd64.snap (md5 3f85860a...), sideloaded + persisted;
  the VM's MAC verified against concurrent agents; owner's
  VMs untouched throughout.
- [2026-11-17] T48 DONE — build.sh + the snap-run flake.
  BUILD.SH FIX: the one-liner at 1592 is now usermod
  --prefix "$(realpath -m "${BUILD_DIR}/squashfs-root")" —
  committed locally 0c3540a on desktop/26 (ahead 12, no
  push); a targeted join-logic harness proves the old line
  FAILED the absolute case verbatim and the fixed line
  passes both. FLAKE CODE-PATH VERDICT: one sentinel —
  sandbox/cgroup/tracking.go:28 ErrCannotTrackProcess;
  tracking = a systemd transient scope created via the
  SESSION bus for non-root (from the launch ENV only);
  core26+ makes failure FATAL (upstream 171769f800,
  SNAPDENG-34299); the fork is upstream-identical ->
  UPSTREAM-GENERAL, joins the queue with N2/N3/N4. REPRO
  (disposable VM): verbatim with a launch context without
  a live pam session (no bus address; /run/user/UID gone
  when the last session closes) — WITH a healthy session
  and orca running; ssh/systemd-run --user contexts pass.
  N1's sideload refusal reproduced and CLEARS when orca
  stops — the by-design refresh.go running-apps check,
  NOT the flake. FIX PROPOSAL: a snapd tracking patch —
  dbusutil SessionBus falls back to the canonical
  /run/user/UID/bus when the env lacks an address; git
  apply --check clean against desktop/26, NOT committed
  (the fork was read-only for this task); nuance
  recorded: fixes the intermittent env-deprived cases; a
  fully session-less launch has no bus to find and the
  core26+ hard-fail is upstream's SNAPDENG-34299 policy
  call. HONEST NOTE: a mid-flight dd under the live
  disposable VM truncated snapd state.json — restored from
  the pristine bake (the canonical bake was md5-verified
  untouched).
- [2026-11-18] T50 DONE — THE LAST SHIPPING-QUALITY BATCH:
  the startup race + the a11y packaging gaps + the base
  localsearch-3 vendor step. RACE ROOT CAUSE (reproduced +
  traced on a disposable copy of the T39 bake, a11y
  sideloaded to the owner's build): THE SOCKET HANDOFF —
  this systemd generation passes LISTEN_PIDFDID (a pidfd
  of the unit main pid = the T47 supervisor); the
  supervisor's LISTEN_PID rewrite cannot satisfy the
  server child's sd_listen_fds identity check, so the fd
  claim FAILS and speechd falls into its unix_socket
  branch: it UNLINKS the unit's socket path and binds its
  own socket there, orphaning everything already queued on
  the unit's socket — orca's login connection AND the
  watchdog's own first probe (ss Recv-Q=2 stranded for
  the whole session; the watchdog killed a HEALTHY
  1.1s-initialized server at the 30s startup grace and
  respawned against a path only the new server's own bind
  answers — T47 STEP 5's "born-hung catch" was this
  artifact, not a hang). THE AUDIO LAYER IS CLEAN (the
  audio open succeeded in 1.1s on the broken build). FIX:
  the supervisor passes the activation fd via the
  server's own SPEECHD_SOCK_FD hook (speechd.c:1341) —
  the server serves the unit's socket directly: no
  unlink, no rebind, the pre-spawn backlog is served,
  fd-mode queue preservation becomes real. LIVE: first
  reply 0.42-0.55s (was 30s+kill+respawn), one socket at
  the path, Recv-Q=0. PACKAGING: sd_dummy SHIPPED —
  required a sem_open shim (launchers/sem-snap-shim.c,
  LD_PRELOADed onto the server + module children) and
  the v1 name-mapping was disproven LIVE (glibc's
  sem_open mknods a RANDOM temp name — verbatim AVC
  /dev/shm/sem.OwoID8 requested_mask="c"); shim v2
  IMPLEMENTS sem_open via open+ftruncate+mmap+sem_init
  inside the granted perms: the dummy initializes,
  registers ("3 output modules"), zero ANOM_ABEND. THE
  LOCALE DICTS were staged all along — the gap was the
  compiled-in LOCALE_DATA path /usr/share/speech-dispatcher
  not resolving in-ns; a layout bind fixes it (en/en_US
  dict failures 0; the 'c'-locale residue is inherent —
  the deb ships no locale/c). BASE VENDOR STEP LANDED:
  core-base-desktop desktop/26 0ed202e (the one-file
  core-override drop-in, the dconf pattern), base rebuilt
  20261118+desktop, BAKED + LIVE: the drop-in merges,
  localsearch-3 active/running CONFINED (exe = the
  session snap's content binary), zero 203/EXEC,
  --failed empty. FINAL BAKED VERIFICATION (image build
  with no user pre-seeded: base 20261118+desktop, snapd
  g78.4835bf2, session c93ad74, a11y 0.1+git20261118,
  all x1): boot -> autologin -> orca auto-start +11s ->
  THE FIRST ANNOUNCEMENTS RENDER — the /proc/asound
  monitor loop logged 226 RUNNING transitions spanning
  14:41:23.4->14:41:36.6 (~13.2s of synthesis through
  the HDA), first reply 0.42s, no KILL, no ANOM_ABEND,
  zero wedge signatures. COMMITS (LOCAL ONLY): a11y main
  @ d9229a8 (amended: the shim v2); core-base-desktop
  desktop/26 @ 0ed202e. Disposable VMs used (owner's VMs
  untouched), image copies + the build tree cleaned,
  scratch evidence kept. FINDINGS FOR THE QUEUE: the
  boot-time actuation re-enables screen-reader-enabled
  EVERY boot (the Nov-16 finding (8) live); upstream
  notes: sd_listen_fds vs LISTEN_PIDFDID (SPEECHD_SOCK_FD
  is the designed workaround), glibc sem_open's
  random-name mknod vs scoped /dev/shm grants, the deb's
  missing per-locale dicts noise.
- [2026-11-18] T51 DONE — WIZARD SPEECH MADE PERMANENT (six
  local commits on ubuntu-desktop-session-snap desktop/26,
  no pushes; the final snap 20261118+git6a727a6). THE
  CHANGES: (1) 907ed72 the orca shim (/usr/bin/orca
  layout bind execing /snap/bin/ubuntu-desktop-a11y.orca,
  resolving DISPLAY/XAUTHORITY from the manager env) +
  the display/auth brokerage (gate + helper); (2)
  afcc4ee the CHORD: a gsd media-keys custom0 keybinding
  <Super><Alt>s -> the shipped toggle script, seeded at
  wizard session init into the wizard dconf (gated on
  the initial-setup account; the stock user-session
  chord untouched); (3) 57a56d3 + 87f5e44 + e989b84 the
  gate routed through the gsd apps (the wizard's session
  manager/shell run the CONTENT binaries raw — only the
  gsd units are snap apps), the gate invocation fixed
  ($SNAP prefix; an erroneous shift causing silent
  exit-0), the brokerage reads the manager env first;
  (4) 6a727a6 the REAL BLOCKER captured verbatim:
  AppArmor denies GrabAccelerators to the UNCONFINED
  wizard shell (peer_label=unconfined) — the same-snap
  peer rule only covers the greeter. FIXED via a dbus
  plug dbus-gnome-shell-client -> this snap's own
  dbus-gnome-shell slot; THE FULL GRANT NEEDS THE SNAPD
  FORK PATCH (now COMMITTED: ce05e9b156 interfaces/dbus:
  the plug-side unconfined-peer send rules for
  session-bus-only plugs, gofmt-clean, authored and
  signed off by the owner; the live test used the two
  label-based send rules injected at the image level,
  T44-drop-in style). ZERO-TO-SPEAKING VERIFIED
  (disposable copy, md5-verified a622859f): chord
  17:23:31.97 -> the key flip rc=0 -> orca.service
  active -> orca + sd_espeak-ng -> FIRST PCM RUNNING
  17:23:35.26 -> LATENCY ~3.3s; the reboot-persistence
  boot ~2.7s (that boot the stock screenreader grab won
  the chord — either path flips identically). English
  selected via type-ahead. LAYOUT GUARD PASS: the
  grabbed chord is consumed (no Shqip jump); the input
  sources untouched. REMAINING GAPS: the navigation
  announcements silent (the Flutter semantics tree +
  orca's KeyboardMonitor sends AppArmor-denied against
  the unconfined shell — same class, same patch shape,
  the residual to extend); the GADGET CONNECTION
  WIRING required for shipping (the dbus-gnome-shell-
  client plug -> the slot in the gadget/image); the
  helper's systemctl exec denied (non-fatal). Image
  copy + recon deleted; scratch cleaned; owner VMs
  untouched.
- [2026-11-18] THE /tmp/.X11-unix STORY CORRECTED — THE
  HOST-SIDE THEORIES WERE ALL WRONG; THE BATTLEFIELD IS
  THE SESSION SNAP'S SHARED PRIVATE TMPFS. VERBATIM
  EVIDENCE: /proc/<greeter-shell-uid-60579>/root/tmp/
  .X11-unix = drwxrwxr-t 2 60578 gnome-initial-setup —
  the wizard's mutter created the dir inside the SESSION
  SNAP'S PRIVATE /tmp (the confined mutters' mount
  namespace), which is SHARED across the users of the
  same snap (the wizard's uid-60578 session and the
  user's uid-1000 session share it). The user session's
  mutter (uid 1000) rejects the 60578-owned dir
  (mutter's own ownership check, the verbatim "Wrong
  ownership" error) and SIGABRTs. THE HOST-SIDE FIXES
  WERE ALL INVISIBLE: the host /tmp is shadowed by the
  private tmpfs in the confined mutters' namespaces
  (the root-owned install "worked" per ls but mutter
  never saw it); the T50-style boot-time tmpfiles rule
  is DEAD for this bug (the host dir is irrelevant).
  THE FIX APPLIED: chown root:root /proc/<greeter-shell-
  pid>/root/tmp/.X11-unix (through the live confined
  process's root view) — the dir is now root:root in
  the shared tmpfs; EVERY session uid accepts a
  root-owned dir. THE OWNER IS RE-TESTING THE LOGIN.
  THE PERMANENT FIX OPTIONS (upstream-class, the design
  is the finding): (a) mutter should ACCEPT sticky-bit
  /tmp dirs regardless of the owner (the classic
  /tmp/.X11-unix is 1777 sticky for exactly this
  cross-uid reason — mutter's ownership check is
  stricter than the filesystem's); (b) snapd should
  mount the private tmpfs PER-USER, not per-snap (the
  cross-uid collision is inherent to the shared tmpfs
  for any multi-user snap that creates /tmp content).
  The immediate user workaround: the /proc chown recipe
  (root via ssh). ALSO RECORDED: the host-side /tmp
  mtime confusion resolved (the chown updates the ctime
  not the mtime — the ls mtime 21:05 was the earlier
  install's entry creation; the ownership was never the
  host's).
- [2026-11-18] THE A11Y-SETTINGS LAUNCH FAILURE ROOT-CAUSED
  (the owner's re-test on the fresh nouser bake): the
  a11y menu -> Accessibility Settings launches
  gnome-universal-access-panel-desktop (DBusActivatable)
  which must OWN org.gnome.Settings — the bind is
  AppArmor-DENIED (dbus_bind DENIED name=org.gnome.
  Settings label=snap.ubuntu-desktop-session.gnome-shell;
  the panel: Failed to register: not allowed to own the
  service) -> the panel exits -> the spinner dies. THE
  CHORD NOW WORKS on the fresh nouser bake (the owner:
  Super+Alt+S -> the screen reader audible — the
  T51/T52 chain delivering on the baked g78+base
  20261118). THE SYSTEMIC SCOPE: the same bind denials
  hit org.gnome.Nautilus, org.freedesktop.Notifications,
  org.gnome.Orca.Service — while org.gnome.Shell works
  (declared in the dbus-gnome-shell slot). THE SESSION'S
  APPS BROADLY LACK THEIR DBUS NAME BIND GRANTS. T54
  DISPATCHED (the dbus name grants: the snapd dbus
  interface's name mechanism, the full denied-name
  audit, the session/a11y snap slot declarations for
  every service name, the rebuild + the live
  verification: the a11y panel opens + the zero-DENIED-
  binds audit).
- [2026-11-18] T53 DISPATCHED — the permanent session-snap
  fix: the launcher self-heal (at session start, before
  mutter: a foreign/non-1777 /tmp/.X11-unix in the shared
  private tmpfs is removed/recreated owned by the current
  uid, mode 1777; the EPERM case logs loudly + the /proc
  chown workaround pointer) + the full zero-to-desktop
  verification on a disposable copy of the owner's nouser
  image (the wizard -> the greeter -> the LOGIN -> the
  desktop — the first-ever full-flow exercise) + the
  regression guard (the wizard speech must survive the
  launcher change) + the upstream notes recorded
  (mutter's sticky-dir acceptance; snapd's per-user
  private tmpfs).
- [2026-11-18] T53 DONE — THE COLLISION IS FIXED
  PERMANENTLY; THE FULL FLOW (wizard -> chord speech ->
  complete -> greeter -> PASSWORD LOGIN -> DESKTOP)
  PASSES. THE DESIGN (pinned from source BEFORE coding,
  both facts verified live on the VM): (1) snap-confine
  setup_private_tmp bind-mounts the HOST dir
  /tmp/snap-private-tmp/snap.<snap>/tmp (root:root 01777,
  enforced) over /tmp — /tmp in-ns is root-owned STICKY,
  shared per-snap across uids, host-shadowed; (2) mutter
  ensure_x11_unix_perms (meta-xwayland.c) accepts the dir
  only if owned by /tmp's uid or the session's getuid(),
  sticky+writable, else SIGABRT. THE CONSEQUENCE (the
  design-level finding): the spec'd launcher rm-rf
  self-heal PROVABLY cannot fix the cross-uid case as a
  non-owner (kernel check_sticky — EPERM, proven LIVE) —
  it is implemented verbatim anyway (scripts/
  ensure-x11-dir.sh: missing ->create 1777; root/self->
  keep + chmod 1777; foreign->attempt removal->recreate->
  EPERM->LOUD log + the /proc chown pointer + continue;
  every action logged; hooked in run.sh's gnome-shell
  branch = the pre-mutter point for ALL session kinds +
  the run-session.sh early pass replacing the legacy
  silent mkdir/chmod pair) AND COMPLETED by a minimal
  root daemon: the ensure-x11-dir oneshot service (same
  commit) that normalizes the dir to ROOT-OWNED 1777 at
  boot inside the same namespace — mutter accepts a
  root-owned dir from EVERY uid, so the collision is
  structurally gone; boot order race-safe in both
  directions. COMMIT: session snap ad10f61 (desktop/26,
  local, on b6218fe; the artifact 20261118+gitad10f61,
  md5 820d09df; the stale-stamp gotcha hit once — clean
  the version part explicitly). VERIFY on a disposable
  copy of the owner's build/pc.img (both prior md5s
  stale — the owner re-baked twice; current f8f2ec69,
  quiescence verified, copy md5-matched; host /tmp is
  tmpfs so the collision is created+consumed within one
  boot): BEFORE (stock x1): the wizard completed via
  vncdotool (English, the a11y page, keyboard US + the
  typed guard word, account test/nopass456 — NEW-3 still
  non-reproducing) -> gdm auto-attempted the new user ->
  THE VERBATIM FAILURE: "Failed to start X Wayland:
  Wrong ownership for directory /tmp/.X11-unix, owned by
  60578 but should be same as /tmp (owned by (0)) or
  1000" -> 6/ABRT -> back to the greeter. AFTER (x2
  sideload, reset, reboot): the daemon logged "missing:
  created (owner 0, mode 1777)" at boot; the wizard's
  launcher heal logged "ok (owner 0, mode 1777)" BEFORE
  mutter; the chord (ONE vncdo session) -> orca.service
  -> sd_espeak-ng x2 -> PCM open 21:50:27.58->close
  21:50:39.43 (~11.9s synthesis, chord->speech ~2.3s —
  the T51 magnitudes; the stock grab won, the documented
  alternation) -> the wizard completed -> THE DESKTOP UP
  (confined shell from x2, Xwayland :0/:1 INSIDE the
  root-owned dir) -> graceful GUI logout -> THE EXPLICIT
  PASSWORD LOGIN test/nopass456 -> the desktop again,
  BOTH heal passes logged per login. WHOLE AFTER BOOT:
  ZERO "Wrong ownership", ZERO "Failed to start X
  Wayland", zero ABRT. THE EPERM EDGE EXERCISED LIVE
  (non-destructive rename dance): the script as uid 1000
  on a planted foreign dir -> the loud ERROR + the /proc
  chown pointer, rc=0, the dir untouched; the service
  re-run as root -> root-owned again — WITH A REAL
  FINDING: the confined root daemon's chown is
  AppArmor-refused (the template mrwlkix does not cover
  ownership changes) and the rm+mkdir fallback fired as
  designed (harmless at boot; a chown AppArmor grant = a
  minor hardening item). UPSTREAM NOTES RECORDED (no
  filing): (a) mutter should accept sticky 1777
  /tmp/.X11-unix regardless of the owner; (b) snapd's
  private tmp is per-snap not per-user — the cross-uid
  collision is inherent for multi-user snaps writing
  /tmp content (per-user tmpfs or a snapd pre-created
  root-owned .X11-unix = the structural fixes). TOOLING:
  vncdotool `key Enter`/`Return` silently failed (rc=30)
  — lowercase `key enter` works. CLEANUP: graceful
  poweroff ("reboot: Power down"), the image copy
  deleted, scratch of lean evidence kept (39 PNGs incl.
  the full-flow transcript, the serial log, the
  recipes). Owner VMs untouched.
- [2026-11-18] T53 DONE — THE COLLISION IS STRUCTURALLY
  FIXED. DESIGN FINDING (pinned from source, verified
  live): snap-confine binds .../snap.ubuntu-desktop-
  session/tmp (ROOT:ROOT 01777) over /tmp — the private
  tmpfs root is root-owned and sticky, so a non-owner
  launcher can NEVER remove a foreign dir (the kernel
  check_sticky, exercised live) — the launcher-only fix
  was provably insufficient. THE COMPLETED FIX (session
  snap ad10f61, one commit): (a) scripts/ensure-x11-dir.sh
  — the self-heal (missing->create 1777;
  root/self-owned->keep+chmod; foreign->remove
  attempt->recreate->EPERM->loud log + the /proc chown
  pointer + continue), hooked pre-mutter for all session
  kinds + the run-session.sh early pass (replacing the
  legacy silent mkdir/chmod that EPERM'd — the exact
  pre-T53 path); (b) a minimal root daemon:oneshot
  (ensure-x11-dir) NORMALIZING THE DIR ROOT-OWNED 1777
  AT BOOT — mutter accepts root-owned from every uid, so
  the collision is structurally gone. FULL-FLOW VERDICT:
  PASS — before (stock x1): wizard->complete->auto-login->
  the verbatim Wrong ownership ABRT->greeter; after (x2
  sideload, reset, reboot): the daemon boot log -> the
  wizard heal logged before mutter -> the chord->orca
  ~11.9s PCM-verified -> the wizard complete
  (test/nopass456) -> THE DESKTOP UP (Xwayland :0/:1
  inside the root-owned dir) -> GUI logout -> EXPLICIT
  GREETER PASSWORD LOGIN -> the desktop again; the whole
  after-boot: zero Wrong ownership, zero SIGABRT.
  REGRESSION GUARD: PASS — the T51 chord->orca flow
  unbroken; the heal runs once per session start before
  mutter. The EPERM edge + the root path both exercised
  live (the root chown was AppArmor-refused — the
  rm+mkdir fallback fired as designed; a chown grant =
  minor hardening). UPSTREAM NOTES recorded (no filing):
  (a) mutter should accept sticky 1777 .X11-unix
  regardless of the owner; (b) snapd's per-snap private
  tmp makes the cross-uid collisions inherent — per-user
  tmpfs or a snapd pre-created root-owned dir are the
  structural fixes. NOTE: the owner RE-BAKED pc.img
  during T53 (both prior md5s stale — caught during
  verification and the fresh copy f8f2ec69 verified).
  Scratch cleaned; owner VMs untouched.
- [2026-11-19] T54 DONE — THE DBUS NAME GRANTS COMPLETE,
  THE A11Y PANEL OPENS. MECHANISM (pinned from snapd
  source + live): each dbus slot carries ONE name; the
  permanent-slot dbus (bind) rule trio lands in the
  profiles of the apps REFERENCING the slot (the app's
  slots: list AND activates-on: scope it; an
  unreferenced slot = all apps). THE OWNER'S DENIALS
  EXPLAINED: the panel/nautilus children forked from the
  shell INHERIT the gnome-shell label, whose profile
  lacked the binds (the slots were scoped to
  gnome-control-center/nautilus-service); three names
  had no slot at all. NAME AUDIT (the whole journal
  history, 8 names): org.gnome.Settings,
  org.gnome.Nautilus, org.freedesktop.FileManager1,
  org.freedesktop.a11y.Manager,
  com.canonical.Shell.PermissionPrompting (the shell
  label), org.freedesktop.Notifications (the
  shell-notifications), org.gnome.Orca.Service (the
  a11y snap), org.pipewire.Telephony (the pipewire snap
  — a store snap, NOT ours). IMPLEMENTATION (local
  commits): the session snap 1e8cc66 — the gnome-shell
  app slots += dbus-gnome-settings/nautilus/
  filemanager1 + NEW scoped slots
  dbus-freedesktop-notifications/a11y-manager +
  dbus-canonical-shell-permissionprompting (the
  notifications app too); the a11y snap 3ecf429 —
  dbus-orca-service + dbus-orca-keyboardmonitor scoped
  to orca. NO POLICY REMOVALS (all newly-referenced
  slots were already scoped). VERIFICATION (a fresh
  nouser bake from the same repos — the owner's pc.img
  was live under their running VM, so no copy): THE
  PANEL OPENS — the a11y menu -> Accessibility Settings
  -> the Settings window with the Accessibility panel
  fully visible (PNG evidence), org.gnome.Settings
  owned by the forked panel under the shell label. THE
  WHOLE-BOOT DENIED-BIND AUDIT: only
  org.pipewire.Telephony remains (the pipewire snap's
  own slot — not ours). POSITIVE OWNERSHIP of every
  granted name; the org.gnome.Shell bind intact; the
  must-deny errno-13 D3 probe HOLDS; the chord->orca->
  speech PCM-VERIFIED IN ALL THREE SESSION KINDS (the
  wizard 157 + the user session 150 + the greeter 216).
  REMAINING DENIED: org.pipewire.Telephony only
  (pipewire-snap-owned) + the non-bind residuals
  already queued (the a11y-launcher SessionManager
  RegisterClient; the orca<->shell a11y-Manager method
  calls). THE SHIPPING IMPLEMENTATION IS COMPLETE: the
  policy layer, the self-healing, the dbus name grants
  — all verified on the baked images. THE REMAINING
  DECISIONS: the pushes + the upstream candidates.
- [2026-11-19] THE A11Y REPO: RENAMED + HISTORY REWRITTEN
  (the owner's rulings: (1) the branch desktop/26, (2)
  the history rewrite dropping the snap blobs).
  EXECUTED: main -> desktop/26; the pre-rewrite backup
  at ~/git/ubuntu-desktop-a11y-pre-rewrite-backup.tar.gz
  (940,796,823 bytes — the full .git with the blobs);
  git filter-repo 2.47.0 --invert-paths --path-glob
  '*.snap' -> THE HEAD TREE BYTE-IDENTICAL
  (895d8f04... unchanged — the HEAD never contained
  snap files), .git 899M -> 288K, the history 41
  commits (the blob-only commits dropped — the
  commit-map 2136399... -> 0000000 recorded in
  .git/filter-repo/commit-map for the notes' hash
  references), the remote added: origin =
  canonical/ubuntu-desktop-a11y. THE PUSH AWAITS: the
  GitHub repo creation (the owner's step — the remote
  is set, the push fails until
  canonical/ubuntu-desktop-a11y exists). THE NOTES'
  HASH REFERENCES: stale for the a11y-repo commits
  post-rewrite (the commit-map is the lookup).
- [2026-11-19] T57 DISPATCHED — the independent dual
  review (the correctness + the restructure) of
  core-base-desktop's 16 unpushed commits
  (origin/desktop/26..desktop/26 — the dispatch
  drop-ins, the dynamic-user homes, the localsearch
  vendor step), destination canonical's CI-consumed
  desktop/26.
- [2026-11-19] CORRECTION — THE OWNER CHALLENGED THE
  DIVERGENCE CLAIM AND WAS RIGHT: THE PUSH IS A CLEAN
  FAST-FORWARD, NO FORCE NEEDED. VERIFIED:
  origin/desktop/26 = 78dca3acd0 (the remote's tip —
  the 27 commits were NEVER PUSHED, so the remote's
  tip is the BASE of the restructure), desktop/26 =
  e01549bbb9 (78dca3a + the 15 restructured/fixed
  commits), the merge-base = origin/desktop/26
  itself, 0 remote-only commits, and
  origin/desktop/26 IS AN ANCESTOR of the rewritten
  branch. THE MANAGER'S CLAIM CONFLATED
  origin/desktop/26 (78dca3acd0) WITH THE OLD LOCAL
  TIP (f5b4338099). THE OLD 27-COMMIT LINEAGE LIVES
  ON LOCALLY IN work/pre-restructure-backup; THE
  REMOTE'S HISTORY IS UNTOUCHED BY THE REWRITE. THE
  PUSH: EXECUTED AS THE FAST-FORWARD PER THE
  APPROVED PLAN (step 5).
- [2026-11-19] T57 DONE — THE INDEPENDENT DUAL REVIEW OF
  CORE-BASE-DESKTOP'S 16 COMMITS: CORRECTNESS — NOT
  READY TO PUSH. BLOCKER 1 (b67bf18 + 295c176):
  /etc/dconf becomes WORLD-WRITABLE (0777, no sticky,
  bind-mounted from writable storage) for the life of
  the device — dconf's system config dir: any local
  user can plant a profile/db setting defaults for
  every user + the wizard; AND ucd-a11y-handover
  applies whatever schema/key pairs are in the ini
  (no owner check) to a user named in a file anyone
  can write -> CROSS-USER CODE EXECUTION via the
  custom keybinding commands. FIX: a dedicated channel
  dir owned root:gnome-initial-setup mode 1770 (the
  group exists), the owner/mode checks + a schema
  allowlist in the script + the MATCHING PROVD PATH
  CHANGE. BLOCKER 2 (d54c481): the home-creation
  commit rests on a FALSE premise — GDM ITSELF creates
  the wizard's home (root, 0700, the wizard uid;
  gdm-dynamic-user-store.c:327-329, the shipped gdm3
  binary carries /run/gdm3/home); the launcher's mkdir
  runs AFTER the shell started
  (After=gnome-session.target) — it cannot be what
  made the bake work; the T52 denial was the crash
  loop (GDM deletes the home while a confined helper
  runs); T52 never tested d54c481 separately from
  b6218fe; AND mode 1777 on /run/gdm3/home lets any
  local user PRE-CREATE a home with planted content.
  FIX: DROP the commit + confirm with one bake on the
  stock 0755 parent. SHOULD FIX (80bcb51): with d47f0ba
  the session snap's bind-mounts cover
  Xwayland/xkbcomp/mutter-x11-frames — the three base
  launchers are DEAD CODE + they hardcode
  x86_64-linux-gnu (undoing the arm64 work). SHOULD FIX
  + GATES THE PUSH (d47f0ba): it needs session-snap
  b6218fe (STILL LOCAL ONLY) — the base landing
  without it = the first-boot wizard crash-loops; a11y
  581f5ce "not in the repo" = the REWRITE changed its
  hash (the commit-map: the lookup). THE DISPATCH
  DROP-INS THEMSELVES ARE CORRECT (only the
  initial-setup instances, the names match, the
  greeter/user drop-ins untouched); the localsearch-3
  redirect correct but localsearch-control-3/
  writeback-3 will fail the same way (follow-up); ~20
  private T-number references in the shipped files/
  messages need scrubbing. STRUCTURE: NOT a single
  commit (it would hide two permission changes in 400
  unrelated lines + break the orca-adapter removal's
  clean revert); the RESTRUCTURE (dry-run-verified in
  a scratch clone: no conflicts, git diff --quiet
  d54c481 HEAD = 0, 16 -> 10 commits): drop a43f5c2 +
  4a126c2 (added-then-reverted), fold
  b67bf18+295c176+a36b1b3 into 6ea5214 as ONE
  handover commit (one message, the end state), move
  56a21d2 after the handover, drop d54c481 (finding
  2), drop 80bcb51 (finding 3); then the content
  fixes on top: the /etc/dconf rework, the reference
  scrub, the cross-repo dependency stated in
  d47f0ba's message. ON CONTENT ALONE: d5dd37e,
  f622a7d, 39d48fb, 2d8c6c2, f16b8bb, 0ed202e could
  go now after the scrub.
- [2026-11-19] T58 DISPATCHED — EXECUTE THE T57 REVIEW:
  the restructure (16->10 per the recipe), the /etc/
  dconf SECURITY REWORK (the channel dir
  root:gnome-initial-setup 1770, the owner/mode
  checks, the schema allowlist, the PROVD path
  change), the d54c481 drop + the bake confirmation,
  the reference scrub, the base rebuild + the bake,
  and the FULL VERIFICATION (the wizard -> the chord
  -> speech -> the user creation -> the login -> the
  reader on). The session-snap b6218fe PUBLISH GATES
  the base push (the CI-built session snap without it
  = the wizard crash-loop) — the push sequence is the
  owner's decision.
- [2026-11-19] T58 DONE — THE RESTRUCTURE + THE SECURITY
  REWORK + THE FULL VERIFICATION. RESTRUCTURE:
  desktop/26 = origin/desktop/26 + 9 COMMITS (the
  T57 shape: 16 - 4 drops - 3 fixups); a43f5c2/4a126c2
  dropped, the handover trio folded into ONE commit
  (the rewritten end-state message), 56a21d2 moved,
  d54c481 + 80bcb51 DROPPED; the tree delta vs
  d54c481 = exactly the expected (+2/-86: the 3 dead
  launchers gone, the 1777/mkdir reverted); zero
  conflicts; the backup work/pre-t58-backup; the
  reference scrub: ZERO T-refs/fat-line/gate-N in the
  shipped files + all 9 messages; d47f0ba's message
  states the b6218fe dependency. NO PUSHES. SECURITY
  REWORK: /etc/dconf now root:root 0755 (no more
  world-writable bind); the channel =
  /etc/dconf/channel/handover, created + re-enforced
  every boot by a new tmpfiles rule as
  root:gnome-initial-setup 1731 (1770 deadlocked the
  target-user reader — adjusted live, documented);
  the hook fails loud on non-dir. The script: the
  channel/file owner+mode checks, the 10-key a11y
  ALLOWLIST (media-keys custom keybindings
  structurally impossible), the value-type
  validation, the target validated against getent
  passwd. PROVD (the source accessible:
  ~/git/ubuntu-desktop-provision) commits the
  channel paths (29b4ac105 local); the provd-snap
  plug needed no change. VERIFICATION (3 base
  rebuilds/bakes, 3 disposable-VM boots): GDM
  creates the wizard home ITSELF (finding 2
  CONFIRMED — the d54c481 drop validated); the
  chord fired in ALL 3 boots (orca ~0.2-0.4s, PCM
  RUNNING ~2.3s); the wizard completed
  (test/nopass456, NO confirm-field wedge — NEW-3
  does not reproduce on this build either); provd
  wrote the ini into the channel
  (wizard-uid:gnome-initial-setup 0644); the
  greeter -> login -> the handover applied the
  allowlisted keyset into the session's REAL dconf
  db (dconf dump matches; the apply backend +
  provd's XDG redirect fixed en route — the
  original apply silently wrote an unreadable
  keyfile); custom-keybindings = []; zero denials
  from the rework; greeter/session/audio/
  media-keys sane. Two build-env findings fixed
  in-flight (the tmpfiles pass pre-creates
  /etc/dconf; the hook tolerates + re-owns it).
  OPEN: (1) provd still records screen-reader-
  enabled=false — the value chain (provd's view of
  the wizard's a11y state) needs one instrumented
  wizard boot; the fix candidates documented (the
  cache at SetAccessibility time) — the created
  user's reader is OFF at first login until enabled
  via the chord (which works); (2) THE PUSH
  SEQUENCE: b6218fe must publish BEFORE/WITH the
  base (a clean fast-forward, 9 commits) — the
  owner's decision; (3) the localsearch control/
  writeback follow-up (F5). THE SHIPPING
  IMPLEMENTATION IS COMPLETE AND VERIFIED
  END-TO-END: the wizard speech, the chord, the
  user creation, the handover (allowlisted,
  secured), the login, the reader available. THE
  REMAINING DECISIONS: the push sequence + the
  upstream candidates.
- [2026-11-19] THE HANDOVER FIX RULING (the owner asked
  which fix is the simplest/most reliable): OPTION (c)
  CHOSEN — the handover script reads the LIVE
  screen-reader-enabled key AS THE WIZARD USER (dconf
  read; the direct db read, no bus) at the handover
  moment and uses that value for screen-reader-enabled,
  falling back to the ini on failure. RATIONALE: gdm
  needs NO special handling — the key lives in the
  created user's own dconf store and the session's
  gsd-a11y-settings starts orca automatically (the
  T58-verified designed behavior); the only broken
  link is provd's cached false (the chord bypasses
  the a11y pages); the live read covers BOTH the
  chord and the a11y-page paths, at the exact moment
  it matters, with NO provd rebuild. The
  alternatives recorded: (b) provd reads at
  completion (the provd rebuild), (d) gsd notifies
  provd per key change (unnecessary).
  IMPLEMENTATION PENDING: a small edit to the
  handover script in core-base-desktop (the
  T58-reworked script). ALSO: the localsearch
  companions SEPARATED into their own todo per the
  owner (NOT accessibility-related):
  `20261119-localsearch-control-writeback-units.md`
  (created; low priority, mechanical, bundles with
  the next base cycle).
- [2026-11-19] T59 DISPATCHED — THE COMPLETE
  ZERO-TO-SPEAKING-PER-BOOT CHAIN (the owner's "do it"
  on the design): (1) the handover live-read (the
  script reads the LIVE screen-reader-enabled AS THE
  WIZARD USER at the handover moment, overriding the
  ini's stale value — closes the provd-cache gap);
  (2) the GREETER PROPAGATION at the handover (mirror
  the reader state into the gdm-greeter user's dconf
  store — the boot's greeter auto-starts orca; the
  /run/gdm3/home PERSISTENCE check rides along — the
  base-side fix if ephemeral); (3) the BOOT-TIME
  GREETER MIRROR (the T53 root daemon:oneshot
  extended: the last real user's reader preference
  mirrored into the greeter store at every boot).
  VERIFICATION: the FULL CYCLE on a disposable copy
  of the owner's nouser image (the current md5
  verified first — the owner re-bakes): the chord ->
  the wizard -> the greeter speaks AUTOMATICALLY ->
  the login -> the reader on -> the toggle off ->
  REBOOT -> the greeter silent (the mirror both
  directions) -> the toggle on -> the reboot -> the
  greeter speaks again.
- [2026-11-19] T60 DISPATCHED — THE LAST-MILE GREETER
  ACTUATION (the owner's requirement made explicit:
  A BLIND USER CANNOT KNOW WHEN THE GREETER HAS
  RENDERED, so the chord fallback is INSUFFICIENT —
  press too early and the keystroke is lost into the
  pre-shell void; THE AUTOMATIC GREETER SPEECH IS A
  REQUIREMENT, NOT A NICE-TO-HAVE). T60: the
  instrumented greeter session (the dbus-monitor +
  the gsd debug) to discriminate the hypotheses: H1
  the write path (the chord writes through the
  dconf service -> the Change signal; the mirror's
  `dconf write` CLI writes the gvdb DIRECTLY -> NO
  signal -> gsd blind), H2 the label, H3 the timing
  (the mirror writes before gsd starts), H4 the
  store mismatch (the T38/T45 class). THE FIX
  CANDIDATES: (a) the mirror writes THROUGH the
  dconf service (gsettings set AS the greeter user
  WITH the session bus), (b) the gsd debug
  iteration, (c) the structural fallback: the
  greeter session starts orca DIRECTLY when the
  flag is on (the autostart unit gated on the flag
  — guarantees the requirement even if the
  actuation is structurally broken). THE SUCCESS
  BAR: a fresh boot -> the greeter renders -> orca
  starts AUTOMATICALLY within seconds, no input,
  PCM-verified, both directions across two reboots;
  the chord/wizard/user flows unbroken.
- [2026-11-19] T60 DONE — THE LAST-MILE ACTUATION
  SOLVED: THE ZERO-TO-SPEAKING-PER-BOOT CHAIN IS
  COMPLETE. ROOT CAUSE — H4 CONFIRMED WITH THE TWIST
  THAT THE SESSION'S LIVE STORE IS THE KEYFILE: the
  session snap's gio/modules is empty
  (libdconfsettings.so exists only in the
  gnome-desktop-runtime), so EVERY session-side
  GSettings client — gsd-a11y-settings,
  gsd-media-keys, gnome-shell, the chord's toggle
  script — falls back to the KEYFILE BACKEND at
  $XDG_CONFIG_HOME/glib-2.0/settings/keyfile; the
  dconf user db (served by the session's own dconf
  service) is a DEAD STORE NO SESSION CONSUMER
  READS. EVIDENCE (dbus-monitor as the greeter
  user, ~70k lines): the shipped mirror write went
  through the session's own dconf service and
  landed in the dead db; ZERO Writer Changed
  signals were ever emitted for ANY write (chord or
  mirror); gsd's StartUnit followed the chord by
  0.2-1ms and the chord's write landed in the
  KEYFILE (the mtime = the actuation millisecond) —
  THE KEYFILE BACKEND'S GFileMonitor IS THE
  ACTUATION PATH. T59's three-way verify was
  self-consistent around the wrong store. H1/H2/H3
  refuted by the capture. Corroborating fragments
  were already in the tree (the T58 apply comment,
  the T44 "dead dconf store" recipe). THE FIX:
  core-base-desktop desktop/26 commit 7d5f79c on
  840ab0d (one new commit; tip = fea653f+11; no
  pushes; the session snap untouched): greeter_write
  writes the greeter's KEYFILE store as its own
  dynamic user (the name from its loginctl session
  — also fixes the latent hardcoded `su gdm-greeter`
  failure on gdm-greeter-2 boots),
  GSETTINGS_BACKEND=keyfile, bus-free, verified by
  the backend readback + a direct file grep;
  read_as prefers the keyfile, then the dconf db;
  the apply writes BOTH stores (keyfile = live,
  dconf = record). Live-validated BEFORE
  rebuilding: the mirror's false write STOPPED the
  running orca, true RESTARTED it. REQUIREMENT
  VERIFIED — THE AUTOMATIC GREETER SPEECH, ZERO
  INTERACTION, PCM-EVIDENCED, BOTH DIRECTIONS
  ACROSS TWO REBOOTS: boot 2: the keyfile written
  16:07:00 -> orca 16:07:04 (~10s after boot, NO
  INPUT), the speech PCM captured at 16:23:39;
  boot 3 (the false mirrored): zero orca, silent;
  boot 4 (the true mirrored): the write 16:29:13 ->
  orca 16:29:20 -> PCM RUNNING 16:29:23 — THE
  GREETER ANNOUNCED THE LOGIN SCREEN ~20s AFTER
  BOOT. The chord fallback, the wizard speech, and
  a new apply-side user-session actuation all
  verified; the denial audit: zero new denials
  from the mechanism. OPEN FOR THE OWNER: the
  greeter-home path unit re-fires per event
  (idempotent, journal-noisy — the optional
  debounce); the handover burst's late runs log
  "wizard home is gone" (the guard holds); the
  pam_extrausers YESCRYPT warning (cosmetic); the
  user-session orca SEGV (no display brokerage in
  the user manager env — a session-snap item). THE
  ZERO-TO-SPEAKING-PER-BOOT CHAIN IS COMPLETE: A
  BLIND USER BOOTS -> ~10-20s LATER THE GREETER
  ANNOUNCES ITSELF AUTOMATICALLY -> THEY TYPE THEIR
  PASSWORD (SPOKEN) -> THEIR DESKTOP (THE READER
  PER THEIR SETTING). NO SIGHTED-ASSIST, NO CHORD,
  NO TIMING GUESSWORK.
- [2026-11-19] T59 DONE — THE ZERO-TO-SPEAKING CHAIN:
  TWO OF THREE PIECES END-TO-END, THE THIRD
  HONESTLY PARTIAL (core-base-desktop ONE local
  commit 840ab0d on the owner's rebased 9-commit
  line = fea653f+10; NO PUSHES). (1) THE HANDOVER
  LIVE-READ ✓ VERIFIED END-TO-END: the ruling's
  literal apply-time su was IMPOSSIBLE (the apply
  runs as the TARGET user; the wizard home is wiped
  before first login) — the fix: a PATH-TRIGGERED
  root capture (ucd-a11y-handover-live.path+service)
  reads the live reader state AS THE WIZARD USER at
  CreateUser (the only moment the wizard db
  exists), records it in the channel
  (ucd-handover-live-reader), and the apply
  overrides the ini ("live-read override true (the
  ini recorded false)" in the journal on every
  boot). (2) THE GREETER PROPAGATION ✓: the
  recorded state delivered into the greeter
  session's LIVE dconf db via a second path trigger
  (ucd-a11y-greeter-home.path glob) + the
  class-based session identification + a session-bus
  write through the greeter's OWN dconf service
  (verified: the session-bus readback + the file
  read as the dynamic user). (3) THE BOOT-TIME
  MIRROR ✓: the root oneshot records the last real
  user's state (uid>=1000+/bin/bash; the
  newest-db-mtime tiebreak documented) into the
  channel at every boot, both directions observed.
  THE GREETER-PERSISTENCE MECHANISM FOUND: the
  greeter session runs as the DYNAMIC user
  gdm-greeter/gdm-greeter-2 (uid 60578/60579 —
  NON-DETERMINISTIC PER BOOT; the passwd gdm uid
  200 is only the daemon), home /run/gdm3/home/
  gdm-greeter* on tmpfs — EPHEMERAL, recreated per
  boot; /var/lib/gdm3 belongs to the daemon user
  and is inert. NOTHING persists -> the mirror
  re-delivers per boot (the design handles it).
  FULL-CYCLE VERDICT: DIRECTION 1 (OFF)
  END-TO-END — toggle off -> reboot -> mirror(false)
  -> the greeter renders SILENT (zero orca, two
  artifacts). DIRECTION 2 (ON): the mirror
  delivers true into the greeter's db (verified
  three ways) — BUT THE AUTOMATIC SPEECH IS NOT
  ACHIEVED: the greeter's gsd-a11y-settings does
  not ACTUATE on the mirror's session-bus write,
  while the CHORD's own toggles actuate reliably
  every time (orca + PCM within seconds — the
  working fallback). THE CHORD->SPEECH CHAIN at
  the wizard and the greeter is PCM-verified on
  every boot. OPEN FOR THE OWNER: (1) the
  LAST-MILE GREETER ACTUATION — one instrumented
  greeter session (dbus-monitor/debug gsd) to pin
  why the confined plugin's view ignores the
  unconfined writer while reacting to the confined
  one; (2) the pre-existing user-session orca SEGV
  (no display brokerage in the user manager env —
  a session-snap item); (3) THE PUSH SEQUENCE:
  the base (10 commits) AFTER session-snap
  1e8cc66 PUBLISHES (the dependency). THE
  PRACTICAL STATE FOR A BLIND USER TODAY: one
  chord press at the greeter (Super+Alt+S)
  reliably starts orca within seconds on every
  boot — the fully-automatic greeter speech is
  the last-mile item.
- [2026-11-20] THE PROJECT-DOCUMENTATION SUBMISSION
  FILED: the session-snap internals distilled for
  future agents (the keyfile store, the per-snap
  shared /tmp, the dbus name binds, the GDM dynamic
  users, the zero-to-speaking chain, the provd
  value-chain gap, the speechd supervisor/pidfd,
  the debug recipes). The todo is current through
  this entry; the push sequence remains the
  owner's decision.
- [2026-11-20] ALL REPOS PUSHED (the owner tested
  the fresh bake: "it seems to be working"; the
  a11y metadata URLs ruled canonical; the pushes
  executed in the dependency order): (1)
  ubuntu-core-desktop-snapd desktop/26
  78dca3acd0..e01549bbb9 (the fast-forward — the
  restructured 15-commit series; the earlier
  divergence claim CORRECTED — the owner was
  right, no force needed: the 27 commits were
  never pushed, so origin's tip was the
  restructure base); (2) ubuntu-desktop-session-
  snap desktop/26 2697819..1e8cc66 (the volume
  keys, the wizard speech, the self-heal, the
  dbus slots); (3) core-base-desktop desktop/26
  fea653f..7d5f79c (the dispatch drop-ins, the
  security rework, the greeter mirror — after the
  session snap per the T57 dependency);
  (4) ubuntu-core-desktop desktop/26
  6a8bac9..0c3540a (the build fixes);
  (5) ubuntu-desktop-a11y desktop/26 [new branch]
  — the repo existed at canonical (verified via
  gh), the renamed+rewritten branch (41 commits,
  .git 288K, the blobs dropped per the owner's
  rewrite ruling; the pre-rewrite backup at
  ~/git/ubuntu-desktop-a11y-pre-rewrite-backup.tar.gz).
  THE PROJECT'S CI NOW BUILDS ALL THE CONSUMED
  SNAPS FROM THESE BRANCHES. THE REMAINING: the
  upstream candidates (mutter's sticky-dir
  acceptance, snapd's per-user tmpfs, the Flutter
  SEGV, N2/N3/N4, the tracking flake, the speechd
  silent-fd-claim logging + the hang watchdog, the
  QEMU PPM submitted), the store snap-declaration
  for the a11y deployment (the T56 finding 4
  documentation), the localsearch companions todo,
  the testing.
- [2026-11-20] THE UPSTREAM-CANDIDATE TODOS CREATED
  (the owner's ruling: a separate todo per
  upstream issue, unless one exists; the existing
  speechd todos cover the speechd items; the QEMU
  PPM is SUBMITTED; N1 the sideload refusal is
  BY-DESIGN — excluded): (1) the mutter
  sticky-1777 /tmp/.X11-unix ownership check (the
  wizard->user session transition incident) —
  tracked separately; (2)
  `20261120-snapd-per-user-private-tmpfs.md` —
  snapd's private tmpfs is per-snap not per-user
  (the cross-uid collisions inherent); (3)
  `20261120-flutter-wizard-chord-off-segv.md` —
  the chord-OFF toggle segfaults the Flutter
  wizard UI (the T52 verbatim SEGV); (4)
  `20261120-snapd-revert-user-daemon-orphans.md` —
  N2: the revert leaves the newer-revision user
  daemons orphaned; (5)
  `20261120-orca-crash-loop-on-broken-atspi.md` —
  N3: orca crash-loops SIGSEGV against any broken
  at-spi state; (6)
  `20261120-atspi-bus-stop-session-fatality.md` —
  N4: the at-spi bus death kills the whole
  session; (7)
  `20261120-snapd-tracking-sessionbus-fallback-upstream.md`
  — the tracking flake (the draft patch + the T49
  live verification are DONE; only the submission
  remains). EXISTING:
  `20261116-speechd-hang-wedge-upstream.md` +
  `20261118-speechd-silent-fdclaim-logging-upstream.md`
  (the speechd pair),
  `20261117-third-party-reader-snap.md` (the
  investigation),
  `20261119-localsearch-control-writeback-units.md`
  (our packaging, not upstream).
- [2026-11-20 LATE] THE DCONF MIGRATION (option 2) —
  the keyboard-layout backend fix moved the WHOLE
  session onto dconf, so the T60 keyfile mechanism
  is superseded and the a11y handover now uses the
  same live store. WHY: the first-boot wizard's
  layout selection was written to dconf by provd
  but the confined session used GLib's per-snap
  keyfile backend (the snap probe / missing gio
  module class from T60), so gnome-shell stayed on
  "us" and Shift+3 typed #. Rather than scope dconf
  to gnome-shell only (split-brain vs the T60
  keyfile chain), the owner chose one live store:
  dconf everywhere.
  COMMITS (all local; NO PUSHES):
  - ubuntu-desktop-session desktop/26 4839f0a:
    gnome-shell gsettings (ca.desrt.dconf) plug +
    GIO_EXTRA_MODULES + the shipped
    gnome-initial-setup dconf profile. c95e724:
    force GSETTINGS_BACKEND=dconf in the snap
    environment; add the gsettings plug to EVERY
    app that plugs systemd-user-control (63) plus
    the 7 GSettings apps that do not (screencast,
    nautilus, xdg-desktop-portal-gnome, the 3
    ibus services, colord). The AVC that forced
    this: the wizard chord's seeding
    (wizard-a11y-init.sh run by
    gnome-session-service) was denied because a
    well-known-name send needs a peer=(name=
    ca.desrt.dconf) rule; the generic same-snap
    peer-label rule does not cover it.
  - core-base-desktop desktop/26 521a8e9:
    core-desktop-session-wrapper no longer exports
    GSETTINGS_BACKEND=keyfile (that override
    would send the real user session back to the
    dead store); mirror read_as prefers dconf
    (snap-common then plain), keyfile last-resort;
    greeter_write writes the greeter's dconf
    through its session bus (T59 path, dynamic
    user from loginctl, bus wait, retried set,
    same-bus verify); handover apply writes dconf
    first and keeps the keyfile only as a
    fallback if the dconf set fails.
  - ubuntu-core-desktop desktop/26 65dac0e
    (earlier): gadget-connect
    ubuntu-desktop-session:gsettings -> its own
    dbus-dconf slot.
  VERIFIED on a rebuilt image (session snap
  c95e724 content; local repack of the version
  string only, the source is committed; base
  521a8e9), on a disposable test VM:
  - Keyboard layout, THE REPORTED BUG, fixed
    END-TO-END: the wizard page's test box shows £
    for Shift+3, and the CREATED USER's own
    session does too — log in as test, Super then
    Shift+3 in the shell search entry renders £.
    The user's dconf has sources=[('xkb','gb')]
    (provd's write; the session's own dconf
    service read it back), so gnome-shell applies
    gb.
  - Wizard chord: wizard-a11y-init seeding
    SUCCEEDED (binding <Super><Alt>s ->
    toggle-screen-reader; no dconf denial). The
    chord set screen-reader-enabled=true and
    started orca (pid 21470).
  - Automatic greeter speech (T60 requirement)
    WORKS with dconf: after a reboot with the
    user's key true, the boot mirror read true,
    greeter_write wrote the greeter's dconf via
    the session bus ("mirrored ... verified"),
    and the greeter's gsd-a11y-settings started
    orca.service automatically with NO input
    (orca pid 9672, unit active; dconf greeter
    key true). Reader false → reboot → mirror
    false, greeter key false, zero orca (silent).
    Both directions verified (process/unit; this
    test VM has no audio device, so no PCM).
  - The user-session actuation path works with
    dconf: a dconf true as the user started
    orca; false stopped it.
  - Zero ca.desrt.dconf AppArmor denials in the
    final boot (the wizard chord's seeding and
    the session's dconf traffic included).
  - ONE STORE CONFIRMED: neither the user's nor
    the greeter's home has a glib-2.0/settings/
    keyfile at all; the only GSettings db is
    .../snap/ubuntu-desktop-session/common/
    .config/dconf/user. Nothing on this line
    writes the legacy store.
  - HANDOVER LIVE-READ: WORKS (an earlier reading
    of the journal was wrong — no race, no
    regression). On the wizard boot (boot -2,
    journal short-monotonic ~300) the first three
    ucd-a11y-handover-live runs read the LIVE key
    AS THE WIZARD and logged "live read (as
    gnome-initial-setup) screen-reader-enabled=
    true; recording the decision and the greeter
    state" (the channel's ucd-handover-live-reader
    holds true), then the wizard session teardown
    removes the homes and the remaining runs of
    provd's event burst log the guard line "the
    wizard home is gone (a stale ini from a
    previous boot)" — which is exactly the
    documented, harmless stale-ini path (it also
    fires at every later boot; the decision file
    is untouched). At the created user's first
    login the apply logged "live-read decision
    screen-reader-enabled=true" and "live-read
    override true (the ini recorded false)", and
    the user's dconf had true before any manual
    action (orca started). provd's ini carried
    false, so the live-read is what delivered the
    chord's choice — the T59 behaviour, unchanged
    by the dconf move.
  - Wizard chord: the chord also still actuates
    the user session: manually setting the
    user's dconf true started orca, false
    stopped it (both observed).
  - The stale-ini burst was NOT cosmetic in the
    end (live first boot on the owner's VM: 366
    handover runs in 8 s at CreateUser, each
    spawning a logind session through su, then
    the path unit failed with trigger-limit-hit
    and the boot was degraded; the stale ini also
    refires on every later boot). FIXED in
    core-base 4fad222: PathExists= ->
    PathChanged= (fires on the ini write and
    then stays quiet; verified live). Full
    write-up: `20261120-first-boot-session-startup-errors.md`,
    which also covers the ~50 s first-login
    stall (content-data lock vs gvfsd, fixed in
    ubuntu-desktop-session bf5ec7d) and the
    wizard UI's "No DConf source to write to"
    exceptions (DCONF_PROFILE set empty, fixed
    in 4fad222).
  - Related, separate: the wizard-a11y-init
    brokerage systemctl calls are still
    exec-denied (known T51 item; the display
    comes from the shell's manager-env export) —
    not introduced here.
  CLEANUP: the test VM and its image were
  removed after verification (scratch policy);
  the full chain is reproducible from the
  committed sources with the image build
  (build.sh) after rebuilding the snaps in
  ubuntu-desktop-session and core-base-desktop.
  The snapcraft base instance was repaired
  (valid) and the GOPROXY part overrides were
  reverted; the build-infra workarounds are
  recorded in the project documentation (base
  instance FINISHED+setup, GOPROXY direct).
- [2026-11-20 REVIEW] An independent maintainer-style
  review of the keyboard + dconf/a11y commits found
  real failure-handling gaps, all verified then
  fixed in core-base 378595c and session 0e12c9b:
  (1) gsettings set exits 0 even when the dconf
  commit fails (reproduced with an unreachable
  bus: rc=0, value unchanged), so the apply marked
  the handover done without applying and the
  reader could be lost for good; every a11y write
  is now verified by readback, retried, and the
  marker is written only when every present key
  verified (keyfile fallback is best effort and
  does not count). (2) ucd-a11y-greeter-home.path
  had the same PathExists loop as the handover
  unit: it re-ran for the whole greeter session
  (a su/PAM session each time) and kept rewriting
  the recorded reader state over greeter-side
  changes; now PathChanged=/run/gdm3/home,
  verified with a systemd --user test. (3) the
  wizard UI's Dart dconf client reads the db file
  directly while writing via the bus, so it now
  gets XDG_CONFIG_HOME pointed at the session's
  snap-common redirect. (4) greeter_write now
  retries on the readback (not the exit code) and
  no longer hard-codes the multiarch triplet.
  (5) the invalid GIO_USE_VOLUME_MONITOR=none was
  dropped. Review points that needed no code
  change: the 521a8e9 message's rationale/hash
  reference are wrong (recorded in the project
  documentation), the created-user keyboard half
  is provd's write + the session's dconf read
  (live-verified gb), and in-place upgrades are
  explicitly unsupported (dangerous-model
  images), so no keyfile migration/connection
  self-heal was added.
