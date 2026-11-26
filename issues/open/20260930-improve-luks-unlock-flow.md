# LUKS unlock flow improvements

## Impact / Priority

The initramfs LUKS unlock flow gives no indication of the active
keyboard layout and, after a failed passphrase, offers only a generic
message with an automatic retry limit — a user whose console keyboard
is in an unknown or unusable layout can be locked out of an encrypted
machine with no explicit recovery options. Impact derived from the
original note's described symptoms.

## Scope

Improve the initramfs LUKS unlock flow: show the active keyboard
layout, recover from an unknown or unusable keyboard layout, and
provide explicit options after a failed passphrase. Do not change the
splash-screen unlock flow in this work.

Work through the steps in order. Do not start a step until the previous
step's verification gate passes. Each step has a concrete result and
gate; if a gate fails, fix that step before proceeding.

## Steps

1. Establish a reproducible VM baseline

   Create a disposable Ubuntu VM matching the affected machine's
   release and boot configuration. Configure an encrypted root disk and
   confirm that dracut, rather than another initramfs generator, builds
   the booted initramfs. Provide both a serial console and a graphical
   virtual console. Keep a rescue ISO and a known-good boot entry
   available.

   Verification gate:
   - The VM boots and unlocks successfully using the baseline image.
   - The booted initramfs is confirmed to be dracut-generated.
   - Unlock prompts and input are accessible through the serial
     console.
   - The graphical console is available for physical-console keymap
     tests.

2. Set up fast rollback and repeatable test images

   Shut down the baseline VM in a known-good state and preserve its
   disk as an immutable golden image. Run each test from a fresh qcow2
   overlay based on that image. Keep failed overlays temporarily for
   diagnosis; never merge them into the golden image. Record how to
   attach the rescue ISO and how to select the known-good boot entry.

   Verification gate:
   - A test overlay can be booted without modifying the golden image.
   - After making a harmless change in an overlay, a fresh overlay
     boots to the original known-good state.
   - The rescue ISO or known-good boot entry is reachable from the VM
     menu.

3. Identify the implementation and message sources

   Inspect the booted initramfs and matching upstream source to
   identify which component prints the unknown-keyboard-mode warning
   and which component prints the failed-passphrase message. Determine
   whether the warning is reflected in the command's exit status or
   only its output. Clone or otherwise obtain the exact upstream source
   revision to patch.

   Verification gate:
   - Both messages are attributed to specific commands/files in the
     booted initramfs and their upstream source.
   - The exact source revision and the command that builds the test
     initramfs are recorded.
   - The observed warning behavior, including exit status, is
     reproducible.

4. Reproduce the unknown-layout path before changing behavior

   Reproduce the warning in the VM and determine how the current unlock
   flow behaves when it occurs. If it cannot be triggered reliably, use
   a disposable test initramfs or test harness to inject the relevant
   failure; do not add a production-only failure mechanism. Distinguish
   serial-console behavior from graphical-console keyboard mapping.

   Verification gate:
   - The warning/failure path can be triggered repeatably without
     touching the golden image.
   - It is clear whether the failure is detectable by status, output,
     or another signal.
   - The test notes explain which observations require the graphical
     console, since loadkeys may not remap characters sent by a serial
     terminal.

5. Implement keyboard-layout reporting and recovery

   In the upstream source, show the active keyboard layout on the LUKS
   passphrase screen. When the layout is unknown or cannot be loaded,
   explain why the passphrase may not be entered as intended and
   require the user to select an available keymap before proceeding.
   List keymaps available in the initramfs in numbered columns, accept
   a valid number or name, and retain the default US/41 mapping on
   Enter. Update the displayed layout only after a keymap loads
   successfully.

   Verification gate:
   - A normal unlock prompt displays the correct active layout.
   - The injected unknown-layout case displays the explanation and
     keymap chooser instead of silently continuing as if the layout
     were known.
   - Enter selects the documented default; valid selections load and
     display the selected keymap; invalid selections do not silently
     succeed.
   - A graphical-console test confirms that changing the keymap
     changes punctuation input as expected.

