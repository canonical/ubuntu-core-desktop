# Update all regular Ubuntu Desktop snaps from core24 to core26 (2604 content)

## Impact / Priority

No priority stated in the original note: this is requested migration
work, not a live bug. What a real user gains once it lands: 26.04 snap
apps still based on core24 / 2404 content (e.g. firmware-updater,
App Center) pick up the 2604 content -- mesa-2604 >= 26.2.3 (the
NovaLake enablement need) included -- which only lands as the 26.04
platform launches. Impact derived from the original note's described
symptoms.

## Context

Request from enablement engineer (2026-11-04):

> Intel NovaLake enablement for 26.04 needs mesa-2604 >= 26.2.3
> (currently latest/edge; stable has 26.0.3). Many 26.04 snap apps are
> still based on core24 / 2404 content (ex: firmware-updater, App
> Center...). Update them to base core26 + mesa-2604. mesa-2604 26.2.3
> hits stable when platform launches.

Working method:
- Working copies: separate scratch clones (github/ and launchpad/
  subdirectories), kept apart from the regular repos
- Build: snapcraft --use-lxd on host (snapcraft 9.2.1, LXD default
  provider)
- Test: multipass 26.04 VM "core26-build" - sideload, connect 2604
  content, screenshot check EVERY snap via xvfb + dbus-run-session,
  PNG transferred back with `multipass transfer`.
- Rules:
  - 2604 content snaps (mesa-2604, gnome-core26) already exist - NEVER
    forward-port a 2404 snap; just point consumers at the 2604 snap.
  - extensions: [gnome] auto-wires gnome-core26 + mesa-2604 (gpu-2604)
    on core26 (snapcraft/extensions/gnome.py:32, gpu_extension.py:78).
  - Host stays untouched - all install/testing in the VM.
  - PRs to GitHub repos; merge proposals to ~desktop-snappers LP repos
    (proposed from personal namespace, team merges).
  - firefox/thunderbird: stable branches only (not beta/esr/nightly).

## Per-snap recipe

1. clone (done below)
2. branch core26-update
3. snapcraft.yaml: base: core26 + 26.04 build/stage package fixes
4. snapcraft --use-lxd
5. copy snap to VM, snap install --dangerous,
   snap connect <snap>:gpu-2604 mesa-2604 / gnome-core26 as applicable
6. dbus-run-session -- xvfb-run snap run <app>; screenshot; verify GUI
7. PR / merge proposal; tick here

Status legend: [ ] todo  [~] in progress  [x] done  [!] blocked/flagged

Tracking file: this issue.

## GitHub repos

- [x] firmware-updater: canonical/firmware-updater main (DONE: core26
  snap built; ldd clean, GUI libs resolve from mesa-2604 26.2.3;
  committed)
- [x] snap-store / App Center: ubuntu/app-center main (DONE: core26
  snap built; ldd clean; committed)
- [x] desktop-security-center: canonical/desktop-security-center main
  (DONE: core26 snap built; GUI screenshot OK (needs snapd-control
  connected - manual interface); committed)
- [x] prompting-client: canonical/prompting-client main (DONE: core26
  snap built; daemon runs; rust plugin default toolchain replaces
  rust-deps staging; committed)
- [x] snapd-desktop-integration: snapcore/snapd-desktop-integration
  main (DONE: core26 snap built; service runs; committed)
- [x] snap-tpmctl: canonical/snap-tpmctl main (DONE: core26 snap
  built; CLI runs; systemd-cryptsetup now its own package; committed)
- [x] authd-google: canonical/authd main snap/variants/google/ (DONE:
  core26 snap built+installed; service registered (dbus-activated);
  variant yaml updated (prepare-variant copies at build))
- [x] ubuntu-desktop-bootstrap: branch
  snap/ubuntu-desktop-bootstrap/main (DONE: core26 snap
  built+installed (classic); python3.12 -> 3.14 port: staged
  libpython3.12-* -> libpython3.14-*, python3.12-minimal ->
  python3.14-minimal, hardcoded interpreter paths in apps and
  snap/local/subiquity-server; subiquity-server daemon active; ldd
  clean (GUI needs EGL - Xvfb limit))
