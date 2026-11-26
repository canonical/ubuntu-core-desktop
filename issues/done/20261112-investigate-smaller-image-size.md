# Reduce the 20 GiB Ubuntu Core Desktop image; decide raw vs qcow2

## Impact / Priority

A user downloading or flashing the image got a nominally 20 GiB
artifact of which only ~4.8 GiB was written content (the rest is
sparse holes inside the partitions), and it was undecided whether the
shippable artifacts should be raw, zstd+bmap, or qcow2. Impact derived
from the original note's described symptoms.

Companion to `20261111-installer-bmap-write-optimization.md` (bmap
installer, verified) and an imagecraft PR #95 review-and-parity note.

## Measured starting point (pc.img, KDE variant)

    apparent size:      20 GiB (sparse file)
    allocated:          4.8 GiB
    partitions (GPT):   p1 bios-boot   1M
                        p2 ubuntu-seed 6.8G vfat, content 2.2G
                        p3 ubuntu-boot 750M
                        p4 ubuntu-save 32M
                        p5 ubuntu-data 12.4G ext4, preseeded ~2.4G
    free space:         ~14.6G of unwritten (hole) regions inside the
                        partitions -- the bmap installer already skips
                        these (writes only 4.8 GiB)
    verified this session: the full-dd install and the bmap install
    produce byte-identical disks (cmp vs pc.img, excluding one grubenv
    byte touched by the recordfail experiment)

## Why the image is 20G, and what "minimal" means

The 20G comes from --image-size 20G padding ubuntu-data at build time;
ubuntu-seed is gadget-declared at 7000M (also padded: 2.2G content).
The minimal image is NOT "the filesystems at their minimum" alone --
three levers, in order of authority:

  1. the gadget yaml declarations (seed 7000M, data 1G) -- the
     authoritative sizes snapd validates against; changing them is a
     pc-amd64-gadget-desktop PR
  2. --image-size at build time (pads ubuntu-data beyond the gadget
     declaration; the dev convenience we are trying to remove)
  3. post-build shrinking (resize2fs/sfdisk/virt-resize) -- works on
     existing images without a rebuild, but the result must stay
     consistent with the gadget declarations (or the declarations must
     change first)

## 1. Tool compatibility with our flow (test and verify)

Our working environment: the LXD build container (root, ext4+loop
works, mknod-from-sysfs pattern proven this session), the host (no
sudo), and the ISO/QEMU verification loop.

- [ ] ext4 (ubuntu-data, ubuntu-boot): e2fsck -f + resize2fs -M
      (minimum) or resize2fs <target> on a loop device with partition
      offset; then shrink the partition (sfdisk/parted) and relocate
      the GPT backup header (sgdisk -e or fix manually); truncate the
      image file. All tools present in the installer build container.
      TEST the full sequence on a pc.img copy.
- [ ] verify after shrink: the shrunk image BOOTS (it is a
      pre-initialised image -- modeenv mode=run/good -- so a direct
      QEMU boot reaches the desktop; that validates the boot chain
      without needing an install run)
- [ ] vfat (ubuntu-seed): resize2fs does not apply; fatresize exists
      but is flaky, and the seed size is gadget-declared (7000M).
      Expectation: seed shrinking = gadget yaml PR, not post-processing.
      Verify whether snapd accepts a seed partition smaller than
      declared before relying on any vfat resize.
- [ ] virt-resize (libguestfs): would wrap the whole sequence, but the
      appliance needs a kernel+modules (awkward in the LXD container;
      apt install needs root on the host). Evaluate only if the manual
      sequence proves fiddly; the manual path needs nothing new.
- [ ] the modeenv burn-in trap: ALL shrink/growth tests must use a
      FRESH never-booted image (plain image build; CORRECTION
      2026-11-12: there is no --image-size flag on build.sh -- the 20G
      is hardcoded at build.sh's ubuntu-image call, line ~1971;
      building SMALL images natively needs a temporary local edit of
      that line or a new --image-size flag in build.sh), never a
      booted one. Booted images skip device initialisation (modeenv
      mode=run/good) and give misleading results (verified this
      session: a pre-booted 12.4G data partition did not extend on a
      64G disk).

## 2. Absolute minimal size (test and verify)

- [ ] measure resize2fs -M on the preseeded ubuntu-data fs
      (12.4G, ~2.4G content): expect minimum ~2.6-3G
