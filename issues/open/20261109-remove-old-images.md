# Remove the stale ubuntu-core-desktop trees from cdimage.ubuntu.com

## Impact / Priority

Priority: Low. Nothing we still publish is lost or broken by these
trees: the current daily images live on GitHub Releases (dated
gnome-/kde- tags), not cdimage. A real user who finds

<https://cdimage.ubuntu.com/ubuntu-core-desktop/>

today downloads a 2025-10 / 2026-01 subiquity installer ISO whose
install path has been broken since livecd-rootfs 26.04.27 - a stale,
misleading entry point for the project, plus ~16G of dead hosting.
Cheap to fix, but blocked on a single external ask (cdimage admin), so
it can wait.

INVESTIGATION ONLY (2026-11-11) - no removal requested yet.

## What is actually there (verified 2026-11-11)

<https://cdimage.ubuntu.com/ubuntu-core-desktop/>

- 24/edge/: dated dirs 20251015, 20251016, 20251017 + current/ +
  pending/. Each dated dir: ubuntu-core-desktop-24-amd64.iso (~3.3G)
  plus .iso.zsync, .manifest, .list, SHA256SUMS(.gpg) and a 0-byte
  .OVERSIZED marker.
- 26/edge/: dated dirs 20260125, 20260126 + current/ + pending/ -
  same layout with ubuntu-core-desktop-26-amd64.iso.
- pending/ holds the newest build of each tree; current/ ("images
  that passed any automatic testing") is EMPTY in both - the ISOs
  never passed image testing, consistent with the broken installer.

Five ~3.3G ISOs total; nothing newer than 2026-01-26.

## What those images are

Context from `20261009-build-and-publish-gnome-dangerous.md`:

Subiquity INSTALLER ISOs built by Launchpad from livecd-rootfs
(PROJECT=ubuntu-core-installer SUBPROJECT=desktop) - a different
artifact AND a different pipeline from the current dangerous VM images
(pc.img via ubuntu-image + custom model, published as GitHub Releases).
The installer broke in livecd-rootfs 26.04.27 and builds stopped
2026-01-26 ("the installer still fails for unclear reasons",
livecd-rootfs commit 149a9921). Nothing current depends on these trees.

## Why removal is a cdimage-admin action, not a repo change

There is no self-service and no GitHub-side mechanism:
cdimage.ubuntu.com is Canonical infrastructure driven by the
ubuntu-cdimage orchestrator (product config + cron in
git.launchpad.net/ubuntu-cdimage, e.g. etc/crontab; published content
lives under /srv/cdimage.ubuntu.com/www/ on the cdimage host). Removal
is a server-side admin action. The product's cdimage config/cron entry
must be removed or disabled in the same pass so the tree cannot
regenerate. Note the cdimage machinery was described as "under
refactor" (chat below), so the config may live somewhere new - the
admin will know. The edge/ daily trees are not mirror-synced content
(mirrors carry releases/), so no mirror coordination should be needed;
let the admin confirm.

## How to request it, in order of practicality

1. Ask the cdimage-side contact directly: in the chat captured in
   `20261109-build-images-on-launchpad.md`, Utkarsh is the person who
   does cdimage publishing/management ("@utkarsh can do that").
2. Otherwise the ubuntu-cdimage team: Launchpad ~ubuntu-cdimage /
   ubuntu-cdimage@lists.ubuntu.com, or #ubuntu-release (Libera), who
   coordinate with the cdimage admins.
3. Canonical-internal fallback: an RT ticket to IS reaches the
   cdimage host admins (that is the route the Ubuntu Wiki
   EndOfLifeProcess uses for archiving); for a plain dead-tree
   removal the direct ask above is enough.

The ask: delete the whole /ubuntu-core-desktop/ tree (24/ and 26/),
and remove the ubuntu-core-desktop product from cdimage config/cron so
nothing regenerates it.

## When done

Append a resolution note (who actioned it, any config that was
changed) and move this file to `issues/done/`; add a line to
`20261109-build-images-on-launchpad.md`'s "cdimage presence" section
if the product config was deleted outright (it changes that issue's
"revisit later" picture).
