# Build a working KDE Neon Core image (staged: core24 baseline, then core26)

Date: 2026-09-17

## Impact / Priority

Delivers a bootable KDE Neon Core (Plasma desktop) image built and
booted on this project's ubuntu-core-desktop tooling, in two stages —
while ensuring the existing GNOME image builds are not broken. Impact
derived from the original note's described symptoms. No priority level
was stated in the original note.

## Goal

Get a KDE Neon Core (Plasma desktop) image built and booting on our
ubuntu-core-desktop tooling, in two stages:

1. A build based on the known-good core24 image build pipeline. Verify
   it boots to a working Plasma session.
2. Port that to the active core26 image build pipeline. Verify it boots
   too.

Do NOT break the existing GNOME image builds (their models, snaps, or
scripts) while doing this. Prefer additive changes (new model/json
files, new build script variants) over modifying the GNOME ones in
place.

This was previously functional under core24 (per the user), so stage 1
should mostly be "restore/adapt", while stage 2 is genuinely new porting
work analogous to what we've already done taking the GNOME image from
core24 to core26.

## Background reading: KDE Neon Core building blocks

Source: https://community.kde.org/Neon/Core

KDE Neon Core is KDE Neon's Plasma desktop repackaged entirely as snaps
on an Ubuntu Core base — analogous in shape to what we do for GNOME, but
using KDE's own snap sources instead of ours. The pieces:

- snapd: built from the same
  https://github.com/canonical/ubuntu-core-desktop-snapd fork we
  already use (latest/edge/ubuntu-core-desktop track). No new work
  needed here — reuse our existing snapd.snap.

- pc-desktop (gadget): KDE's wiki says to use "branch 24 of
  https://github.com/canonical/pc-amd64-gadget-desktop" — same upstream
  repo we already build from, just their branch forces auto-connections
  for `plasma-desktop-session` instead of `ubuntu-desktop-session`. We
  likely need a gadget variant (or an extra gadget.yaml
  interface/connection stanza) with those auto-connects added,
  analogous to how our pc-desktop gadget auto-connects
  ubuntu-desktop-session today.

- plasma-core24-desktop (content snap): built from
  https://invent.kde.org/neon/snap-packaging/plasma-core-desktop (KDE
  GitLab, "invent.kde.org", not GitHub). Provides all the Plasma
  session content but no services/apps of its own (a pure "content
  snap", like our core desktop content bits). Built with plain
  `snapcraft` at repo root.

- plasma-desktop-session (app snap): built from
  https://invent.kde.org/neon/snap-packaging/plasma-desktop-session.
  This is KDE's analogue of our ubuntu-desktop-session snap: it's the
  "app snap" that runs confined and drives startup/services of the
  Plasma session, referencing plasma-core24-desktop's content. Its
  `run-session.sh` is the equivalent of our run-session type scripts
  and a good place to inject debug env vars
  (QT_LOGGING_RULES=*.debug=true, QDBUS_DEBUG=1,
  systemd-analyze --user set-log-level debug) when troubleshooting —
  then rebuild the snap and check journalctl.

- Known upstream limitation (as of the wiki): no SDDM shipped; the
  images depend on GDM from core24-desktop as the base, because SDDM
  packaging into its own snap isn't ready upstream. This actually
  aligns well with our own core24-desktop / core26-desktop bases, which
  already carry GDM — so plasma-desktop-session likely wants to run
  alongside/instead-of ubuntu-desktop-session on the *same*
  GDM-carrying base snap, not a separate display manager stack.

- Upstream image repo: https://invent.kde.org/neon/ubuntu-core (KDE's
  equivalent of our ubuntu-core-desktop repo). It contains the
  `kde-neon-core-dangerous-amd64` model plus a Makefile
  (`make kde-neon-core-dangerous-amd64.img`, `make dangerous` for an
  ISO) and expects locally-built snaps dropped into a `local-snaps`
  directory, with everything else pulled from the Snap Store. We
  should clone this repo to see its exact model file and Makefile
  logic, but MUST reimplement the model as our own
  ubuntu-core-desktop-kde-*.model (see step 3) rather than depend on
  KDE's Makefile/tooling directly, so it fits our image build pipeline
  and asserted models.

