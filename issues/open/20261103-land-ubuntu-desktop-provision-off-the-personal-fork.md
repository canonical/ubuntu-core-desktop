# Land ubuntu-desktop-provision work off the personal fork

## Impact / Priority

Priority: Medium - nothing is broken today, but a single personal
account (chris-bainbridge) is a single point of failure and a trust
weakness for artifacts consumed by canonical repo CI: the published
GNOME image workflow downloads the ubuntu-desktop-init snap from
chris-bainbridge/ubuntu-desktop-provision's release (build-image.yaml
drops the fork's branch naming; the workflow consumes its
desktop-26-latest release asset at lines 40/55). If that personal repo
or account becomes unavailable, every subsequent image build fails.
Same trust concern applies to the planned store publishing of
ubuntu-desktop-init from the fork
(`20261103-publish-core-desktop-snaps-to-the-store.md`). No
end-user-visible impact yet.

## Context

The fork was a deliberate stopgap ("origin is actually my fork. This is
fine for now. Do not try to push to upstream" -
`20261008-gnome-github-ci.md`). "Now" has arrived: the fork's output is
consumed by canonical/ubuntu-core-desktop CI and is in the
store-publish plan.

## Fork state (verified 2026-11-03)

- origin = chris-bainbridge/ubuntu-desktop-provision.
- Branch desktop/26 = upstream main + 11 local commits (CI workflow +
  snapcraft fixes: extension source path, gnome-sdk source path, core24
  platform-snap avoidance, skip-unsupported-init-hook, drop dangling
  source-commit pin). STALE BASE: upstream main is 74 commits ahead of
  the fork branch's merge-base (662bb0782, ubuntu/26.10 translations
  backport #1568) - several of the 11 may be obsolete upstream already.
- Two open upstream PRs from this account:
  canonical/ubuntu-desktop-provision#1583 (slideshow overflow) and
  #1584 (done-page buttons on short displays) - branches
  fix/slideshow-overflow, fix/done-page-button-overflow.
- Consumers to update once landed: build-image.yaml:40,55 (fork release
  asset), the store-publish work item's inventory row, and the dev
  build's local snap inputs (they resolve ubuntu-desktop-init from the
  repo's build output).

## Work

1. Triage the 11 fork-only commits against upstream main (74 commits
   ahead): for each, decide (a) already fixed upstream - drop,
   (b) still needed - rework onto current main and PR upstream,
   (c) fork-only plumbing (the desktop-26-latest release workflow) -
   replace rather than port. Expect rebase conflicts; the branch is a
   year-old base.
2. Investigate the store side before building anything: who publishes
   ubuntu-desktop-init latest/candidate today, and from where?
   ANSWERED 2026-11-03 (store lookup): published by seb128 - a PERSONAL
   account (account-id tBdY...), not a verified Canonical publisher.
   So a store path exists, but it is personal-publisher AND unrelated
   to this fork's CI. The endgame is therefore: image workflow consumes
   a store snap published by the verified Canonical publisher from
   canonical/ubuntu-desktop-provision; that requires a publisher
   transfer/republish (tracked in
   `20261103-publish-core-desktop-snaps-to-the-store.md`'s
   PUBLISHER-TRUST note) plus finding/reusing whatever recipe seb128
   uses today. Once that lands, the fork's release-asset CI becomes
   unnecessary - check before porting it.
3. Decide the canonical hosting for whatever CI/release convention the
   image workflow keeps consuming in the interim: either land a branch
   + workflow on canonical/ubuntu-desktop-provision (needs upstream
   buy-in), or switch the image workflow to the store snap per step 2,
   or (last resort) move the fork under a canonical-controlled org.
4. Land the two open PRs (#1583, #1584) or close them if stale.
5. Update the consumers listed above and record the new provenance in
   the store-publish work item. Only after all consumers are off the
   fork: demote/archive it.
6. Also reconcile the branch naming: fork uses desktop/26; upstream
   convention for this repo is snap/<snap-name>/<series> (e.g.
   snap/ubuntu-desktop-init/26.04). Any canonical-side branch should
   follow that convention.

## Related

- `20261103-publish-core-desktop-snaps-to-the-store.md`
  (ubuntu-desktop-init row + recipe search)
- `20261008-gnome-github-ci.md`,
  `20261009-build-and-publish-gnome-dangerous.md` (where the fork
  dependency was created)
