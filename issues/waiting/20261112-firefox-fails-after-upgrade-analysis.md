---
upstream: https://github.com/canonical/snapd/pull/17972
waiting_since: 2026-11-12
---
# Firefox 160 snap fails after upgrade — reproduction, root cause, fix design

## Impact / Priority

Firefox 160.0-1 (rev 9181, core26, gnome extension) aborts at
startup with a missing glycin-loader binary whenever its mount
namespace was bootstrapped before the gnome-core26 content plug
was connected — dead on every launch; and a provider refresh
under a running app strands the running process without its
content mounts. The running-app shape is LP#2016358.

Impact derived from the original note's described symptoms.

## Context

Reproduced and root-caused in a copy of an Ubuntu 26.04 (regular26)
VM (snapd 2.77.1+ubuntu26.04.2), firefox 149/159 (core24) →
firefox 160.0-1 rev 9181 (core26, gnome extension). A disposable
VM copy was used; the backing image was never touched.

## Symptom (identical to bug report)

    Gtk:ERROR:../src/gtk/gtkiconhelper.c:495:ensure_surface_for_gicon: assertion failed
      (error == NULL): Failed to load .../icons/Yaru/16x16/status/image-missing.png:
      Could not spawn the following command. ...
      "/usr/libexec/glycin-loaders/2+/glycin-image-rs" "--dbus-fd" "79"`:
      No such file or directory (os error 2)
    Bail out! Gtk:ERROR:...

## Deterministic reproduction

1. firefox 9181 + gnome-core26 connected, ns discarded, launch →
   works (control).
2. `snap disconnect firefox:gnome-core26` +
   `/usr/lib/snapd/snap-discard-ns firefox`, launch firefox →
   fails with `Content snap command-chain for
   /snap/firefox/9181/gnome-platform/command-chain/desktop-launch
   not found: ensure slot is connected` — **after** snapd has
   bootstrapped+preserved the ns.
3. That ns contains the layout bind for
   `/usr/libexec/glycin-loaders` resolved WITHOUT the content
   mount: bound from firefox's own squashfs (empty stub dirs
   shipped by snapcraft per merged snapd PRs #16828/#16893,
   SNAPDENG-36626).
4. `snap connect firefox:gnome-core26` (no relaunch) → content
   mount added to ns, layout bind NOT redone (fstab text
   identical current-vs-desired) → empty mount persists → crash
   on every launch.
5. `snap revert firefox` + `snap refresh firefox` or plain
   `snap-discard-ns firefox` → fresh bootstrap (content pass 2.2
   before layouts pass 3) → fixed.

## Root cause chain

1. gnome extension (core26): `layout:
   /usr/libexec/glycin-loaders: bind:
   $SNAP/gnome-platform/usr/libexec/glycin-loaders`; provider
   gnome-core26 slot `read: ['/']`, loaders at
   `/usr/libexec/glycin-loaders/2+/`.
2. snapd pack validation (merged #16828/#16893, core26+) REQUIRES
   layout source paths under $SNAP to exist → firefox squashfs
   ships EMPTY STUB dirs.
3. `snap run` bootstraps+preserves the ns BEFORE content/
   command-chain validation; with the plug disconnected the
   layout bind silently resolves to the stub.
4. Current profile records the layout as applied; later connect
   changes only the content entry text → layout never re-bound.
   The profile cannot express "this bind was made against the
   wrong backing mount".
5. Base-snap changes DO invalidate the ns
   (`sc_inspect_and_maybe_discard_stale_ns`,
   "stale-base-invalidation"); content-mount-backed layout binds
   have no equivalent detection. This is saviq's "venerable
   layouts get broken on base upgrade" bug class.

## Verified experiments (snapd 2.77.1, unpatched)

- **Healthy ns**: destination and source stat identical (dev 709,
  ino 12981).
- **Poisoned ns after connect (no relaunch)**: ns gained the
  content mount (`/snap/gnome-core26/33`) via daemon-side
  updateOrDiscard at *connect* time; layout bind still backed by
  firefox stub (dev 707, ino 16). Destination vs source dev/ino:
  **707:16 vs 709:12981 — mismatch**.
- **Provider refresh 33→35 while firefox runs** (candidate
  channel): content mount remounted to rev 35 (source path now
  dev 712, ino 12959) but layout bind **pinned to rev 33
  backing** (dev 709, ino 12981) — same missing dependency rule;
  consumers running during a provider refresh keep serving the
  old runtime's layouts indefinitely (previously unreported
  manifestation).

## Upstream survey (2026-11-12)

- No fix landed: no commits to cmd/snap-update-ns/update.go|
  change.go since Sept 2026; no issues/PRs mentioning glycin or
  this scenario.
- Open PR #17353 (Mohit-Chachada): ns-support.c check comparing
  (dev,ino) of layout sources under /var/snap/<instance>/ vs
  destination; discard on mismatch. Maintainer feedback: bboozzoo
  prefers NOT extending snap-confine; zyga wants snapd/daemon-side
  handling.
- Merged #16906 (Apr 2026): snap-update-ns multi-pass design
  (content mounts pass 2.2, layouts pass 3).
- Merged #16828/#16893 (Apr/May 2026, SNAPDENG-36626): stub layout
  paths are required by pack validation for core26+ — a fix must
  tolerate them.

## Agreed fix design (independent upstream-maintainer review)

**Primary — dependency rule in snap-update-ns's diff**
(`neededChanges`, cmd/snap-update-ns/change.go): a bind/rbind
entry whose source (`Name`) lies inside the mount point (`Dir`,
proper path-prefix) of another entry that is unmounted, newly
mounted, or whose source revision changed must itself be unmounted
and remounted (transitive, so chains work). All in the existing
multi-pass machinery (unmounts with x-snapd.detach in pass 1,
content in 2.2, layouts in 3). Fires at `snap connect` time
(backend Setup → updateOrDiscard), no relaunch needed. Also fixes
provider-refresh pinning and disconnect pinning.

**Hardening — dev/ino staleness check for already-poisoned
systems**: in snap-update-ns (Go, not C), for kept bind/rbind
entries whose source depends on another entry's mount point: stat
source path vs destination inside the joined ns; st_dev/st_ino
mismatch → treat as changed → remount. Injectable for tests,
cheap (few stats per snap), non-fatal on stat errors (keep +
debug log). Heals poisoned systems on first launch after snapd
upgrade; no migration needed.

Rejected: (A) don't-preserve-ns-on-failed-validation — only
closes one entry path; (B) daemon drops/flags layout entries
under disconnected content targets — special-cases content,
misses revision changes, no healing; (C) x-snapd.layout-no-
content marker — symptom not dependency, format change; (D) hard
error on stub binds — breaks legit disconnected launches, stubs
are required by #16893; (E) #17353 as-is — C-side, reactive,
/var/snap-only, fails while snap running (its dev/ino idea kept
as the Go hardening); (F) no stubs — not viable.

Test plan: unit tests on neededChanges (add/remove/
revision-change → layout remade; chains; must-keep boundary
cases: sibling paths, symlink layouts, x-snapd.kind=file,
rootfs, overname, components; synthetic-mimic regression),
mocked-stat tests, spread tests layout-content-reconnect +
recovery (nsenter-recreated poison self-heals).

## Implementation status

- [x] Bug reproduced + root-caused + experiments verified
      (above)
- [x] Fix design agreed (dependency rule + dev/ino hardening
      in snap-update-ns)
- [x] Implemented in ~/git/snapd (cmd/snap-update-ns/change.go
      + tests)
- [x] Existing 2024 tests in change_tricky_test.go documented
      this exact bug as known-broken behaviour, tracked as
      SNAPDENG-31645 ("the mount entry propagated to the layout
      during initial construction sticks around and is not
      updated. This is a bug."). Updated to assert the fixed
      plan.
- [x] Unit tests: 9 new (dependency rule + hardening + fail-
      safe default), full cmd/snap-update-ns suite green;
      osutil + interfaces/mount green
- [x] VM verification with patched /usr/lib/snapd/snap-update-ns:
  - A: already-poisoned/revision-pinned ns (dest 709:12981 vs
    src 712:12959) healed by snap-update-ns run → dest == src,
    layout bound from new revision
  - B: poison (stub 707:16) → `snap connect` heals at connect
    time, no relaunch → firefox launches
  - C: healthy ns → zero re-make churn, dev/ino stay matched
  - D: provider refresh 35→33 while firefox runs → layout
    re-made to new revision (previously pinned to old)
  - E: **recovery semantics correction** — plain `snap run`
    does NOT re-run the system diff on ns reuse (snap-confine
    only does user mounts; .info only carries base-snap-name
    for stale-base detection). System updates are
    daemon-driven (updateOrDiscard at
    connect/disconnect/refresh). Recovery for already-poisoned
    systems therefore happens at the next daemon-driven
    update of the snap or its providers (connect heals
    immediately — Scenario B) or at reboot (/run is tmpfs;
    preserved ns does not survive). Acceptable: poison can
    only arise together with a later connect, which itself
    heals.
- [x] Spread test added: tests/main/layout-content-reconnect +
      fixtures in tests/lib/snaps/ (consumer with stub layout
      source, provider v1/v2). Flow verified manually in the
      VM: poison → connect → canary visible, provider refresh
      follows new revision, disconnect/reconnect round trip.
      A/B regression check: original binary keeps the poison
      ("no canary" after connect), fixed binary heals ("hello
      from provider V2").
- [x] Deployed-binary caveat found during testing:
      snap-update-ns must be built statically
      (-ldflags='-extldflags=-static -linkmode=external'), the
      per-snap AppArmor profile denies mmap'ing ld.so for
      dynamically linked builds (SIGSEGV "snap-update-ns
      killed by signal 11").
- [x] Upstream PR: https://github.com/canonical/snapd/pull/17972
      (branch fix/layout-content-stale-binds, based on current
      master, DCO signed, Jira SNAPDENG-31645 referenced)
- The VM copy is retained as scratch (firefox healthy on 9181;
  distro snap-update-ns restored, fixed binary at
  /root/snap-update-ns-fixed, orig at /root/snap-update-ns.orig)

## Independent maintainer review (post-PR) — findings and dispositions

- F1 (major, VALID): rule P (stat check) false-positives when
  another mount is stacked at the bind's destination (writable
  mimic tmpfs mounted at the same mount point per utils.go
  planWritableMimic "Mount tmpfs over the original directory"):
  stat(Dir) reports the top-most mount → permanent re-make
  churn, cascading via rule D. Fixed: stat check skipped when
  the entry's Dir is shared by more than one current entry
  (stackedDirs). Reachable via nested layouts (layout A target
  containing layout B target that needs a mimic).
- F2 (minor, VALID, subsumed by F1 fix): same mechanism for a
  mimic covering one of the layout's own children.
- F3 (minor, VALID, latent): desktop interface document portal
  bind has source strictly below its own destination
  ($XDG_RUNTIME_DIR/doc/by-app/snap.X ← $XDG_RUNTIME_DIR/doc,
  desktop.go:817); stat(src) resolves through the destination →
  meaningless comparison. Latent only (user current profiles are
  never persisted today), fixed with the strictlyBelow(name,
  e.Dir) guard.
- F4 (minor, NOT A BUG): stat check runs in the same fixpoint
  pass as rules S/D — outcome is order-independent because the
  pass is monotone (only removes from reuse). Ordering comment
  added.
- F5 (nit): map iteration nondeterminism only affects which
  sourceParentDir triggers the (single) stat call and debug
  logs. No action.
- Verified-not-problems (agreed with reviewer): termination,
  skipDir interaction, synthetic needed-by coherence, symlink
  layouts (Name "none" can never match), fstab octal escaping
  (MountEntry holds unescaped values), dev/ino across
  overlayfs/btrfs/NFS (bind exposes the same inode), dangling
  source handled by rule S, downgrade safety (no profile format
  change).

Post-review verification (VM, revised build): healthy ns 0
churn; poison → connect heals (707:16 stub → 709:12981
matched); spread-test flow green (after-connect V1,
provider-refresh V2); firefox launches. Commit amended →
d32168c68f, force-pushed; PR body updated.

## CI status (post-PR)

- First CI run (2026-11-12 ~19:47 UTC): 7 failing checks, **all
  snap store / network outages on the runners, none related to
  the change**:
  - shell-complexity: `cannot install "shellmetrics": cannot
    query the store`
  - package-builds / Create go vendor: `unable to contact snap
    store`
  - snap-builds (all 5 variants): `snap install lxd` → `unable
    to contact snap store`
  - macos-quick: fetching snap "hello" → `connection reset by
    peer` to api.snapcraft.io
  - Green checks: unit-tests (C gcc/clang), unit-tests-python,
    unit-tests-fuzzing, branch-static-checks, cla-check
  - `gh run rerun` refused ("workflow file may be broken" —
    API-side); retriggered with an empty commit → final branch
    head 86858152c4
- Note: PR-triggered CI does not run the Go unit tests or spread
  (those run on pilot/merge); local coverage stands in (full
  cmd/snap-update-ns suite, osutil, interfaces/mount, VM
  verification).
- PR body edits: `gh pr edit` fails on this repo (GraphQL
  classic-Projects deprecation error) — use
  `gh api repos/canonical/snapd/pulls/17972 -X PATCH --input
  payload.json` instead. Summary now links SNAPDENG-31645
  (https://warthogs.atlassian.net/browse/SNAPDENG-31645).

## Final state

- Upstream PR: https://github.com/canonical/snapd/pull/17972
  - Branch: fix/layout-content-stale-binds (fork
    chris-bainbridge/snapd)
  - Head: 86858152c4 (fix commit d32168c68f amended with review
    guards + CI retrigger)
- VM: powered off; the qcow2 overlay copy is retained as scratch
  (backing image untouched; contains all experiment state; the
  distro snap-update-ns restored, fixed binary at
  /root/snap-update-ns-fixed)
