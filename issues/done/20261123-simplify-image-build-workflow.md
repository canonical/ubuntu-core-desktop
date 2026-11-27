# One-command image build for external developers

## Impact / Priority

Medium. No end-user impact, but it is now the main onboarding blocker:
the project has external developers arriving (2026-11) and the
documented "build an image" path is 13 manual clone/build/copy steps
across 16 repositories, each with a different build command. The
developer welcome documentation is already drifting from reality, so a
newcomer cannot tell whether their failure is their setup or a stale
doc.

The problem:

Building an image requires 16 snaps from 16 repositories. They are
built in their own repos, by hand, with commands that differ per repo:

    core-base-desktop          ./tools/build-variant.sh desktop
    ubuntu-core-desktop-snapd  snapcraft pack --use-lxd   (needs 8.x)
    ubuntu-desktop-a11y        cd snap && snapcraft pack
    accountsservice-snap       ./build-github.sh
    provd-snap                 ./build-github.sh
    kf6-core26                 ./build.sh
    plasma-core-desktop        ./build-github.sh
    plasma-desktop-session     ./build-github.sh
    (the rest)                 snapcraft pack --use-lxd

The resulting *.snap files are then copied to stable names and passed
to ubuntu-core-desktop/build.sh, which is ~2100 lines and takes 13+
explicit --snap/--base-snap/--gadget-snap/--snapd-snap/
--kde-session-snap/--kde-plasma-snap arguments. A full set of builds
is hours of LXD churn; almost none of it is work the developer wants.

What already exists, and should be reused rather than reinvented:

- CI already does the "use prebuilt snaps" path. build-image.yaml and
  build-image-kde.yaml both `mkdir -p snaps`, download every input
  with `gh release download <tag> -R <repo> -p <asset> -O
  snaps/<name>`, then call build.sh with `--base-snap snaps/...`.
  That spec list (repo:asset:local-name) is exactly the component
  table this task needs - it just lives in YAML instead of a script.
- The repo's root .gitignore already has a bare `*.snap` rule, so a
  snaps/ cache needs no new ignore rules for the snaps themselves.
- A RAM-disk build-dir convention exists in the project's private
  tooling (a tmpfs build root, default /var/lib/ucd-ram, refusing to
  run unless it is tmpfs). It is not used here: `snapcraft pack`
  already builds in an LXD container, so there is no build output
  directory of ours to redirect.
- The snap component set is settled: 13 GNOME payload repos (one of
  them, core-base-desktop, supplies the base snap) + 3 KDE-only.

The plan:

1. snaps/ cache directory (tracked .gitkeep; contents gitignored).
   Holds one *.snap per component under its stable local name, e.g.
   snaps/core26-desktop-variant.snap, snaps/pc-desktop.snap. Same
   layout CI already uses, so the same build.sh command line works
   in both places.

2. local-sources/ override directory (tracked .gitkeep; everything
   else gitignored). A developer who wants to change one component
   clones it here:

       cd local-sources
       git clone https://github.com/canonical/accountsservice-snap

   Presence of the directory means "build this from source"; absence
   means "use the cached snap". No submodules: a submodule checkout
   would force every developer to pull all 16 source trees, which is
   the thing this task exists to avoid.

3. Two scripts, splitting "what to build" from "how to build it":

   build-snap.sh <component> - builds one component. Holds the
   component table (repo, release tag, asset, local name, desktops)
   and one build_<component>() function per snap. A component with no
   function is a plain `snapcraft pack`; the exceptions are explicit
   and named (core-base-desktop needs build-variant.sh, four repos
   need build-github.sh because their base name is rejected by
   snapcraft's schema, kf6-core26 has its own build.sh, a11y builds
   from snap/). Also --list, --table and --force.

   build-snaps.sh [--desktop gnome|kde] / build-snaps.sh sync -
   orchestration only, no snapcraft knowledge. For each component:
   build it with build-snap.sh if local-sources/<name> exists,
   otherwise use the cached snap, downloading it if missing. `sync`
   is the only path that refreshes the cache.

   The tag is uniform: every component, including the base, publishes
   to desktop-26-latest from its repo's desktop/26 branch. (Until
   2026-11-23 the base used desktop-26-thin-latest, a name left over
   from the 2026-11-09 branch rename; that is now gone.)

   Behaviour, in order, for each component:

     a. If local-sources/<source-dir> exists: build it, but only if
        something changed (see state tracking below). Copy the
        produced snap to snaps/<local-name>, then `snapcraft clean`
        so the next build starts clean and nothing is left holding
        disk/RAM. The clean runs on failure too, via an EXIT trap.

     b. Otherwise: ensure snaps/<local-name> exists. If it does, do
        nothing - no network, no gh call, no "is there a new
        upstream?" check on every build (those rolling releases
        change on every green CI run; silently picking up new ones
        makes local builds non-reproducible and slow).

     c. `build-snaps.sh sync` (explicit, opt-in) re-downloads every
        non-overridden component. That is the only path that
        refreshes the cache. Consider also `sync <name>...` for a
        single component.

