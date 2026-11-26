---
upstream: https://github.com/canonical/snapd/pull/17972
waiting_since: 2026-11-12
---
# Firefox snap fails to start after upgrade (core26 / glycin-loaders)

## Impact / Priority

Firefox (snap rev 9181, core26) aborts at startup — the browser is
dead on every launch after upgrading from the core24 revisions;
first launch happens before the gnome-core26 content plug is
connected, and once the mount namespace is poisoned it stays
broken until a discard/reboot. A user gets a non-starting browser.

Impact derived from the original note's described symptoms.

## Context

Started 2026-11-12, updated 2026-11-14. Detailed record:
`20261112-firefox-fails-after-upgrade-analysis.md`.

## TL;DR

Firefox snap 160 (rev 9181, core26) aborts at startup because
`/usr/libexec/glycin-loaders` is an empty mount. Root cause: snapd's
mount-namespace diff never re-makes bind entries whose *source*
resolves through a changed content mount, and a ns bootstrapped
while the content plug is disconnected records a bind of an empty
stub directory as "applied". Fixed symptom-level in PR

<https://github.com/canonical/snapd/pull/17972>

but after maintainer feedback (Zyga) the working conclusion is that
the real fix is architectural: **stop patching preserved namespaces
in place at all** ("no runtime updates, ever") — discard and
rebuild instead.

## The bug

- Symptom: `Gtk:ERROR:...ensure_surface_for_gicon... Could not spawn
  "/usr/libexec/glycin-loaders/2+/glycin-image-rs" ... No such file
  or directory (os error 2)` → `Bail out!` → firefox dead on every
  launch.
- Trigger: firefox 149/159 (core24) → 160 (core26) upgrade; first
  launch happens before the gnome-core26 content plug is connected
  (auto-connection delayed/missing on upgrade; content snaps not
  seeded on fresh installs). Also reproduces via provider refresh
  under a preserved namespace.
- Reported on the snapd forum (valentin.david, aleasto); same-family
  as LP#2016358 (see below).

## Related failure mode: LP#2016358 (running app vs. provider refresh)

The older report LP#2016358 ("Running firefox instance malfunctions
after refresh of gnome-42-2204 snap"), duplicate LP#2023344, is the
same family but a different trigger: a provider refreshes under an
*already running* app. The desktop interface puts the app in a
cloned per-user namespace; the refreshed content mounts are not
propagated into it, so
`/proc/<pid>/root/snap/firefox/<rev>/gnome-platform` goes empty for
the running process (new launches are fine). Journal signature:
LD_PRELOAD `bindtextdomain.so` preload failure, `libgtk-3.so.0`
missing, XPCOMGlueLoad error. That is a torn update into a derived
namespace, versus this note's missed update in the main-namespace
diff.

Discard-first fixes this as a corollary: the running app keeps its
coherent old-generation mounts instead of being half-updated, and
the next launch bootstraps the new generation.

- https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/2016358
- https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/2023344

Firefox-snap history worth keeping:

- `00059b6a` "Add workaround for LP: #2016358" primed the gpu
  mountpoint dirs.