6. Implement explicit recovery choices after failed passphrases

   Replace the generic failed-passphrase message with a clear message
   that says the passphrase or keyboard layout may be wrong and
   displays the current layout. Offer Enter to return to the passphrase
   prompt, K to change layout, S for a recovery shell, P to power off,
   and R to reboot. Remove retry-limit-triggered automatic recovery so
   the user remains in control. Keep passphrase input hidden and out of
   logs.

   Verification gate:
   - A wrong passphrase displays the new message and current layout.
   - Enter returns to the passphrase prompt without exhausting a retry
     limit.
   - K opens the keymap chooser and returns with the updated layout.
   - S enters a usable recovery shell.
   - P powers off and R reboots the VM.
   - The passphrase is not echoed or written to logs.

7. Run the complete VM regression matrix

   Build the modified initramfs and test it using a fresh overlay for
   each run. Exercise normal unlock, wrong passphrase, unknown-layout
   recovery, keymap change, recovery shell, power off, and reboot. Use
   the serial console for prompt/control-flow checks and the graphical
   console for keyboard-mapping checks. Confirm the original image
   still boots by discarding the test overlay and starting a fresh
   one.

   Verification gate:
   - Every scenario above passes and its result is recorded.
   - A failed test can be rolled back by starting a fresh overlay.
   - The golden image remains unchanged and boots successfully.

8. Prepare the upstreamable patch

   Review the final diff for scope, follow the upstream project's
   conventions, and run the relevant tests/build checks. Include
   concise reproduction and verification instructions with the patch.
   Do not include splash-screen changes.

   Verification gate:
   - The patch applies to the recorded upstream revision.
   - Relevant tests/build checks pass, and the VM regression matrix
     from Step 7 passes on the final patch.
   - The final diff contains only the initramfs unlock-flow changes
     and directly related tests or documentation.

## Completion record

1. Baseline: PASS. Ubuntu 26.04, dracut 110, systemd 259.5, encrypted
   root on LVM; the initramfs was built by dracut. Normal unlock was
   verified over serial and VGA consoles.

2. Rollback: PASS. The 0444 golden image remained unchanged. A fresh
   qcow2 overlay backed directly by it booted, unlocked, and reached
   SSH. The main feature test used a disposable overlay backed by the
   baseline/golden chain.

3. Sources: PASS. The warning originates from kbd's `kbd_mode`; the
   passphrase failure originates from systemd-cryptsetup. The dracut-ng
   checkout is based on `5d55d1c23781970206d9feb50e1461a4c24441ce`. The
   VM initramfs was rebuilt with `dracut --force --omit plymouth`.

4. Unknown layout: PASS. A test-only `kbd_mode` stub returned failure
   in an initramfs with `tty0` active. The warning and chooser appeared
   before the passphrase prompt; invalid input was rejected and Enter
   loaded US/41. Serial input was treated as unmapped; physical keymap
   behavior was tested separately on VGA.

5. Layout recovery: PASS. The normal VGA prompt reported US/41. Invalid
   keymap number 999 was rejected; the UK keymap loaded and was
   displayed. With UK selected, VGA Shift+2 produced the quote used by
   a temporary LUKS test key and unlocked the root. That extra key was
   removed afterward.

6. Failed-passphrase recovery: PASS. A wrong passphrase opened the
   recovery menu. Enter retry and retry after changing the layout both
   unlocked after the handler removed systemd's cached failed
   passphrase. The recovery shell executed a command and returned to
   the menu; poweroff stopped QEMU; reboot returned to the unlock
   prompt. Passphrases were not echoed after the TTY prompt settled and
   were absent from the journal.

7. Regression matrix: PARTIAL. Normal unlock, wrong-passphrase retry,
   keymap recovery, shell, poweroff, reboot, injected unknown mode, VGA
   punctuation, and fresh-golden rollback all passed. The scenarios
   reused the disposable feature overlay across reboots rather than
   using a new overlay for every scenario.

8. Upstream checks: PARTIAL. Shell syntax and `git diff --check`
   passed; the modified initramfs built and the behavior was verified
   in the VM. The targeted `TEST-26-ENC-RAID-LVM` suite could not be
   run: `./configure` requires the missing libkmod >= 23 development
   package, and the host also lacks console keymaps and non-interactive
   root access.

## Follow-up: dual-console serial recovery

The serial-console regression was traced to using `/dev/console` for
recovery input and output. With `console=ttyS0,115200n8 console=tty0`,
`/dev/console` targets the VGA console even though the systemd password
agent serves both consoles. The recovery helper now writes status text
to all active kernel consoles and uses
`systemd-ask-password --no-tty --echo=yes --timeout=0` for menu and
keymap input. This also creates the pending ask-password request that
dracut-initqueue already checks before advancing its timeout handling.