- [x] firefox: canonical/firefox-snap, stable branch only (DONE
  2026-11-05: core26 changes committed 24d33b3 - base, GNOME_SDK_SNAP,
  LP#2016358 gpu-2604 mount, ffmpeg sonames
  (libavcodec62/libsvtav1enc2/libjxl0.11/librav1e0.8). Built
  firefox_159.0.1-1_amd64.snap, sideloaded, content interfaces
  auto-connected; ldd 0 "not found"; libX11 resolves from
  $SNAP/gpu-2604/mesa-2604; bundled libnss3 satisfies NSS_3.126;
  `snap run firefox --version` -> 159.0.1 (EGL GUI can't render under
  Xvfb - ldd + version are the agreed test). PR:
  canonical/firefox-snap#185 -> stable)
- [x] ubuntu-desktop-init: branch snap/ubuntu-desktop-init/main (DONE:
  core22 -> core26; architectures -> platforms; built; ldd clean)
- [x] factory-reset-tools: branch snap/factory-reset-tools/main (DONE:
  core26 snap built)

## Launchpad repos (~desktop-snappers/+git/<name>)

- [x] gnome-calculator: ref stable (DONE: base
  core26+gnome-core26+libgvc7; built, sideloaded, auto-connected
  gpu-2604/gnome-core26, GUI screenshot OK ->
  gnome-calculator-core26.png). NOTE: core26 snaps need systemd user
  session for snap run (linger) - see forum snapcraft.io/t/46210;
  gui-test.sh handles via user bus.
- [x] gnome-contacts: ref stable (DONE: core26 snap built+installed;
  GUI screenshot OK (25KB). New recipe: use the 26.04 archive
  EDS/folks/libical stack (same versions: E-D-S 3.62.1, folks
  0.15.12, libical 3.0.20 w/ bundled glib bindings) instead of
  source-building, working around the gnome-core26-sdk g-ir-scanner
  limit; committed acfcf90)
- [x] gnome-characters: ref stable (DONE: core26 snap built; mozjs
  deps dropped - gjs+libmozjs-140 from gnome-core26; screenshot OK)
- [x] eog: ref stable (DONE: + vendored Fedora/Debian
  girepository-2.0 port + NEW librsvg-2.59 render-document patch
  (review-hardened: viewBox/abs-unit fallbacks, ceil, bounds+ status
  checks; normal AND viewBox-only SVG rendering verified); libpeas
  staged + loader layout rebound into snap (verified reachable);
  screenshot OK)
- [x] gnome-logs: ref stable (DONE: core26 snap built, sideloaded,
  auto-connected 2604 content, screenshot OK)
- [x] evince: ref stable (DONE: core26 snap built, screenshot OK)
- [x] cheese: ref stable (DONE: clutter/clutter-gtk staged from
  archive; gnome-video-effects 0.6.0 built from source; gir gen off;
  g_object_ref cast fix; screenshot OK)
- [x] simple-scan: ref simple-scan (DONE: core26 snap
  built+installed; GUI screenshot OK (22KB); libgusb2a; vendored
  sane-backends gcc15/16+glibc-2.43 patches (as in the 26.04 deb);
  sane-airscan aligned to deb's 0.99.37 (gcc const fix))
- [x] gnome-text-editor: ref gnome-text-editor (DONE: core26 snap
  built+installed; GUI screenshot OK (5.5KB))
- [x] gnome-calendar: ref stable (DONE: core26 snap
  rebuilt+installed; GUI screenshot OK (25KB) via snap-local wrapper
  that re-exports LIBGWEATHER_LOCATIONS_PATH after the command chain
  (desktop-launch in gnome-core26 overrides it with a stale path);
  archive libical 3.0.20 deb-aligned; E-D-S introspection+vala off)
- [x] gedit: ref stable (DONE: + vendored gedit#614 patch porting
  engine to girepository-2.0 API (as in the 48.1 deb); libpeas+Peas
  typelibs staged from archive; libpeas loader layout added pointing
  into the snap (verified reachable); stale layouts dropped)
- [x] evince: ref stable (DONE: core26 snap built, screenshot OK)
- [x] gnome-clocks: ref stable (DONE: core26 snap built, screenshot
  OK)
- [x] thunderbird: ref beta (DONE 2026-11-05: core26 changes rebased
  onto beta 160.0b5-1 per Nathan Teodosio's review of LP 514127 (LP is
  only a mirror for thunderbird; PRs go to ubuntu/thunderbird GitHub):
  2 commits f7e00be "Rebase to core26" + 60b976c "layout: use
  $CRAFT_ARCH_TRIPLET_BUILD_FOR for the libcanberra bind" (split per
  review; explanatory commit bodies + added yaml comments dropped per
  review). Built thunderbird_160.0b5-1_amd64.snap, sideloaded, GUI
  screenshot OK (thunderbird-beta-core26.png); PR:
  ubuntu/thunderbird#69 -> beta. LP proposal 514127 superseded.)

## PR / merge proposal status (2026-11-09)

LP MPs (12, from ~chris-bainbridge/<repo>/+git/core26-update, filed
11-05): all 12 branches UPDATED 11-09 with review-feedback commits
(pushed): cleanup part dropped everywhere; gsettings declared
explicitly in gedit, clocks, logs, characters, eog, cheese,
simple-scan, calendar, contacts, text-editor, evince
(calculator/thunderbird already had it). gnome-calendar MP 514119:
also removed the snap-local gweather wrapper (reviewer asked for
upstream fix instead). Reviewer: Alessandro Astone (aleasto) -
feedback on MP 514128 (calc) and MP 514119 (calendar). Draft replies
to the LP feedback are prepared (posting needs LP web login or
launchpadlib OAuth).

GitHub PRs:
- ubuntu/thunderbird#69 (Rebase to core26, into beta) MERGED 11-05
- ubuntu/thunderbird#70 (Drop the cleanup part) OPENED 11-09
- canonical/snapcraft-desktop-integration#45 (gweather path fix, ref
  ubuntu/gnome-sdk#387) OPENED 11-09
- ubuntu/gnome-sdk issues #385/#386/#387 (ours, filed 11-05) OPEN
- firefox: built + verified (firefox_159.0.1-1); PR #185 CLOSED
  upstream (superseded by their #184, cherry-picked to stable)
- 11-09 aleasto feedback on ubuntu/app-center#2280: flutter apps need
  gsettings for accent color -> added to app-center (branch also
  merged with main), firmware-updater, prompting-client,
  ubuntu-desktop-init, factory-reset-tools; comments posted on all 5
  PRs. udp-bootstrap skipped (classic confinement).
- 11-09 CI triage: firmware-updater integration failure = runner image
  regression (main rerun fails identically; /run/user/0/bus missing
  under sudo) - documented on PR #445, awaiting maintainer preference.
  udp-bootstrap Snap job = ubuntu-22.04 runner LXD regression ->
  switched workflow to ubuntu-24.04, green.
- 11-13 ogres review on #445: add gsettings to firmware-notifier
  plugs. ANALYZED FIRST: notifier is pure-Dart (dbus +
  desktop_notifications only), no direct GSettings reads, no project
  gschema - not strictly needed today. ADDED anyway: core24 gnome
  extension auto-granted gsettings to every app, so the rebase was
  silently narrowing the notifier's confinement - parity beats
  minimal-plugs during a base rebase; noted the nuance in the PR
  reply. PR branch had been refreshed by maintainer (merge of main
  b366bbe: CI fixes + Weblate) - rebased on top, signed b985877,
  pushed, replied (issuecomment-6853151202). Plugs change only -
  metadata yaml-validated; no local rebuild (canonical CI builds it).
- 11-10 udp-bootstrap #1613 dbungert review: requested changes -
  revert subiquity-check normalization (python-version sync is the
  point of the check; coordinate with ogayot whose subiquity PR #2473
  does the core26/python3.14 port). Tried gitlink->ogayot branch
  (fails: check's git cat-file resolves inside THIS repo, PR commits
  unreachable). Reverted to stock check + recipe keeps python3.14;
  sequencing = #2473 merges -> bump packages/subiquity_client gitlink
  to merged main (one-liner, like the existing "chore: bump
  source-commit" commits) -> check passes like-for-like. Subiquity
  Check green again; asked ogayot for ETA on the PR thread.
- 11-10 RESOLVED: dbungert took over subiquity #2473 and MERGED it
  (subiquity main e56ad68d). Branch updated: nested gitlink
  packages/subiquity_client/subiquity -> e56ad68d; curtin pin
  93c36fb6 (matches subiquity); source-commit re-pinned to a tree
  combining main's flutter scaffolding + this branch's core26 snap
  recipe + the bumped gitlink (first attempt pinned a snap-branch-
  only tree and broke the flutter part on missing .fvmrc - fixed).
  ALL CI GREEN on #1613 (snap 21m + subiquity-check + labeler).
- 11-10 automated PR-reviewer comments on snapcraft #6555 (2: missing
  core26 external-SDK test + stale expanded docs example) and #6556
  (1 high: prime escape). Dispositions: 6556 escape CONFIRMED on the
  intermediate revision (reproduced deleting an outside-prime file)
  and FIXED in current head (canonical containment + same-dir targets
  + strict family + dir-collision guard + executable scriptlet
  tests); replied with the repro. 6555: official-SDK gating + both
  core26 fixtures added (replied); stale expanded docs example
  acknowledged - will update after both snapcraft PRs land (avoid
  double churn).
- 11-11 aleasto review on #6555: the SDK file list should never be a
  cleanup source - "just replace it" with the content snap. Applied
  (sdk -> content as the first source) + kept a guard: custom SDK
  names derive a nonexistent content snap (content = sdk[:-4]) and a
  missing build-snap fails the build, so those setups skip the
  content-snap dedup instead. Both paths covered by tests
  (official-SDK-pinned + custom-SDK), moved from #6556 into #6555
  where they belong. #6555 rebuilt from upstream gnome.py (an earlier
  amend had leaked #6556's scriptlet rework into it); #6556 rebased
  to scriptlet-rework-only on top. Both signed, 168/168 extensions
  tests green, force-pushed; replied to aleasto (r4537108481). CI
  pending.
- 11-12 aleasto REPLIED: NO custom-SDK guard - "assume that an SDK
  always has a matching content snap. Other places in the gnome
  extension already do so" (true: get_root_snippet sets the derived
  name as default-provider unconditionally). AGREED: the guard was
  actively wrong for legit forks (custom SDK + matching content snap
  would lose dedup against their own content snap). Guard + both
  guard fixtures dropped; diff = his literal one-liner + 2
  test-expectation lines in the existing core26 test. Heads
  d4c16dce0 / e4357b110 (stacked), signed, 22 + 166 tests green,
  force-pushed; replied (r4550373331) + follow-up on the
  automated-reviewer thread that had requested the fixtures
  (r4550374425).
- 11-16 snapd-desktop-integration#175 review round (aleasto,
  CHANGES_REQUESTED): (1) drop the source-built libnotify part -
  DONE, runtime resolves libnotify.so.4.0.0 from gnome-core26
  (verified via /proc/<pid>/maps of the live daemon), build uses
  archive libnotify-dev (26.04 renamed the package: libnotify4-dev ->
  libnotify-dev); commit 12b5b47 pushed, replied (r4591962179). (2)
  NO gsettings plug - he is right: sdi reads themes via GtkSettings ->
  settings portal. VERIFIED LIVE on the user's 26.04 desktop VM
  (GDM/gnome-shell, sdi sideloaded over store rev):
  gtk/icon/cursor/sound changes all flow through GtkSettings (journal
  "New theme: ..." lines); icon=Papirus -> "Missing theme snaps" +
  the install prompt SEEN LIVE by the user on VNC;
  gtk-common-themes-only themes -> "All available theme snaps
  installed", no prompt. Replied with results
  (issuecomment-6930202958). NOTE: hand-built Xvfb test session in
  the multipass VM failed on portal backend activation (UseIn=gnome
  + bus-activation env) - live desktop was the right env. User's VM
  left running OUR sideloaded sdi (x1) pending their choice to revert
  (snap revert snapd-desktop-integration).