- 2026-11-04: core26 landed (PR #184); `f274e0c` reverted the
  workaround with no explanation - the core26 gnome extension now
  creates the gpu-2604 mountpoint itself. That silently re-bets
  that the refresh-while-running failure no longer applies on
  core26; nobody has verified it.
- `09a9552` is the core26 move; PR #185 (ours) was closed.

Repro matrix (carried over from
`20261105-investigate-running-app-breakage-when-gnome-snap-updates.md`,
to run during prototype validation):

1. Launch Firefox from its .desktop (desktop interface = cloned
   namespace; `snap run` in a terminal may not reproduce).
2. Record `grep -E 'gnome-platform|gpu-2604' /proc/<pid>/mountinfo`.
3. With Firefox open, `snap refresh gnome-core26` and/or
   `mesa-2604` (use mesa-2604 latest/edge for a real content delta,
   or sideload a rebuilt provider).
4. Check for the failure signature and compare mountinfo with the
   baseline.
5. Variants: runtime provider vs gpu provider; firefox with the
   `00059b6a` workaround re-applied vs post-revert; core24 vs
   core26.

## Root cause (verified live on Ubuntu 26.04 VM, snapd 2.77.1)

1. gnome extension (core26) adds `layout:
   /usr/libexec/glycin-loaders: bind:
   $SNAP/gnome-platform/usr/libexec/glycin-loaders`; provider
   gnome-core26 has slot `read: ['/']` with the real loaders at
   `/usr/libexec/glycin-loaders/2+/`.
2. core26+ pack validation (snapd #16893, SNAPDENG-36626) REQUIRES
   layout source paths to exist in the consumer squashfs → firefox
   ships **empty stub dirs** at every layout source.
3. `snap run` bootstraps AND preserves the mount namespace BEFORE
   content / command-chain validation fails ("ensure slot is
   connected"). A launch with the plug disconnected binds the
   layout from the stub and records it as applied. No error
   anywhere.
4. `snap-update-ns` diffs profiles textually; after connecting the
   plug the layout entry text is identical current-vs-desired →
   the stub bind is never re-made → empty mount forever. Profile
   bookkeeping cannot express "this bind was made against the
   wrong backing".
5. Same missing dependency rule: provider refresh under a
   preserved ns pins layout binds to the old provider revision;
   disconnect pins the detached provider mount.
6. Workaround: `snap revert firefox` + `snap refresh firefox` (or
   snap-discard-ns, or reboot — `/run` is tmpfs). A fresh
   bootstrap is always correct (content mounts pass 2.2 before
   layout binds pass 3).

## What was done

- Deterministic repro + A/B verification in a VM copy (all
  scenarios listed in the analysis md; poisoned ns → connect →
  heal; provider refresh 33→35→33 unpins; healthy ns → zero
  churn; firefox launches).
- PR https://github.com/canonical/snapd/pull/17972 (branch
  `fix/layout-content-stale-binds`, fork chris-bainbridge/snapd,
  Jira SNAPDENG-31645): dependency rule (S/D) + dev/ino staleness
  check (P) in `neededChanges` (cmd/snap-update-ns/change.go);
  11 unit tests; spread test `tests/main/layout-content-reconnect`
  + fixtures.
- Discovered Zyga's 2024 tests (`change_tricky_test.go`) already
  documented this exact bug as known-broken (SNAPDENG-31645);
  updated to the fixed plans.
- Independent review found two real holes in the first patch
  (stacked-mount churn via writable-mimic tmpfs at the same mount
  point; source-below-own-destination) → guards added, suite
  green, VM re-verified.
- CI failures on the PR were a snap store outage on the runners
  (nothing related); retriggered via empty commit (head
  86858152c4).

## Zyga's review on PR #17972 (2026-11-12, verbatim)

> I can already tell without looking at all the details that this
> doesn't work and it's just more heuristic. We tried to model the
> full VFS ops and propagation and that was pre-AI and was a lot
> of complexity that ended up nowhere.
>
> I'll review this next week as I have a blacklog but I don't
> have high hopes as anything that works for one test case, fails
> horribly in other places.
>
> You can go extreme and just unmount and remount everything and,
> guess what, that causes regressions too. I honestly think the
> only case that works is no runtime updates, ever.

## Conclusion (discussion 2026-11-14): Zyga is almost certainly right

The fundamental issue: a running process holds (a) already-open
fds/mmaps — SAFE under namespace mutation, lazily detached mounts
keep them alive — and (b) **future path resolutions**, which
resolve against the namespace view *at open time*. A lazily
detached mount vanishes from path resolution immediately, so a
running app gets ENOENT for opens it makes *later* (exactly
LP#2016358: running firefox can no longer dlopen libgtk-3).
Derived namespaces (per-app clones) see mutations asymmetrically
(unmount propagates, replacement mount doesn't). No in-place
patching strategy — textual diff, dependency rules, stat probes,
or a full VFS model — can keep the future opens of arbitrarily
complex running processes coherent; the mutator cannot fence the
process's next open. Every patching approach covers some cases and
tears others (the unbounded tail both Zyga and our own review
cycle kept hitting).

Sound policies are therefore:

1. **Never touch the namespace of running processes** — they keep
   one coherent generation until exit (lazily pinned old world).
2. **New processes always get a fresh bootstrap** of the desired
   profile — which is always correct (verified).

⇒ **Discard-first**: interface connect/disconnect and provider
refresh must NOT patch the preserved ns in place
(`updateOrDiscard`'s update branch); discard it instead (the
`ApplyDelayedEffects` → `opportunisticDiscard` machinery already
exists) and let the next launch rebuild. Fixes this bug, the
provider-refresh pinning, and LP#2016358 as corollaries.

Downsides examined — all small and already covered by existing
machinery:

- Security fixes wait for app restart (restart prompting via RAA /
  snapd-desktop-integration already exists; strictly better than
  today's broken running apps; same trade as deb/lib upgrades on
  live systems).
- Old revisions stay pinned until exit — already true today via
  lazy detach; old-revision GC already copes with busy mounts.
- Refresh/remove with running apps is already blocked by RAA.
- Mixed generations across concurrently running apps: already the
  norm.
- Endure daemons pin the old runtime until restart: existing
  endure semantics.
- The one engineering gap — a missed discard when apps were
  running at trigger time — is solved exactly with a
  **generation counter** in `snap.<snap>.info` (daemon bumps it on
  desired-profile change; snap-confine compares at launch and
  discards+rebootstraps if stale). Integer comparison, not a
  heuristic; extends the existing `.info`/stale-base mechanism.

## Next steps / open items

- [x] Reply on PR #17972 (2026-11-12 21:09): quoted Zyga's "no
      runtime updates, ever" line and asked "Why not do that?
      Having a consistent namespace would eliminate this entire
      class of bugs." Zyga responded: "The swamp of this problem
      space welcomes you. Thank you for the PR. We've been in
      this area for several years without success that has no
      sharp edges." He will review properly next week. Still
      relevant from this step when the discard-first proposal is
      formalised: it aligns with Zyga's stated position AND with
      bboozzoo's #17353 feedback ("reuse existing logic to apply
      opportunistic discard if nothing is running"); the
      generation-counter answer to "why not do that" is the
      missing piece to present (what breaks without in-place
      updates: nothing — running apps keep a coherent old world,
      next launch bootstraps fresh; the counter just makes the
      rebuild happen reliably even if the idle-discard was
      missed).
- [ ] Verify nothing genuinely depends on in-place ns updates:
      map all `updateOrDiscard` callers
      (connect/disconnect/provider-refresh/restore); check
      `ApplyDelayedEffects` retry semantics when apps are
      running at trigger time; check git history for why
      "update when running" was chosen.
- [ ] Prototype discard-first (+ generation counter) on a
      scratch branch; validate in the VM against all recorded
      scenarios plus the LP#2016358 shape (running app during
      provider refresh).
- [x] Cross-reference LP#2016358 (+ dup LP#2023344) as
      related-but-distinct: same family (stale content mounts),
      different mechanism (propagation into the running app's
      cloned per-user ns vs. main-ns diff gap). Details and the
      running-app repro matrix folded in above;
      `20261105-investigate-running-app-breakage-when-gnome-snap-updates.md`
      closed as superseded.
- [ ] Watch CI on PR #17972 (first run failed on a snap store
      outage, retriggered; PR CI doesn't run Go unit tests or
      spread — those run on pilot/merge).
- [ ] Decide: redirect PR #17972 vs withdraw and re-file
      discard-first.
- [ ] Consider a forum reply on the original thread pointing to
      the analysis.

## Environment / artifacts

- The repro VM is a disposable Ubuntu 26.04 install (qcow2
  overlay), powered off; the distro snap-update-ns was restored
  on it afterwards and the fixed binary kept alongside.
- Repo: `~/git/snapd`, branch `fix/layout-content-stale-binds`,
  remote `fork` → chris-bainbridge/snapd.
- Build note: snap-update-ns must be built statically, matching
  upstream:
  `go build -ldflags='-extldflags=-static -linkmode=external'
  ./cmd/snap-update-ns` — the per-snap AppArmor profile denies
  mmap'ing ld.so, so dynamic builds die with "snap-update-ns
  killed by signal 11".
- PR body edits: `gh pr edit` fails on canonical/snapd (GraphQL
  classic-Projects deprecation) — use
  `gh api repos/canonical/snapd/pulls/17972 -X PATCH --input
  payload.json`.
- Key files: cmd/snap-update-ns/change.go (neededChanges),
  update.go (multi-pass), cmd/snap-confine/ns-support.c
  (stale-base detection), interfaces/mount/backend.go
  (updateOrDiscard / ApplyDelayedEffects / opportunisticDiscard),
  overlord/snapstate/handlers.go.
