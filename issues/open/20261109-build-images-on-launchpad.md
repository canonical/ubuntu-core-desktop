# Build images on Launchpad instead of GitHub? (investigation: not now)

## Impact / Priority

Priority: Low / decision record. No user-facing impact today: the
GitHub pipeline is green and daily (dated gnome-/kde-/gnome-arm64-
releases on canonical/ubuntu-core-desktop). This note exists so a
future "should we move to Launchpad/cdimage?" discussion starts from
the recorded answer instead of re-deriving it. Revisit only if/when
the project ships official asserted images (see "Revisit when"
below).

Source:

<https://chat.canonical.com/canonical/pl/jqwdow4yt7ypx8xttsr5yta6oe>

(owner asking how cdimage images get published; verified against
`20261009-build-and-publish-gnome-dangerous.md` and the official
image-builds docs, 2026-11-11.)

## What the chat established

- Publishing to cdimage.ubuntu.com via GitHub CI "is not going to
  work ... this is more or less by policy": cdimage content is built
  on Launchpad, driven by Canonical's cdimage machinery, not by
  external CI.
- The recipe if we ever wanted it: autosync the GH repo to Launchpad;
  get an image config into livecd-rootfs to trigger a livefs build;
  hook it to a cdimage cron for daily builds. livecd-rootfs is the
  durable part ("the cdimage machinery is under refactor, but what's
  in livecd-rootfs is likely going to stay around"); see
  https://launchpad.net/livecd-rootfs and its README.local.

## How the Launchpad pipeline actually works

cron on the cdimage host -> ubuntu-cdimage orchestrator -> livefs
builds on Launchpad (live-build + livecd-rootfs config) -> debian-cd
assembles ISOs -> ubuntu-cdimage publishes into dated build-stamp dirs
and mirror-syncs. cron/config: git.launchpad.net/ubuntu-cdimage
(etc/crontab); build logs: ubuntu-archive-team.ubuntu.com/cd-build-logs.

Key point: this is how the OLD ubuntu-core-desktop images on cdimage
were built (see `20261109-remove-old-images.md`) - subiquity installer
ISOs from livecd-rootfs PROJECT=ubuntu-core-installer
SUBPROJECT=desktop. That pipeline broke in livecd-rootfs 26.04.27 and
died 2026-01-26 (commit 149a9921).

## Why this is NOT "our current image, moved to Launchpad"

The current pipeline (build-image.yaml) produces a different artifact
class: a VM pc.img built by ubuntu-image from a pre-signed grade:
dangerous model, sideloading ~7 locally-built UNASSERTED snaps pulled
from per-repo desktop-26-latest GitHub release assets. A livefs build
resolves everything from the Ubuntu archive + Snap Store and emits
livecd-rootfs/debian-cd installer ISOs. It cannot sideload our
unasserted local snaps at all, so "build the current image on
Launchpad" is not a port - it is a rewrite onto livecd-rootfs with a
different output, and the dangerous ingredients (unasserted snaps,
individual's registered test key) are exactly what cdimage policy does
not host.

## Verdict

Possible: yes, in principle (it existed before), but only with
Canonical cdimage-admin involvement for the livecd-rootfs image config,
the Launchpad livefs/product setup, and the cdimage cron - none of it
GitHub-side, all of it a parallel build system.
Desirable: not now. GitHub is working, matches the artifact we actually
ship (dangerous developer-preview VM images), and the cdimage trees
would misrepresent a dangerous image as official. This matches the
standing 2026-10-09 decision
(`20261009-build-and-publish-gnome-dangerous.md`: "cdimage publishing
requires Canonical cdimage admin access regardless; GitHub Releases is
the practical publish target for now").

## Revisit when

The prerequisites below are all gates of the store roadmap, not of this
note: when the snaps are store-published and asserted
(`20261103-publish-core-desktop-snaps-to-the-store.md`, incl. the
gadget-connections migration gate), the model is a store-resolved
official/signed one, and the project wants cdimage as its official
download home - THEN a livecd-rootfs image config + Launchpad livefs +
cdimage cron is the right, policy-compliant mechanism (and aligns with
the project principle of staying close to upstream Ubuntu Core
machinery). Until then: do nothing here.

## cdimage presence

The existing (dead) ubuntu-core-desktop product trees on cdimage are
tracked in `20261109-remove-old-images.md`; if that removal gets
actioned by deleting the product config outright, any future
Launchpad/cdimage move starts from a fresh product setup rather than a
resurrection.