## Key adaptation problem

The upstream kde-neon-core-dangerous-amd64 model is built against
*vanilla* Snap Store snaps (core24-desktop, pc-desktop, etc. from
Canonical's real store). Our local 24 and 26 pipelines use custom,
locally-signed/rebuilt versions of core24-desktop / core26-desktop /
pc-desktop / snapd with local patches (see
ubuntu-core-desktop/README.md's snap table). So step 1/2 is not "just
run KDE's Makefile" — it's "take the upstream KDE model as a reference
and reproduce its snap list/interfaces inside a new
ubuntu-core-desktop-kde-24-amd64-dangerous.model (and later -26-)
following the same local-snap-substitution pattern the image build
already uses for GNOME".

## Sequenced plan

1. Research/prep: clone
   https://invent.kde.org/neon/ubuntu-core,
   https://invent.kde.org/neon/snap-packaging/plasma-core-desktop, and
   https://invent.kde.org/neon/snap-packaging/plasma-desktop-session.
   Read their READMEs, Makefiles, snapcraft.yaml, and the
   kde-neon-core-dangerous-amd64 model/json in ubuntu-core. Record the
   findings (exact upstream snap names/ids/channels used, gadget
   differences vs our pc-amd64-gadget-desktop, and any KDE-specific
   interfaces/plugs needed) in the project documentation. This step is
   mostly reading and summarizing, but requires judgement about what's
   relevant — it sets direction for everything else and mistakes here
   are expensive to unwind.

2. Build plasma-core-desktop and plasma-desktop-session snaps locally
   with plain `snapcraft` per their repo instructions (as the wiki
   describes). Mechanical: clone, run snapcraft, capture build logs,
   note failures verbatim without root-causing them yet.

3. Diagnose and fix any snapcraft build failures from step 2 (likely
   candidates: base mismatches, missing chisel slices/parts, core24 vs
   core26 base assumptions, KDE-specific stage-packages not available).
   This requires the same kind of judgement calls as the
   core-base-desktop packaging work (chisel vs apt overlap,
   stage-conflict resolution).

4. Create ubuntu-core-desktop-kde-24-amd64-dangerous.model (json +
   model), derived from our existing
   ubuntu-core-desktop-24-amd64-dangerous.model, replacing/adding:
   ubuntu-desktop-session -> plasma-desktop-session, adding
   plasma-core24-desktop as a content-providing app snap, and folding
   in the gadget auto-connect changes for plasma-desktop-session
   identified in step 1. Keep core24-desktop as the base (unchanged)
   so GDM keeps working per the known upstream limitation. Sign it the
   same way our other dangerous models are signed (via `snap sign` in
   the Makefile).

5. Duplicate the Core 24 image build script into a KDE-specific build
   script (do not edit the original) that points at the new KDE model
   and drops the locally-built plasma-* snaps into the local-snaps
   directory, analogous to how the GNOME build drops ours. Similarly
   duplicate the image boot script with a distinct IP/port so it
   doesn't clash with the existing Core 24 test VM. Purely mechanical
   copy-and-rename work with small path substitutions.

6. Run the new KDE build script, fix any build-time errors (missing
   assertions, gadget auto-connect mismatches, model validation errors
   — watch for the documented gotchas about gadget naming and
   stage-packages caching).

7. Boot the KDE image, SSH/serial in (root password `x` on serial, per
   existing convention), and debug the Plasma session using
   plasma-desktop-session's run-session.sh debug hooks and journalctl,
   until Plasma starts. Use the established GDM/session debugging
   methodology — this is likely to rhyme with GNOME session issues
   we've already solved (confinement/AppArmor gaps, systemd user unit
   confinement, etc.) since plasma-desktop-session follows the same
   "app snap confined session on top of content snap" shape as
   ubuntu-desktop-session.

8. Once stage 1 boots to a working Plasma desktop, verify nothing
   regressed in the GNOME Core 24 image (rebuild/boot it unmodified
   and confirm GDM/GNOME still comes up) before moving to stage 2.
   Quick regression check, but worth care given it's a "don't break
   this" gate.

9. Duplicate the KDE Core 24 build/boot scripts into Core 26 variants
   (again, copy-and-rename, mirroring how the Core 26 GNOME build
   relates to the Core 24 one), and duplicate the KDE model into
   ubuntu-core-desktop-kde-26-amd64-dangerous.model with base:
   core26-desktop, following the same snap/channel adjustments already
   made when we ported the GNOME model 24 -> 26 (see
   `20260915-update-old-snaps-in-desktop26-model.md` for the pattern:
   which snaps needed 26/stable channels, which bases could be
   dropped, etc.).

10. Rebuild plasma-core-desktop / plasma-desktop-session against
    core26 (or confirm/adjust their snapcraft.yaml base), since KDE's
    own upstream targets core24 only. This is genuinely new porting
    work, same category as our core24->core26 GNOME migration
    (chisel/apt conflict issues likely apply here too), iterating with
    LXD build introspection.

11. Build and boot the KDE Core 26 image, debug until Plasma boots on
    core26, reusing the confined-session AppArmor/systemd fixes
    already discovered for GNOME's core26 port where applicable (see
    `20260916-confine-gnome-session-user-units.md` and the other
    confined-session items — the KDE app snap will likely hit the same
    class of confinement gaps).