Verification: the updated helper was embedded in a fresh initramfs and
booted in a disposable dual-console VM. The keyboard-layout status and
recovery menu were visible on serial; selecting retry and entering the
correct passphrase over serial returned to the login prompt. During the
wait, dracut-initqueue remained active; no timeout warning was captured
on serial, but the reported VGA warning stream was not captured
directly, so that exact symptom remains partially verified.

A persistent test overlay is now available in
~/git/upstream/luks-test-vm/ (recovery-serial-updated.qcow2). It is
based on `recovery-serial.qcow2` and contains a rebuilt initramfs whose
helper checksum matches the working tree. The VM was powered off after
the build; this persistent image has not yet been reboot-tested with
that rebuilt initramfs. The golden image was not modified.

## Redo (2026-11-09): minimal redesign

Status: PR OPEN, IN PROGRESS. The pull request has been opened against
upstream dracut-ng; not finished until it is merged, including the VM
regression matrix passing on the final patch.

The first implementation was rejected as too complicated. Its recovery
machinery (keymap chooser, K/S/P/R menu, OnFailure unit, forced single
try, keyctl purge, forced all-keymaps install) was removed from the
working tree. The tree is at ~/git/upstream/dracut-ng, base
5d55d1c23781970206b9feb50e1461a4c24441ce, changes uncommitted.

Investigation findings that drove the redesign:

1. "The keyboard is in some unknown mode" is printed by kbd's
   kbd_mode, which 20i18n/console_init.sh runs on tty0 via the
   initqueue (hence the dracut-initqueue attribution). kbd <= 2.9 has
   no case for the kernel's K_OFF mode, so a VT left in K_OFF
   (typically by plymouth) is reported as "unknown"; Ubuntu 26.04 ships
   kbd 2.7.1 and kbd 2.10.0 fixed the labelling. kbd_mode exits before
   changing anything, so the warning never impaired passphrase entry -
   it was coincident with, not causal to, the reported unlock failure.
   Consequences: no initramfs UX change is needed for it. The warning
   is purely presentational: kbd_mode declines the switch and exits
   before touching the console state (kbd_mode.c exits before the
   KDSKBMODE ioctl), and the keymap dimension is unaffected - the
   reported unlock failure was keymap/typo related, the warning
   coincidental, not causal. Ubuntu SRU is therefore not justified for
   the kbd relabelling: there is no functional fault, only a misleading
   label in early-boot output, which does not meet the SRU requirement
   of real user impact. kbd 2.10.0 already fixed the labelling
   upstream, so it reaches Ubuntu via the normal kbd release/sync path,
   not an SRU. Optional and equally non-SRU: a small console_init.sh
   robustness fix (pass -C, tolerate failure) in dracut-ng. A reference
   kbd checkout now lives at ~/git/upstream/kbd.

2. The wrong-passphrase emergency drop is systemd-cryptsetup's default
   of three attempts (arg_tries in src/cryptsetup/cryptsetup.c). The
   service failure then cascades through dev-mapper-*.device and
   sysroot.mount into OnFailure=emergency.target; the "root drive does
   not exist" text comes from dracut's parse-root.sh emergency hook.
   No timeout is involved - the drop is immediate. crypttab tries=0
   already means "retry indefinitely", each round printing systemd's
   own "Passphrase incorrect?" message, and headless= entries still
   fail immediately. Debian initramfs-tools and Arch mkinitcpio already
   re-prompt forever; systemd just defaults to 3 and dracut did not
   override it.

The minimal patch (4 tracked files changed, 71 insertions, 2
deletions, plus two new files):

- modules.d/71systemd-cryptsetup/dracut-crypt-prepare.sh (new, 196
  lines, purely informational): prints "Keyboard layout: <name>"
  immediately above the passphrase prompt; a single warning line if
  the layout or keyboard mode is unknown; nothing for keyfile entries
  or under plymouth; never asks for input and never fails the unlock.
- modules.d/71systemd-cryptsetup/cryptsetup-prepare.conf (new):
  drop-in adding only ExecStartPre=/sbin/dracut-crypt-prepare prepare
  %I.
- modules.d/71systemd-cryptsetup/module-setup.sh: installs the helper
  and drop-in (non-plymouth only) and rewrites the initrd crypttab so
  interactive entries default to tries=0 (explicit tries=, headless=
  and keyfile entries untouched). The rewrite is not plymouth-gated so
  splash boots also keep prompting.