4. build.sh integration. build.sh calls build-snaps.sh first, then
   defaults each snap path to snaps/<name> when the flag is not
   given, so the developer types:

       ./build.sh --desktop gnome --model-account-key ci/account-key.assert \
                  --model ci/ubuntu-core-desktop-26-amd64-dangerous.model

   Existing explicit flags keep working (CI and hand-built snaps).
   Later, once this is trusted, move the repo:asset:local-name spec
   list out of the two workflow YAMLs and have CI call
   `build-snaps.sh sync` so there is exactly one copy of the table.

State tracking (how "only rebuild what changed" works):

Per component, keep a stamp file outside the source tree (e.g.
build/.build-state/<source-dir>) recording the last built git HEAD
plus a hash of the working-tree state. Rebuild when either differs.

Deliberately do NOT write the stamp inside local-sources/<repo>: that
is the developer's own clone, and a stray untracked file there breaks
`git status` and `snapcraft clean` habits.

For a dirty tree, hash the diff (`git diff HEAD` plus the list of
untracked files) rather than forcing a rebuild on every invocation.
Rebuilding a clean-tree base snap costs 15-30 minutes, so
"dirty means always rebuild" is too blunt for iterating on one
component; the diff hash gives the same safety with incremental
behaviour.

Note the snap must be rebuilt when the component's *recipe* changes,
which HEAD covers, and when the pinned upstream version changes, which
for the repackaging snaps is usually a stage-packages version bump -
also in HEAD. Uncommitted changes are the only case the diff hash is
needed for.

RAM-disk builds: not needed. `snapcraft pack` already defaults to an
LXD build container, so there is no per-build output directory to
redirect and no --destructive-mode fallback to maintain. The only
housekeeping is the `snapcraft clean` after each build.

Rejected / deferred alternatives (recorded so this does not get
re-litigated):

- Writing a custom build tool: no off-the-shelf tool does this
  hybrid, but the logic is a few hundred lines of bash around
  `snapcraft pack`; a new tool would be more to maintain, not less.
- Git submodules for the component repos: forces every developer to
  clone all 16 source trees to get a working image.
- Collapsing the 10 "repackaging" snaps into one monorepo (or into
  ubuntu-core-desktop): technically fine - GitHub Actions has no
  1:1 repo/snap restriction, only Launchpad does, and a
  changed-since-last-build loop over a snaps/ tree is trivial. The
  real cost is losing per-component git tags in favour of
  system-level versioning. Worth doing eventually; not a prerequisite
  for onboarding, and orthogonal to this plan (the component table
  would just point at subdirectories instead of repos).

Open questions:

- ubuntu-desktop-a11y was added to CI on 2026-11-10 and is missing
  from the developer doc's clone list (and from docs/building.md).
  The component table makes this class of drift impossible, but the
  docs need the same fix.
- ubuntu-desktop-provision and the three KDE repos live under
  chris-bainbridge/, not canonical/. Fine for now; the table records
  it explicitly. See
  `20261103-land-ubuntu-desktop-provision-off-the-personal-fork.md`.
- --snap flag duplication: plasma-core-desktop.snap is passed twice
  to build.sh (as --snap and --kde-plasma-snap). The defaults
  mechanism must not double-add it.

Out of scope (separate task):

Importing the project's private notes library into
ubuntu-core-desktop/docs/ as .md with local-environment references
stripped, plus an AGENTS.md that points at docs/README.md as a router.
Related only in that the same docs are the thing telling a new
developer how to build; that work should land after this so it can
document the new flow.

Status: COMPLETE 2026-11-25. The build flow, the docs and the
developer guide are done; what remains is unrelated follow-up, listed
under "Open, optional" below.

## Done (2026-11-24): cross-snap skew, and the missing CI gate

The published kde-latest image had been unusable since 2026-11-21: on
boot, SDDM authenticated the autologin user and then kwin_wayland
segfaulted in a loop (11 restarts) and fell back to the greeter.