- 11-16 CI on #175 failed after the push: snap job = store outage at
  setup ("unable to contact snap store", recurring); tests job = test
  1/6 TIMEOUT 270s in TEARDOWN only (all 5 assertions passed, daemon
  healthy; unitary-test.yaml builds its own snapd-glib and libnotify
  from source - does not read snapcraft.yaml, so the commit cannot
  affect it). Both reruns GREEN (tests 1m15s, snap 4m24s) -
  flake/outage confirmed, PR fully green.
- 11-16 sdi round 2 (aleasto, new thread): archive libnotify-dev
  build-package unnecessary - the GNOME SDK ships libnotify 0.8.8 dev
  files and the gnome extension prepends the SDK pkgconfig dirs to
  PKG_CONFIG_PATH for every part. VERIFIED empirically: dropped the
  build-package, rebuilt, meson resolved "libnotify found: YES 0.8.8"
  from the SDK path alone. Commit ba97608 pushed, replied
  (r4593000094), thread resolved. 26.04 archive note: the dev package
  is named libnotify-dev (not libnotify4-dev) if ever needed.
- 11-10 thunderbird#71: aleasto LGTM modulo inline comment -> comment
  removed, force-pushed. Replied to his #70 dedup comment with the
  audit findings + snapcraft PR/issue links.