- modules.d/70crypt/crypt-run-generator.sh: runtime rd.luks entries
  also get tries=0 unless rd.luks.key= is set.
- modules.d/20i18n/module-setup.sh: independent empty-directory
  bugfix kept from the first attempt.
- man/dracut.cmdline.7.adoc: short documentation of both behaviours.

Verification so far (no VM - the previous test images were deleted):
bash -n and shellcheck clean; helper fixture tests 11/11; crypttab
rewrite matrix 15/15; runtime generator tests 5/5; an install()
harness proves the crypttab rewrite runs with and without plymouth
while the helper installs only without plymouth; a throwaway initramfs
built into /tmp contains the drop-in and the rewritten crypttab.

## PR preparation and independent review (2026-11-10)

The changes were split into three logical commits on branch
crypt-unlock-tries0-layout in ~/git/upstream/dracut-ng, rebased onto
current origin/main (04e04cf), nothing pushed:

1. fix(i18n): skip empty keymap subdirectories in install_all_kbd
2. feat(crypt): default initrd LUKS passphrase prompts to unlimited
   tries
3. feat(systemd-cryptsetup): report the keyboard layout at the
   passphrase prompt

The branch went through four rounds of independent maintainer review
(an independent reviewer acting as an upstream maintainer, explicitly
instructed to find counterexamples). Three fix rounds followed. The
material redesign from review: the helper was changed from a
(partially systemd-compatible) duplicate keymap loader into a purely
informational reporter, and the unlock is now ordered after the
authoritative systemd-vconsole-setup.service by a drop-in adding
After=, Wants= and ImportCredential=vconsole.keymap to
systemd-cryptsetup@.service - so the complete keyboard configuration,
including KEYMAP_TOGGLE, is guaranteed applied before the prompt and
the helper can no longer fight the effective configuration. The
cmdline and vconsole.conf parsers are ports of systemd v259.5 sources
(proc-cmdline tokenization, parse_env_file_internal) differentially
tested against a compiled v259.5 oracle. Final counts: 130/130 parser
cases (incl. 60 oracle cross-checks), 39/39 end-to-end helper
fixtures, crypttab rewrite 15/15, runtime generator 5/5, i18n fixtures
pass, and throwaway initramfs builds with and without i18n/plymouth
both succeed. Closing verdict: "ready to submit upstream"; no known
unlock-blocking regression.

Limitations recorded by review (documented in the man page and PR):

- Devices that systemd-cryptsetup-generator creates natively from
  rd.luks.uuid= without a matching crypttab entry keep systemd's
  default of three attempts; rd.luks.options=<uuid>=tries=0 is the
  mitigation. The complete fix belongs in systemd.
- On a systemd v253 initrd a credential-only keymap cannot be reported
  (ImportCredential= arrived in v254); harmless, non-fatal.
- plymouth builds install neither the layout line nor the ordering
  drop-in (text output would be invisible behind the splash).

## Cross-family review and PR split (2026-11-10)

The layout helper's parser-parity approach (592 -> 253 lines, 130-case
differential suite) was cut back after an owner decision: two separate
PRs now exist, and the layout display is a best-effort line, not a
guarantee.

- PR #2823 (fixes): i18n empty-dir fix (a38380a), crypttab tries=0
  default (6d37582), ordering (5476cda). The ordering drop-in moved to
  systemd-ask-password-console.service (Wants=systemd-vconsole-setup;
  After= already upstream): ordering the cryptsetup instances instead
  was rejected in independent review because vconsole-setup is
  Type=oneshot with the start timeout disabled
  (src/core/service.c:1241-1243) and waits unboundedly on the console
  lock and loadkeys/setfont - so a hung vconsole-setup would hang
  every unlock, including unattended TPM2/keyfile boots. With the
  prompt unit only, automatic unlocks never wait; a hung
  vconsole-setup already blocks sysinit.target anyway.
- PR #2824 (display): dracut-crypt-prepare.sh is now 25 lines -
  plymouth skip, getarg vconsole.keymap / rd.vconsole.keymap, last
  KEYMAP= of /etc/vconsole.conf (one quote layer stripped), one printf
  to /dev/console, always exit 0, silent when unsure. Accepted
  limitation: toggle/credential/exotic-config/failed-load cases may
  misreport or stay silent; "never misreport" was shown unattainable
  at any line count (a keymap that fails to load is undetectable), so
  the complexity was not worth buying. Fixtures 11/11; tail is not in
  real initramfs images, so the file read is pure bash; getarg does
  not strip rd. itself, so both spellings are queried.