- [ ] measure the ubuntu-seed vfat content precisely (2.2G du) and the
      size the gadget would need to declare (content + headroom for a
      second recovery system for rollback: ~4.5-5G, or less if we
      accept dropping rollback slack)
- [ ] compute the floor: seed(min) + boot(content ~0.3G in 750M) +
      save 32M + data(min) -- expect ~4.5-6.5G depending on the seed
      decision; compare with a native --image-size build of the same
      size
- [x] THE DECISIVE TEST -- ANSWERED YES (2026-11-12 23:5x): device
      initialisation DOES extend ubuntu-data on first boot of a fresh
      never-booted image. Test: a fresh build/pc.img (never booted,
      ubuntu-data 12.4G) installed via the zstd+bmap ISO onto
      a 64G target (total guest write 2.436 GB = exactly the bmap's
      594316 mapped blocks), reboot, first boot: snapd seeding ~4 min,
      then serial login. lsblk on the installed system: ubuntu-data
      EXTENDED 12.4G -> 56.4G (filling the 64G disk); df confirms the
      ext4 resized with it (/dev/vda5 56G, 6.4G used, 47G avail);
      modeenv mode=run, recovery system 20261112. CONSEQUENCE: MINIMAL
      IMAGES ARE SAFE -- the gadget's small data declaration holds at
      install time and the first boot claims the rest of the disk. No
      gadget install-device hook needed, no shipping-without-data
      needed, no manual growpart/resize2fs instructions for the
      normal path (only for pre-booted images, which skip init --
      modeenv trap). The remaining shrink levers are just the seed
      (gadget yaml PR) and measuring data's filesystem minimum.
- [ ] FDE caveat: with FDE the initramfs creates/encrypts ubuntu-data
      at install; re-verify the growth story on an FDE image before
      claiming anything for the encrypted path
- [ ] snapd layout validation: confirm snapd tolerates partitions
      smaller than the gadget declaration (or that we stay at/above
      the declared sizes) -- boot test is the arbiter

## 3. zstd-holes vs qcow2 for VMs (arguments, then decide)

Clarification first: plain decompression (zstd -d / gunzip) of the
artifact does NOT preserve holes -- the writer materialises every
byte (a 20G file). Hole-preserving paths are: bmaptool copy (writes
only mapped ranges -- verified 4.8 GiB), cp --sparse=always /
rsync -S / fallocate --dig-holes post-hoc, or qcow2 conversion.

- qcow2 PROS (as a VM artifact):
  - naturally thin: qemu-img convert -O qcow2 of the minimal image
    allocates only real content (~3-5G) -- no sparse-file confusion
  - grows on demand inside the VM; snapshots; backing chains (a dev
    base image + per-test overlays = fast test cycles)
  - VM-native: virt-manager / GNOME Boxes / multipass can consume it
    directly; no dd, no 20G sparse file on the user's disk
- qcow2 CONS:
  - not flashable to USB / not usable by the bmap installer (real
    hardware needs raw)
  - offline inspection needs qemu-nbd (nbd kernel module) vs plain
    losetup for raw
  - allocation-on-first-write performance overhead; fragmentation
- raw PROS: universal (dd/bmaptool/flashers), losetup-inspectable,
  zero overhead, the format the bmap installer already consumes
- raw CONS: apparent-vs-allocated confuses users and tooling; no
  snapshots; manual resizing
- [ ] measure: qemu-img convert the minimal image -> qcow2 size vs
      the raw; boot both in QEMU and compare first-boot time
- [ ] decide the artifact set. Sketch: pc.img.gz + .bmap (flasher +
      ISO installer) AND pc.qcow2 (VM users, naturally minimal) --
      both derived from one minimal source image. OR raw-only +
      instructions (simpler artifact story)

## 4. Expansion instructions (required if we ship minimal raw)

VERIFIED 2026-11-12 (test 3 above): device initialisation extends
ubuntu-data (partition AND filesystem) to fill the disk on the first
boot of a fresh never-booted image. So:

- [x] document for QEMU/dev: NOTHING NEEDED -- boot the image and
      first boot extends automatically; only pre-booted images (the
      modeenv trap) skip it
- [x] document for real hardware: device initialisation extends
      automatically on first boot (verified); keep a growpart +
      resize2fs note only for the pathological pre-booted-image case
- [x] "use all available space" confirmation: NOT needed -- the
      extension is implicit and automatic (verified)

## Work items