Cause: kf6-core26 floats on Neon's release/resolute suite, which moved
independently. Its 2026-11-21 rebuild picked up Qt 6.12.0 while the
Plasma snaps still staged a kwin built against 6.11. Both published
green. Every version manifest and dependency constraint looked
consistent (kwin's `qt6-base (>= 6.11.1)` is satisfied by 6.12.0), so
nothing short of booting the image could see it. Local builds were
unaffected only because they predated the Qt roll.

Fixes:

- rebuilt kf6-core26, plasma-core-desktop and plasma-desktop-session
  against the healed archive and verified an image from them boots to
  Plasma with autologin and zero kwin crashes; the published
  desktop-26-latest assets now carry that set.
- build-image-kde.yaml and build-image.yaml gained a boot gate: a
  throwaway image with a gate account is built, booted headless (no
  GPU needed - virtio-vga without virgl, compositor on llvmpipe) and
  must reach plasmashell/gnome-shell on seat0 before the publish step.
  KVM when /dev/kvm is writable, TCG otherwise. It caught the broken
  asset set on its first run.

  Known flakiness: RESOLVED 2026-11-24. The gate was failing on what
  looked like "GDM never starts": instrumented runs showed
  snapd.seeded 'activating' for the whole window, with gdm queued
  behind it. The stuck task is "Setup snap ubuntu-desktop-session
  security profiles" - snapd runs apparmor_parser -j1 over ~80
  profiles, and on some hosted runners that takes >20 min (the same
  image seeds in ~90s locally, and reproducing under TCG shows the
  parser itself churning rather than hung). Not an image bug and not
  fixable from here.
  Fix: the gate now cold-boots and waits for snapd.seeded explicitly
  (30 min budget, printing the last seeding tasks on timeout), then
  reboots warm and asserts the session (8 min, one retry). Typical gate
  time is now ~5 min (seeding ~3 min + session ~80s). It also builds
  the gate image with cache=unsafe and runs before the publishable
  image, so only one 20G image exists at a time.

  Update 2026-11-27: the next two 30-minute failures were a different
  failure mode - the seed change errored ~3 min in, snapd parked a
  retry change in Wait ("resume after reboot"), and the gate watched
  that park for the rest of its budget with no apparmor_parser running.
  The gate now detects the park, dumps the evidence, and reboots once
  to let snapd resume (commit 47d16d5); details in
  `20261127-seed-change-errors-then-parks-waiting-for-reboot.md`.
- kf6-core26 dispatches build-snap on the two Plasma repos after
  publishing (needs a fine-grained PAT secret REBUILD_TOKEN; warns and
  skips without it), and all three KDE repos now rebuild daily.
  Decision 2026-11-24: leave REBUILD_TOKEN unset for now - the daily
  schedules (03:17/03:37 UTC) converge the set within a day, and the
  only token available is an account-wide OAuth one, which is too broad
  to put in a repo secret. Set it when a scoped PAT exists.

Docs and developer onboarding (2026-11-24):

- The developer welcome documentation rewritten around the new
  workflow: ./build.sh with three arguments gets an image from the
  published snaps; local-sources/ is only for components you modify.
  No more 13 manual clone/build/copy steps.
- docs reviewed against the new model: models.md describes how snaps
  reach the image (cache, override, or explicit flag); building.md and
  kde.md say which branch a local clone must be on; README no longer
  claims the image is only "tested through the welcome screen".
- build-snap.sh records the branch CI builds each component from and
  warns when a local-sources clone is on a different one
  (ubuntu-desktop-provision defaults to main while CI builds
  desktop/26 - a silent footgun before this).

Done (2026-11-23):

Build flow:

- snaps/ and local-sources/ added (tracked .gitkeep/.gitignore; the
  cache, build state and any clone are gitignored). local-sources/
  README.md explains the override workflow.
- build-snap.sh builds one component (table + build_<component>()
  functions + EXIT-trap `snapcraft clean`, including after a failed
  build), tracks state in snaps/.build-state/ and copies the result
  to snaps/<local-name>. --list/--table/--force.
- build-snaps.sh orchestrates: build what has a local source,
  download the rest, and `sync` to refresh. `sync` revalidates against
  the sha256 digest the GitHub API reports for each asset and downloads
  only what moved (never on an ordinary build), with `--force` to
  re-download everything. No snapcraft knowledge.
- build.sh calls build-snaps.sh and fills in every snap path that was
  not passed; --snaps-dir and --no-build-snaps added. CI keeps working
  unchanged (it passes every path itself).
- Verified: full KDE image built with only --desktop, --model and
  --model-account-key; all 16 snaps downloaded via the table and
  reused on the second run; accountsservice-snap built from a clone,
  skipped when unchanged, rebuilt when an untracked file appeared, and
  its LXD instance cleaned up afterwards.
- docs/building.md, README.md and CONTRIBUTING.md updated.

Tag/branch prerequisite cleanup:

- core-base-desktop publishes to desktop-26-latest like every other
  repo (was desktop-26-thin-latest, a name left over from the
  2026-11-09 rename). The stale fat release and tag are deleted.
- .github/workflows/build-snap.yml removed from desktop/26-fat: the
  fat branch is history only and must never build again.
- Both image workflows, the arm64 boot gate on main, and
  docs/building.md now download the base from desktop-26-latest, and
  the stale "desktop/26-thin" prose is gone.

Open, optional (2026-11-25):

- REBUILD_TOKEN is unset in kf6-core26, so the cross-repo rebuild
  dispatch warns and skips; the daily schedules still converge the KDE
  snap set within a day. Set it when a repo-scoped PAT exists (the only
  token to hand is the account-wide gh OAuth token, which is too broad
  for a repo secret).
- arm64 images are not boot-gated: no KVM on arm64 runners, so a gate
  there would be a 10-60 min TCG boot per push. Deliberate.
- `20261125-apparmor-profile-setup-slow-single-threaded.md` covers
  the remaining first-boot slowness (per-snap task overhead dominates;
  copy and compile are ~13% of first boot).