- udp-bootstrap #1613: gitlink -> subiquity main e56ad68d (merged
  #2473 by dbungert), curtin 93c36fb6 aligned, source-commit
  re-pinned to a tree = main flutter scaffolding + core26 snap recipe
  + new gitlink (first re-pin used the snap-branch tree and broke
  flutter-git on missing .fvmrc). ALL CI GREEN.

NOTE: thunderbird is now tracked on GitHub (ubuntu/thunderbird); LP
repo is only a mirror - do not file LP MPs for it.

## Rebuilds after review feedback (2026-11-09), all from updated branches

- batch1 (DONE): gnome-calculator, gnome-characters,
  gnome-text-editor, evince, gnome-logs, gnome-clocks
- batch2 (DONE): gedit, eog, cheese, simple-scan, gnome-calendar,
  gnome-contacts (+ libgoa-1.0-dev fix - an earlier build only passed
  because the reused LXD container still had goa installed from the
  retired EDS parts)
- thunderbird (DONE): 160.0b5-1 built (250MB), installed, ldd clean,
  GUI renders (151KB screenshot)
- VM RESULTS (2026-11-09): all 11 GUI snaps render (sizes match
  pre-review builds); gsettings plugs connected on all 9 that declare
  it; snap sizes sane after cleanup-part drop (cheese even smaller -
  extension auto-cleanup working); gnome-calendar NOT GUI-tested
  (expected to abort until gnome-core26 ships the fixed desktop-launch
  - see MP 514119 reply + PR #45)

## Content snaps - no work needed (already exist)

- [x] mesa-2604: stable 26.0.3 (26.2.3 NovaLake in latest/edge -
  graphics team promotes at launch; our snaps must just require
  mesa-2604 >= 26.2.3)
- [x] gnome-core26: latest/stable (ubuntu/gnome-sdk branch
  gnome-core26)
- [x] gaming-graphics-core26 (kisak track, steam)
- [x] gtk-common-themes (base: bare - unchanged)

## Flagged for other teams

- [!] mesa-2604 26.2.3 stable promotion -> graphics team (at launch)
- [!] 26.04 image seed snap revisions bump -> livecd-rootfs / image
  team
- [!] NovaLake real-HW GPU validation -> enablement team
- [!] firefox (Mozilla-published) coordination -> we still do
  firefox-snap stable branch PR

## Notes

2026-11-04: list built from host inspection (26.04.1 LTS),
canonical/desktop team repo list (gh api
orgs/canonical/teams/desktop/repos), and
code.launchpad.net/~desktop-snappers (54 repos, 110 snap recipes;
dormant 2017-era games core18/22 excluded -
chess/mines/tali/sudoku/nibbles/etc). Selected scope:
all actively-published core24 snaps + firefox/thunderbird stable
branches.

## Independent maintainer review (post-implementation, 2026-11-04)

- VALID + FIXED: eog SVG renderer hardened (viewBox/abs-unit fallbacks,
  ceil rounding, bounds + cairo status checks); verified normal AND
  viewBox-only SVGs render. eog+gedit libpeas loader layouts rebound
  to the snap copies (gnome-core26 ships no libpeas); loaders verified
  reachable in-snap. thunderbird 26.04 sonames committed + arch-safe
  libcanberra layout. simple-scan aligned to deb's sane-airscan
  0.99.37 (not 0.99.38). 6 repos' committed .snap binaries removed;
  ALL repos squashed to one clean source commit each.
- INVESTIGATED, NOT A DEFECT (upstream design): "gsettings plug
  missing" - snapcraft commit c05aed0c1 deliberately dropped the
  gsettings plug from the core26 gnome extension. Empirically verified
  in VM: dconf writes PERSIST across processes without the plug (snapd
  confines $HOME/XDG_CONFIG_HOME to ~/snap/<app>/x2/.config). The plug
  only grants shared-user-dconf access, which upstream removed.
  Flagged to gnome-sdk team rather than re-adding plugs against
  upstream design.
- REAL BUGS FOUND INCIDENTALLY (filed as the gnome-sdk issues below):
  gnome-core26-sdk g-ir-scanner can't parse sdk's own glibc headers
  (blocks in-snap gir generation); gnome-core26 desktop-launch exports
  a stale LIBGWEATHER_LOCATIONS_PATH (libgweather-4/ ->
  gweather-locations/) which aborts gnome-calendar - worked around
  via snap-local wrapper.

Build/test evidence: per-snap screenshots saved alongside the working
copies (*-core26.png, plus eog-svg-test.png, eog-vb-test.png). Firefox
+ thunderbird builds were restarted with the final recipes (multi-hour
builds).

2026-11-05: GitHub PRs opened (from chris-bainbridge forks, all OPEN,
verified base branches):
- canonical/firmware-updater#445 (main)
- ubuntu/app-center#2280 (main)
- canonical/desktop-security-center#288 (main)
- canonical/prompting-client#399 (main)
- snapcore/snapd-desktop-integration#175 (main)
- canonical/snap-tpmctl#88 (main)
- canonical/authd#2188 (main; authd-google variant yaml only)
- canonical/ubuntu-desktop-provision#1615 (base
  snap/ubuntu-desktop-init/main, head core26-ubuntu-desktop-init)