- [x] test 1: RESOLVED 2026-11-13 -- superseded by a better answer: the
      build output has NO ubuntu-data partition to shrink (2-partition
      seed-only image, see below), so the resize2fs sequence is moot.
      The minimal artifact is a post-build TRUNCATE: last-partition-end
      + 1MiB + sgdisk -e. Implemented as build.sh --minimal (commit
      df09628) and verified by booting the result.
- [x] test 2: MEASURED 2026-11-13 -- seed content 2.34 GiB (1.6G
      /snaps + 649M systems/<label>/snaps + 4.7M EFI); two full seeds
      (remodel worst case) 4.68 GiB -> PR proposes 5000M. resize2fs -M
      on data N/A (no data partition in the build output; snapd sizes
      it at first boot). ubuntu-image's internal minimum (where
      --image-size gets ignored): 10.94G (7000M seed), ~8.9G (5000M).
      Minimal artifact: 6.9G apparent (7000M) / 4.9G (5000M); 2.3G
      allocated, 2.08G zstd, bmap 594,32x mapped blocks in all cases.
- [x] test 3: DONE 2026-11-12 (see above) -- extension verified.
- [x] test 4: DONE 2026-11-13 -- qemu-img convert of the minimal image
      -> 2.27G file, 64G virtual after resize; boots to the desktop,
      first boot creates all partitions, data fills the disk. VM
      artifact = qcow2; minimal RAW is not directly bootable as a
      fixed-size VM disk (resize first).
- [x] gadget PR: DONE 2026-11-13 -- pc-amd64-gadget-desktop branch
      smaller-seed, PR #18: seed 7000M -> 5000M (amd64+arm64), with
      boot test of a 5000M-seed image on a 64G disk (all partitions
      created, data 58.4G, modeenv run, desktop). NEGATIVE proof that
      the declaration is authoritative: a 4.5G seed against the old
      7000M declaration boot-loops (initramfs fails to create the
      remaining partitions; grub "error: no such device: ubuntu-boot."
      once per cycle).
- [x] decide artifact set: minimal raw (pc.img from build.sh --minimal;
      works for the bmap installer AND dd/flashers, written to the
      START of any sufficiently large drive) + zstd + .bmap for the
      installer/flasher path; qcow2 (2.27G file, 64G virtual) for VM
      users; the 20G build remains the ready-to-run dev image for
      local boots. Final sizes with PR #18: 4.9G apparent / 2.3G
      allocated / 2.08G zstd.
- [x] write the expansion instructions: nothing needed (section 4
      above, verified).
- [x] update the bmap note (`20261111-installer-bmap-write-optimization.md`)
      + PR#95 parity note: DONE (both edited 2026-11-13).
- [x] FDE caveat: PARTIAL -- without a TPM the model's
      storage-safety: prefer-encrypted falls back to the unencrypted
      flow (verified: the FDE-labeled disk boots and installs like the
      plain image). WITH swtpm in QEMU the encrypted-path boot died
      silently after TPM measurement (TPM state written, no kernel
      serial output, no partitions created) -- needs dedicated
      debugging (swtpm/PCR setup or genuine-TPM hardware) before
      claiming the minimal-image story for the encrypted path.

## Resolution (2026-11-13)

THE ANSWER to "smallest image we can generate": the build output is a
SEED-ONLY image (BIOS Boot 1M + ubuntu-seed + GPT; --image-size 20G
padding is unwritten holes), and snapd's first-boot device
initialisation creates ubuntu-boot/save/data and extends ubuntu-data
to fill the disk. So:
- build.sh --minimal truncates natively to the two written partitions:
  6.9G apparent (7000M seed) or 4.9G (5000M seed, PR #18); 2.3G
  allocated / 2.08G zstd / ~2.44G install write in all cases -- the
  payload was already minimal.
- build.sh --image-size added (capped by ubuntu-image's minimum:
  10.94G / ~8.9G per seed size above).
- VM artifact: qcow2 from the minimal image, 2.27G file @ 64G virtual,
  boots to the desktop.
- Everything verified by boot tests: 7000M-seed minimal (via qcow2 and
  raw), 5000M-seed minimal (raw on 64G), and the negative
  seed<declaration boot loop. The full measurement/tooling/gotcha
  write-up was recorded in the project notes. build.sh commit df09628;
  gadget PR https://github.com/canonical/pc-amd64-gadget-desktop/pull/18
