---
upstream: https://github.com/canonical/core-base/pull/491
waiting_since: 2026-11-23
---
# Upstream the thin core26-desktop variant to core-base

## Impact / Priority

Priority: Medium — architecture/maintenance debt, not a user-facing
bug. Real-world impact for users: none directly; the impact is on
developers and the project's maintainability — today the thin variant
lives on a local branch that only one machine can build, so the base
snap cannot be built or refreshed by anyone else, and every manual
sync risk we removed from core-base-desktop's fat live-build returns
the longer the branch stays unpushed. For upstream (core-base), the
change is additive and desktop-gated: regular/cloud-init builds
produce payload-identical output to stock (proven by a full-clean
vanilla pack), so there is no reason for rejection on regression
grounds. End-to-end impact was verified by the base-swap project
itself: both GNOME and KDE images user-verified on the thin variant
(see
`20261105-replace-model-base-core26-desktop-with-stock-core26.md`).

## Work items

1. Restructure the 33-commit series into the maintainer-reviewed
   8-commit series (reviewed 2026-11-08; the restructure plan and
   absorption lists are recorded alongside it). Verification: final
   tree identical to the current branch, hook-tests green at HEAD,
   rebuilt snap content-identical.
2. Publish on canonical/core-base-desktop: DONE (2026-11-09, admin
   runbook executed): desktop/26 renamed to desktop/26-fat (open PRs
   #92/#91 retargeted automatically), desktop/26-thin renamed to
   desktop/26, repo default switched to the thin branch, the variant
   CI trigger flipped to desktop/26 (fea653f, run verified
   in-progress). The desktop-26-thin-latest release tag kept its name
   for consumer continuity. Note for future pushes from the
   core-base-variant worktree: push to refs/heads/desktop/26 (the
   -thin name is gone).
3. Address the four maintainer-review blockers BEFORE opening the
   upstream PR (they are review-rejection risks, not functional
   bugs):
   a. Provenance/SBOM for vendored payload: SUBSTANTIALLY REDUCED —
      perl+adduser relocated to the accountsservice snap as staged
      debs (md5-guarded patch, documented); the orphaned vendored
      chpasswd folded out of the branch history (pending the polish
      task); what remains is ~8 one-line provenance notes (4 PAM
      modules from debs, xdg-fuse-broker with in-tree source, the
      wrapper scripts).
   b. Architecture contract: RESOLVED-BY-DESIGN (re-scoped
      2026-11-08, maintainer-approved): the 16 hardcoded arch sites
      are parameterized (dpkg-architecture triplet everywhere) and
      the variant declares architectures: [amd64] so foreign-arch
      builds fail loudly instead of producing broken snaps; the
      arm64 payload-ELF sourcing list is documented (7 binaries from
      arm64 debs, gadget-arm64.yaml seed-size port, 10 triplet
      symlinks). The full arm64 image build + boot verification is
      DEFERRED TO THE ARM64 CI RUNNERS (re-scoped 2026-11-08: qemu
      TCG emulation was estimated at 2-5 days and rejected; GitHub's
      free arm64 hosted runners — ubuntu-24.04-arm, available since
      all project repos are PUBLIC — make the builds native at zero
      cost: add runs-on: ubuntu-24.04-arm matrix entries to the
      snap-repo and variant CI; mind runner disk (~14GB — put pc.img
      work on /mnt or build-to-artifact) and use snapcraft
      destructive mode (no nested LXD on GH runners). Boot
      verification: same-arch qemu-system-aarch64 TCG on the runner
      (acceptable for a one-shot gate) or real hardware when
      available.
   c. tools/build-variant.sh instance-state handling: records/starts
      only the first candidate, can attempt to start an
      already-running instance, lacks failure cleanup — harden.
   d. Isolation evidence: hook-tests/995-variant-payload.test checks
      only two config files; strengthen to compare the full payload
      (library links included) of regular/cloud-init builds vs stock
      (+#485, which legitimately changes stock permissions).
4. Open the PR: canonical/core-base-desktop:desktop/26 ->
   canonical/core-base main, describing the variant mechanism
   (payload dirs, fstab.d/writable.conf.d, tools, hook gating) with
   the core26-cloud-init variant as the precedent. The #485
   cherry-pick (fa2cc54, -x preserved) rides in the series or is
   dropped in favor of the upstream branch — preserve the setgid
   ownership invariant either way.
5. Track upstream review; when core-base main grows the variant
   machinery, shrink our desktop/26 toward payload-only.

## Notes

- #485 itself is already approved upstream; its merge makes our
  cherry-pick droppable.
- Do NOT attempt to land the payload (gdm stacks, unit graph, etc.)
  in core-base main — that is base content the upstream variant
  mechanism exists to carry on OUR branch; the PR is for the
  machinery + the variant plumbing only, with the desktop payload as
  the motivating consumer.

## Update 2026-11-23 (state refresh; RFC PR opened as #491)

State refresh against current upstream (main moved 224ca34 ->
26c0e62):

- #485 MERGED upstream (2026-11-11): the cherry-pick 6bd4383 is
  droppable as predicted; the setgid invariant lives upstream now.
- #446 (fstab /host) and #488 (core18/20 automation) merged;
  #486/#490 went to the core24 branch; #489 (reposcan workflow) open
  — CI in flux upstream, noted in the PR.
- Upstream main ALREADY had the variant seam (SNAP_BUILD_VARIANT
  selection, the commented fips stub, the spread matrix
  ["regular","cloud-init"]) — the PR is a generalization of an
  existing mechanism, not a new architecture.
- Item 3 blockers: ALL landed on desktop/26 (a540839 hardening+leak
  test; 1a366b7/3258e4f/a94dd66/14ee0d6 arch + native arm64 CI;
  vendored adduser/perl payload gone — debs staged at build time
  with provenance). 3a's history fold is moot for the PR (the series
  cherry-picks machinery onto a fresh base).
- Item 1 correction: the PR series is NOT the 8-commit restructured
  series (it mixes machinery with payload); it is a MACHINERY-ONLY
  extraction. Item 4 correction: the PR is NOT desktop/26 -> main
  (the branch carries 18 payload commits beyond the machinery).

The PR (https://github.com/canonical/core-base/pull/491,
RFC-framed):

- Branch upstream/variant-machinery off current upstream main
  (26c0e62); 4 signed commits: b0c1c9b variants/ payload mechanism
  (apply-variant-payload.sh + Makefile wiring + generic 995 leak
  test + 993 nested-d allowance + prepare-utils generalization +
  the variants/example demo payload); f37170f tools/build-variant.sh
  (hardened instance handling + repack naming); 742df8f per-variant
  architectures declaration (replaces the desktop branch's
  snapcraft.yaml platforms restriction, which cannot go upstream);
  2d079f1 dispatch-only CI workflow (amd64+arm64 hosted runners,
  artifact upload only).
- Branch pushed to canonical/core-base-desktop:upstream/variant-
  machinery (visibility) AND chris-bainbridge/core-base (the PR head
  — a cross-repo PR from core-base-desktop is impossible: it is not
  a fork of core-base, GitHub rejects the head; 422/GraphQL both).
- Description carries the maintainer question the PR exists to ask:
  end-state hosting (a: desktop variant in-tree / b: machinery-only
  + sibling repo / c: one universal core26, with the Phase-4
  irreducible-residue evidence for its cost), plus snap-naming
  repack acceptability, per-variant arch declaration shape, CI
  appetite. Reviewers cc'd: bboozzoo, Meulengracht (merged #485).
- Deviations: docs/arm64-recon.md NOT included (desktop-project
  recon with local paths; linked instead); the demo variant replaces
  the empty desktop scaffolding upstream; 995 genericized
  (marker-based detection, leak walk over ALL variants with
  chisel-manifest + extrausers exceptions) — desktop-specific
  assertions stay on desktop/26.
- Verification before opening: shellcheck clean; standalone
  functional exercise of apply-variant-payload.sh (all knobs,
  @MULTIARCH@ dir/content/symlink substitution, arch reject/accept,
  input validation); 995 regular-branch simulated on a synthetic
  prime (clean pass, leak + marker-only-leak detection,
  manifest/extrausers exemptions, fstab tamper detection); full
  example-variant build via tools/build-variant.sh
  (core26-example_20261123+example_amd64.snap, hook-tests green
  in-build, repack name/version verified); full-clean regular build
  (hook-tests green incl. the 995 regular branch; packed snap's
  fstab + core-writable.conf byte-identical to static sources, zero
  payload files, no VARIANT_ID).
- Build-infra note: the builds needed a caller-side http_proxy +
  no_proxy workaround — chisel's direct fetches bypass the host
  package-proxy setup; three failed attempts before the workaround.
- Item 5 unchanged (on merge: shrink desktop/26 toward payload-only
  — which now also means: move the arch declaration to
  variants/desktop/architectures, drop the branch's snapcraft.yaml
  platforms restriction, and extend 995's detection + leak walk to
  the desktop payload).
- Side-note: #92/#91 against desktop/26-fat were updated Nov 18/23 —
  external activity; belongs to
  `20261108-port-build-process-pr-to-thin-desktop26.md`.