- systemd: the generator-ordering patch was reworked to a 1-line unit
  change (Wants= on systemd-ask-password-console.service) after
  review, re-verified in the mkosi VM with a passphrase-only LUKS
  volume: the prompt can render while vconsole-setup is inactive
  (race reaches the actual prompt path), and with the fix the prompt
  waits for the keymap while cryptsetup timing is unchanged
  (automatic unlocks unaffected). Issue filed:
  https://github.com/systemd/systemd/issues/44761 (PR deliberately
  withheld pending maintainer response; the local branch
  cryptsetup-order-after-vconsole, commit 721678998c, is
  submission-ready).

## Maintainer feedback and un-stack (2026-11-12)

Conan-Kudo (collaborator) on #2824: "Please don't stack changes like
this. I don't know if I want #2823, but I probably do want this."
Response: #2824 was rebased standalone on current main (tip 519d659 -
only the keyboard-layout change: helper, cryptsetup-report.conf,
module-setup install hunks, man paragraph; the tries=0 and ordering
content was dropped from the branch), the PR body was rewritten
standalone, and a reply clarified that #2823 bundles three independent
commits (i18n fix, tries=0, ordering) that can be split or dropped
individually. Comment:
https://github.com/dracut-ng/dracut/pull/2824#issuecomment-6826196611

Verification of the standalone rebase: conflicts resolved by excluding
tries=0/ordering content; bash -n + shellcheck clean; build smokes of
the submitted tree (staged dracutbasedir + host
dracut-install/util): without plymouth the image contains the report
drop-in and helper and no ask-password ordering drop-in, crypttab has
no tries=0 (that is #2823's); with plymouth neither helper nor report
drop-in is installed. The submission-ready systemd branch (721678998c)
is kept locally, waiting on issue #44761 maintainer response.

## Split per maintainer request (2026-11-14)

Conan-Kudo on #2824: "Please split those out too. I'm pretty sure the
major controversial change is the infinite retries. The rest of it
seems sensible enough." #2823 was closed in favor of three individual
PRs (each one commit, built piecewise on origin/main, no stacking):

- #2828 i18n empty-dir fix, tip 0ab7231 (1 file).
- #2829 tries=0 default, tip 3738825 (3 files). Post-split fix found
  and closed a real hole: the crypttab awk skipped "headless=" but
  systemd's parser also accepts bare "headless"
  (src/cryptsetup/cryptsetup.c:595), so an unattended boot could have
  looped forever without a prompt; skip test now covers either
  spelling, fixtures 14/14, man page documents both spellings.
- #2830 prompt/keymap ordering, tip d5649bd (3 files; cherry-pick
  conflicts resolved to ordering-only content; build smokes prove the
  drop-in lands unconditionally, with and without plymouth).

#2824 was left completely untouched per owner instruction (tip
519d659). The close comment on #2823 links the three PRs. The tries=0
PR (#2829) is the one the maintainer expects to be controversial; its
body leads with the stranded-user rationale and the Debian/Arch
precedent.

Current PR state:

- https://github.com/dracut-ng/dracut/pull/2824 - layout display,
  standalone, tip 519d659. Maintainer: "I probably do want this."
- https://github.com/dracut-ng/dracut/pull/2828 - i18n fix,
  tip 0ab7231.
- https://github.com/dracut-ng/dracut/pull/2829 - tries=0 default,
  tip 3738825 (controversial one).
- https://github.com/dracut-ng/dracut/pull/2830 - ordering,
  tip d5649bd.

Remaining work, in order:

1. Iterate on maintainer review of the four PRs (tests question: no
   in-tree regression tests - point at the fixture suites or add one
   if asked).
2. Follow systemd issue #44761; open the systemd PR once maintainers
   endorse the approach. Long-term simplification candidate from
   review: a systemd feature to record the applied keymap under /run
   would let the display helper become a one-line read.
3. Recreate the VM golden-image/overlay setup and re-run the
   regression matrix from steps 5-7, including a plymouth boot -
   before merge at the latest.
4. systemd follow-up (separate): tries=0 for natively generated
   devices (rd.luks.uuid= without crypttab entry).

Immediate mitigation that needs no patch: add tries=0 to the root
entry in /etc/crypttab and regenerate the initramfs.