- canonical/ubuntu-desktop-provision#1614 (base
  snap/factory-reset-tools/main, head core26-factory-reset-tools)
- canonical/ubuntu-desktop-provision#1613 (base
  snap/ubuntu-desktop-bootstrap/main, head
  core26-ubuntu-desktop-bootstrap)
- firefox-snap stable-branch PR pending its build+test

2026-11-05: gnome-sdk bugs filed (ubuntu/gnome-sdk):
- #385 g-ir-scanner vs glibc regex.h array-__restrict (scanner grammar
  gap; fix belongs in gobject-introspection, sdk can carry deb patch)
- #387 desktop-launch stale LIBGWEATHER_LOCATIONS_PATH
- #386 libpeas-1.x absent from gnome-core26 (python3 plugin loader
  porting)

2026-11-05: LP merge proposals BLOCKED: the local SSH key was not
registered with Launchpad (ssh git.launchpad.net whoami -> publickey
denied). Needed: register a key on launchpad.net + an LP username,
then push lp:~<you>/<repo>/core26-update for the 13 repos and propose
into their stable refs.

2026-11-05 UPDATE: RESOLVED - key registered; NOTE git.launchpad.net
SSH requires the LP username in the URL (ssh
chris-bainbridge@git.launchpad.net, not plain git.launchpad.net) and
only speaks git-upload-pack/receive-pack ("whoami" -> "Unsupported
service" = auth OK, no shell). All 13 core26-update branches PUSHED to
~chris-bainbridge/<project>/+git/core26-update (gnome-calendar under
project "desktop"; push-to-create auto-created each repo;
gnome-clocks needed one retry - LP flakiness).

2026-11-05 (final): LP proposals COMPLETE - all 13 correct, all "Needs
review". The 3 wrong-target proposals were rejected; gnome-characters
and simple-scan re-filed correctly. Merge IDs: gnome-calculator
514128, cheese 514115, eog 514116, evince 514117, gedit 514118,
gnome-calendar 514119, gnome-characters 514129, gnome-clocks 514122,
gnome-contacts 514123, gnome-logs 514124, gnome-text-editor 514130,
simple-scan 514131 (thunderbird 514127 SUPERSEDED: maintainer moved
review to GitHub - rebased onto beta, libcanberra fix split out,
commit comments dropped; see the thunderbird entry above /
ubuntu/thunderbird#69).

2026-11-05 (correction): firefox-snap #185 was rejected in favour of
#184 (nteodosio, cherry-picked into beta+stable) - and the rejection
was CORRECT. Investigation of #184's gpu-2404 leftovers led to a wrong
conclusion (mine): gnome-core26 ships NO mesa/GL at all (verified: no
libGL/libEGL/dri in the runtime); on core26 the [gnome] extension
ITSELF creates the gpu-2604 mountpoint and wires mesa-2604 (docs:
ubuntu.com/frame/docs/26/how-to/use-snap-graphics; empirical: cheese's
squashfs has gpu-2604 with no recipe reference). So #184's stale
gpu-2404 prime lines are inert dead code, and f274e0c ("Revert
workaround for LP: #2016358") was correct cleanup of them. All core26
apps get mesa-2604 >= 26.2.3 via the extension once mesa-2604 promotes
to stable; no firefox follow-up PR needed.
(NB: the reverted workaround was originally for LP#2016358 = running
firefox breaking when gnome-42-2204 refreshed mid-session
(mount-namespace propagation); that snapd bug is still In Progress, so
if "app broke after mesa-2604 refreshed while running" is ever
reported, that's the thread.)

NOTE: anonymous LP API served STALE landing_targets (empty) while
proposals existed - the +activereviews page is the ground truth, not
the API. Merge proposals still needed the web UI (no LP OAuth
configured): for each, visit

https://code.launchpad.net/~chris-bainbridge/<project>/+git/core26-update/+register-merge

target repo / ref:
- gnome-calculator -> ~desktop-snappers/gnome-calculator/+git/snap
  stable
- cheese -> ~desktop-snappers/cheese/+git/stable stable
- eog -> ~desktop-snappers/eog/+git/snap stable
- evince -> ~desktop-snappers/evince/+git/snap stable
- gedit -> ~desktop-snappers/gedit/+git/snap stable
- gnome-calendar -> ~desktop-snappers/desktop/+git/gnome-calendar
  stable
- gnome-characters ->
  ~desktop-snappers/gnome-characters/+git/snap stable
- gnome-clocks -> ~desktop-snappers/gnome-clocks/+git/snap stable
- gnome-contacts -> ~desktop-snappers/gnome-contacts/+git/stable
  stable
- gnome-logs -> ~desktop-snappers/gnome-logs/+git/snap stable
- gnome-text-editor ->
  ~desktop-snappers/gnome-text-editor/+git/gnome-text-editor stable
- simple-scan -> ~desktop-snappers/simple-scan/+git/simple-scan stable
- thunderbird -> ~desktop-snappers/thunderbird/+git/snap stable