12. Final regression pass: verify the GNOME Core 24 and Core 26 builds
    still build and boot unmodified. Then record a summary of what the
    KDE build needs (new scripts/models added, any shared-file
    touchpoints, remaining known issues) in the project documentation
    so future work doesn't have to rediscover this.

## Notes on which steps need judgement

Mechanical steps (cloning, running snapcraft and capturing output,
copy/rename/path-substitution of existing scripts) carry no
architectural judgement. The other steps involve either first-time
architectural decisions (what the KDE model should contain, how
content/app snap wiring should look), debugging opaque build/boot
failures, or a "must not regress GNOME" verification gate — these
benefit from stronger reasoning and are where nearly all of the real
risk in this task lives. If a mechanical step runs into non-mechanical
trouble (a build error whose cause isn't obvious, a boot failure),
escalate that specific piece rather than guessing.

## Resolution note (appended 2026-09-18)

Stage 1 (core24 baseline) is COMPLETE and verified: the KDE Neon Core
image builds and boots to a RENDERING Plasma desktop (not just running
daemons). Steps 1-7 done.

What was actually done (beyond the original plan):

- Plasma forward-ported 6.2.5 -> 6.7.5 (matching Qt 6.11.1 / KF
  6.27.0), fixing the "org.kde.plasma.plasmoid already used for type
  registration" black-screen crash. Uncommitted in the
  plasma-core-desktop repo.
- Three build bugs fixed to get a rendering desktop:
  1. stale-prime service files (snapcraft.yaml override-prime rm -f)
  2. missing org.kde.private.desktopcontainment.folder QML module
     (999 hook was removing the whole org/kde/private tree)
  3. GDM login race (content[plasma-core24] not connected before
     autologin) — fixed by gdm.service.d drop-in, mirroring upstream
     commit 6463bd1.
- The 4 upstream ubuntu-core-desktop commits (8736d00, 6463bd1,
  8800018, 18a057f) were merged into the kde branch (commit 6a8669a).
- Confinement verified: each Plasma component runs under its own
  enforce-mode AppArmor profile (same model as GNOME, cleaner).

NOT done (carried forward to new items):

- Step 8 (verify GNOME 24 not regressed) — not done.
- Steps 9-11 (core26 port) — carried to `20260918-kde-core26-port.md`.
- Step 12 (final regression) — folded into the core26 port item.
- Merge ubuntu-core-desktop-kde back into ubuntu-core-desktop — see
  `20260918-merge-kde-repo-back-into-ubuntu-core-desktop.md`.
- KDE AppArmor denials (polkit-agent, powerdevil) — see
  `20260918-kde-plasma-apparmor-denials.md`.
