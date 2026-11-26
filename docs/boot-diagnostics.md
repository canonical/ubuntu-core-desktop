# Diagnosing Ubuntu Core boot loops / failed run-mode transition

A VM that cleanly reboots every ~12-15s (not a kernel panic) is normally
the recovery/initramfs environment failing to hand off to the installed
system. Symptoms to look for in the boot log:

- `error: no such device: ubuntu-boot.` in GRUB output.
- Repeated `Expecting device dev-disk-snapd-disk.device` with no
  subsequent successful switch-root.
- `snapd_recovery_mode` cycling between `install` and `run` without ever
  reaching a booted run-mode system.
- Task failure `cannot load assertions for label "": no seed assertions`
  (i.e. "Setup system for run mode" failed) — this means the seed's
  assertion set doesn't validate, not a disk/partition problem per se.

Checks:

- GPT layout: a run-mode-capable image needs `ubuntu-seed`, `ubuntu-boot`,
  `ubuntu-save`, `ubuntu-data`. An install-only image only has
  `ubuntu-seed` — that alone isn't a bug, but check it's expected for the
  boot stage you're looking at.
- Seed assertions: `auto-import.assert` and any system-user assertions
  must target the image's actual model name (e.g.
  `ubuntu-core-desktop-24-amd64-dangerous`, not a 26-series model). If a
  Makefile/build shares one `auto-import.assert` between multiple build
  targets (e.g. 24 and 26), each target must regenerate/validate it rather
  than reuse a stale copy from a different model.
- If a build "used to work" and now doesn't, diff the base snap and snapd
  versions actually baked into the seed, not just the build script — a
  base or snapd swap changes seed assertion requirements as a side
  effect.

## UC26+ boots DIRECTLY into run mode — don't gate on the install label

On these images (ubuntu-image 3.10.10+, seeded gadget volumes), there is
NO separate install-mode-then-reboot-into-run-mode cycle to wait
through: the initramfs installer creates ubuntu-boot/save/data, writes
`modeenv mode=run`, updates the seed grubenv, and CONTINUES the SAME
boot. A fresh build's image file itself only has the BIOS Boot +
ubuntu-seed partitions (ubuntu-image deliberately skips boot/save/data
for seeded images per `ShouldSkipStructure`/`IsSeeded` — this is correct
UC20+ behaviour, don't "fix" the gadget yaml over a 1-2-partition GPT).

GATE TRAP: boot-1's `/proc/cmdline` carries a STALE `snapd_recovery_mode`
label from the fresh seed grubenv (it only updates once the initramfs
runs) — reading the cmdline label as mode evidence produces a false
"stuck in install mode" conclusion. Always read the MODEENV (what snapd
itself reads), not `/proc/cmdline`, to determine the actual boot mode.
More generally: any gate/check that runs immediately after boot must
confirm it's looking at the RIGHT system — the install/recovery
environment also runs sshd and accepts baked root credentials within a
few minutes, so an SSH check right after boot can silently measure the
wrong system (`snap list` showing only recovery snaps,
`is-system-running=starting`, no graphical session) while the gate
script itself still exits 0. Gate on run-mode evidence: modeenv says
`run` AND `snap list` contains the full seeded set (not just
`/proc/cmdline` no longer saying `install`).

A device-serial registration failure (store has no serial policy for an
unregistered dangerous brand/model) does NOT block the install→run
transition or the wizard — it costs only a background
"Initialize device" retry loop (journal noise, ~5 min cadence) and a
delayed first auto-refresh (snapd's `canAutoRefresh` needs a few
`ensureOperational` attempts first; manual refresh always works
immediately). Setting the gadget's `device-service.access=offline` (only
settable via the gadget's own configure hook for unasserted gadgets, not
via gadget.yaml defaults) suppresses the retry noise but PERMANENTLY
blocks auto-refresh instead (worse trade) — don't reach for it as a fix.

## Minimal image layout and sizing (ubuntu-image 3.10.10, build.sh)

- A fresh build writes ONLY BIOS Boot (1M) + ubuntu-seed (the gadget's
  declared size); `--image-size` just pads with unwritten holes beyond
  that and is ignored below ubuntu-image's own computed minimum (roughly
  the declared structures sized to the actual seed content + EFI).
  First boot's initramfs creates ubuntu-boot/save/data from the gadget
  layout and extends ubuntu-data to fill the disk — no growpart/
  resize2fs steps are needed for the normal path. A 5-partition image
  already on disk is just a 2-partition build that got booted at some
  point (first boot wrote the rest INTO that file) — never test
  installer/minimal-image flows against an image that has ever been
  booted (it also rewrites the seed vfat's FSInfo/grubenv on every
  boot, so even re-copying it afterwards isn't byte-identical to the
  build output).
- Seed content for a GNOME amd64 image: ~2.34 GiB (1.6G shared `/snaps`
  + 649M per-system-label snaps + 4.7M EFI); a second recovery system
  with shared root snaps costs only ~+0.65G more (worst-case double-seed
  ~4.68 GiB). `build.sh --minimal` (post-build truncate to the last GPT
  partition's end + 1MiB, `sgdisk -e` relocates the backup header) gets
  a seed-only artifact down near that real content size regardless of
  `--image-size`; the allocated/compressed size (sparse `du`, bmap
  `MappedBlocksCount`) is payload-bound and doesn't change with image
  padding — only the apparent size and bmap block count shrink.
- Seed partition smaller than the gadget's declared size does NOT boot
  (initramfs can't create the remaining partitions — emergency-reboot
  loop, GRUB prints "error: no such device: ubuntu-boot." once per
  cycle) — seed size must be changed via the gadget.yaml, never via
  post-processing a built image.
- A minimal (seed-only, truncated) RAW image is NOT directly bootable
  as a fixed-size VM disk (no room for the first-boot partitions);
  resize it first, or convert to qcow2 (`qemu-img convert` then
  `qemu-img resize`), which works directly.
- FDE (`storage-safety: prefer-encrypted`): without a TPM the build
  falls back to the unencrypted flow and boots fine. With swtpm in
  QEMU, the boot died silently after TPM measurement (systemd-stub used
  the TPM, no further kernel serial output, no partitions created) —
  treat the encrypted path as unverified until investigated separately,
  don't assume it works the same as the unencrypted fallback.
- Verification tools: `sfdisk -d`/`sgdisk -p` (read-only, work on image
  files), `du -h --apparent-size` vs `du -h` (holes vs content),
  `bmaptool create` (`MappedBlocksCount` = actual install-time bytes).
