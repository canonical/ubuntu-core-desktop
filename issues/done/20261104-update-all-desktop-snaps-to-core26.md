# Update all desktop snaps from core24 to core26 (mesa-2604)

## Impact / Priority

No end-user impact statement in the original note; the driver is an
enablement request. Request from an enablement engineer: "Hello, We are
doing the Intel NovaLake enablement for 26.04. It requires mesa-2604
version >= 26.2.3 which is in the edge channel now. Currently, a lot of
snap applications for 26.04 are still based on core24, ex:
firmware-updater/App Center...etc. We need to update those application
to be based on core26 and relies on mesa-2604 26.2.3. The mesa-2604
26.2.3 will be in stable channel when the platform is launched. "
Impact derived from the original note's symptoms.

## Steps

1. Make a list of all of the desktop snaps that still rely on core24 /
   2404 content

2. Figure out How to update them all

3. Do it

Check out any repos you need locally.

## Resolution (2026-11-12)

All 25 snaps in scope were migrated, built, VM-tested and proposed
upstream. Per-snap detail and review adjudication: master tracker
`20261104-desktop-snaps-core26-migration-list.md` (all 25 entries
ticked; PR/MP status + CI notes at the bottom).

### What was done

- Inventory: 25 snaps - 12 LP ~desktop-snappers repos (merge
  proposals) + GitHub repos incl. the ubuntu-desktop-provision
  family and firefox/thunderbird.
- Every snap rebased onto core26 consuming the EXISTING 2604
  content snaps via extensions: [gnome] (gnome-core26 + mesa-2604);
  no 2404 content snap was forward-ported. One clean signed commit
  per repo on branch core26-update; working copies under a
  snaps-core26-update/{github,launchpad}/ tree.
- Built with snapcraft --use-lxd on the host; every snap
  screenshot-verified in the multipass 26.04 VM.
- 12 Launchpad merge proposals filed (514115-514131); branches
  updated with review-feedback commits; replies posted.
- GitHub PRs filed for all GitHub repos: thunderbird #69/#70
  MERGED (canonical repo is ubuntu/thunderbird; LP is a mirror),
  #71 open; firefox superseded by Mozilla's own #184 cherry-pick to
  stable - built and verified locally, nothing pending.
- Migration exposed upstream bugs, filed/fixed: gnome-sdk issues
  #385/#386/#387; sdi-command-chain PR #45 (stale
  LIBGWEATHER_LOCATIONS_PATH in gnome-core26 desktop-launch, makes
  gnome-calendar abort); snapcraft PRs #6555/#6556 (gnome extension
  cleanup now deduplicates against the content snap instead of the
  SDK; soname-symlink-safe scriptlet) and issue #6557 (craft-parts
  base-dedup gap).
- ubuntu-desktop-provision #1613 (ubuntu-desktop-bootstrap core26):
  all CI green, all commits SSH-signed, subiquity gitlink = ogayot's
  merged canonical/subiquity#2473 e56ad68d (core26 + python3.14).
  NOTE: no PR against canonical/subiquity was needed from us.
- CI triage: firmware-updater #445 failure = runner-image regression
  (main fails identically); snapcraft PR failures Nov 11-12 =
  GitHub-runner -> api.snapcraft.io outage (408s at `snap install`
  setup, unrelated PRs equally red), NOT code.
- snapcraft #6555 review round 2 (aleasto): custom-SDK guard dropped
  per his direction - an SDK is assumed to always have a matching
  content snap (the root snippet's default-provider already does);
  applied as his literal one-liner + 2 test-expectation lines.

### Not done / outstanding (gated on upstream, not on us)

- Reviews/merges pending: 12 LP MPs (reviewer aleasto), snapcraft
  #6555/#6556 (CI blocked by the store outage as of 11-12), sdi
  PR #45, firmware-updater #445, thunderbird #71, app-center #2280,
  desktop-security-center #288, prompting-client #399,
  snapd-desktop-integration #175, snap-tpmctl #88, authd #2188,
  ubuntu-desktop-provision #1614/#1615.
- gnome-calendar LP MP 514119 is sequenced behind PR #45 + a
  gnome-core26 rebuild (app aborts on the current stale
  desktop-launch).
- snapcraft checked-in expanded gnome example doc is stale - update
  once #6555+#6556 land (avoid double churn).
- snapcraft #6557 (craft-parts base-dedup gap) filed, unfixed.
- Publishing/promotion to stable channels: not started - gated on
  the merges above (mesa-2604 26.2.3 stable promotion at launch is
  the graphics team's action; 26.04 image seed revision bump is
  livecd-rootfs/image team's).
- multipass VM SSH "No route to host" flake investigation still
  open.
