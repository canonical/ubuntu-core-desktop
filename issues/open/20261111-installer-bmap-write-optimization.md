# Installer writes should use bmap block maps: 4.8 GiB not 21.5 GB

One-line root cause found; recommended fix is a small curtin MR plus a
one-command build-pipeline step.

## Impact / Priority

Every install writes the FULL image stream to the target — ~21.5 GB
including ~14G of padding/zeros the target does not need — where a
bmap-block-map write needs only the 4.8 GiB of allocated extents.
Install time scales with --image-size (a 50G image would write 50G);
the note calls the full-stream write "unacceptable for the product
installer".

Impact derived from the original note's described symptoms.

## background

The thin installer prototype (installer/ branch in
~/git/ucd-installer-iso, see its README) dd's the raw core image onto
the target via curtin. Measured during the first successful
end-to-end install (QEMU/UEFI, 64G target, KDE image):

    virtio0: wr 21.553 GB over 21135 ops

That is the FULL image stream written to the target, zeros included.
Install time is dominated by writing ~14G of padding/zeros that the
target does not need. This scales with --image-size: a 50G image
would write 50G. Unacceptable for the product installer.

## confirmed current behaviour

Root cause, exact location:

    curtin/commands/block_meta.py :: write_image_to_disk()

        util.subp(args=[
            'sh', '-c',
            fetch + extractor[source['type']] + ' | dd bs=4M of="$2"',
            '--', uri, devnode])

`dd bs=4M of="$2"` has no conv=sparse: every byte of the decompressed
stream is written, zero runs included. Verified empirically:

  - install blockstats: 21.553 GB written (matches full image size)
  - the dd layout comes from subiquity: for dd sources the storage
    controller emits {"layout": {"name": "dd", "match": {"path": ...}}}
    (subiquity/server/controllers/storage.py, dd_target / render())

Note this code path is shared with MAAS raw-image deployment, so the
fix benefits MAAS too.

## why not just conv=sparse

`dd bs=4M conv=sparse of="$2"` is a one-line fix and was validated on
our image: decompressing pc.img.xz with conv=sparse allocates 4.9G
instead of 21G. BUT conv=sparse changes the contract of the write:

  - it skips ALL-ZERO blocks, conflating "block contains zeros" with
    "block content does not matter". Regions the image author
    intended to be zero end up containing stale data from the target
    disk.
  - filesystems do not care (ext4/vfat free-space content is
    unspecified), but byte-exactness is lost, and on reinstalls
    stale data remains recoverable from free blocks.

ChromiumOS faced the same choice and requires the destination to be
zero-filled first (image_to_vm.sh documents this explicitly). Zeroing
the destination first is correct but expensive on slow media, and
blkdiscard only gives zero-readback on devices reporting RZAT/DRAT
(and not at all on USB HDDs).

## recommended fix: bmap block maps

bmaptool (yoctoproject/bmap-tools, packaged in Ubuntu) is a smarter
dd: a small .bmap sidecar lists exactly which block ranges of the
image contain data (allocated extents). Copies write only those
ranges. Unlike conv=sparse it is EXACT: allocated blocks containing
zeros are still written; only genuine holes (never written at build
time) are skipped. Every range carries a SHA256, so the installer
verifies the write as it goes.

Measured on our actual image (pc.img, KDE variant):

    pc.img:            21G apparent, 4.8G allocated (ubuntu-image
                       writes its output sparsely -- verified)
    bmap:              28 KB sidecar
    BlocksCount:       5,246,976 blocks  = 21.5 GB
    MappedBlocksCount: 1,254,196 blocks  =  4.8 GiB (23.9%)
    bmaptool copy:     51.6s, 94.9 MiB/s (to a local file, container)

4.5x less written, checksum-verified, and the ratio improves for
GNOME (less content) and does not degrade for larger --image-size
(padding is never mapped). bmaptool decompresses the .xz on the fly,
so the shipped artifact stays pc.img.xz + a 28 KB .bmap.

This is the standard embedded-Linux deployment flow (Yocto ships
image.wic.bz2 + image.wic.bmap for exactly this reason).

## proposed implementation

1. build pipeline: after ubuntu-image, run `bmaptool create pc.img`
   and ship pc.img.xz + pc.img.bmap. (ubuntu-image could grow a
   --bmap option upstream.)
2. curtin MR: write_image_to_disk() uses `bmaptool copy "$uri"
   --bmap "$bmap" "$devnode"` when a bmap accompanies the source,
   falling back to plain dd otherwise. The dd layout config gains an
   optional bmap path (subiquity passes it from the source catalog).
3. subiquity: the source catalog / dd layout carries the bmap
   reference (convention: same basename, .bmap suffix, like Yocto).
4. live env: bmap-tools must be present (small python package;
   check whether snapd's deps already pull it into the live image,
   else add it to the installer environment's packages).
5. contract: document "ranges not present in the bmap are
   unspecified on the target". Optionally blkdiscard the target
   first for hygiene/privacy on reinstall (near-instant on
   solid-state media; skip on devices without discard).

## caveats

- bmap skips holes, not zero-filled blocks: it only helps because
  ubuntu-image writes sparse output. If the build pipeline ever
  changes to allocate the full file, regenerate or the map covers
  everything. (Could assert: mapped% sanity-check in CI.)
- COMPRESSION IS MANDATORY FOR THE ISO (do not "optimise" it away):
  ISO9660 cannot represent sparse files, so an uncompressed pc.img
  in the ISO would materialise its ~15G of unwritten free space as
  zeros: a 20 GiB ISO instead of 4.5 GiB. The gzip/zstd saving comes
  almost entirely from those holes, NOT from the snap payload (the
  squashfs snaps are incompressible and pass through ~1:1; the data
  partition's preseeded snap copies likewise).
- decompression cost on the target: MEASURED (2026-11-12, full
  21.5G stream to /dev/null): zcat (gz) 8.6s, zstd -d 3.2s, raw cat
  3.0s. The format choice is a ROUNDING ERROR per install -- the
  zero runs decompress at memcpy speed in every format. bmap does
  the heavy lifting (21.5 GB -> 4.8 GiB written); do not add zstd
  support for install time. zstd is only marginally interesting for
  ISO size (4.4G vs 4.5G) -- not worth the stage-packages/base
  coupling. NOTE: if a future "download + write" flow uses bmaptool
  over HTTP (range requests), the artifact can be the RAW image +
  bmap with no compression at all: only mapped ranges are
  downloaded.
- FDE unaffected: with FDE the initramfs creates/encrypts
  ubuntu-data at install regardless of the dd shape; the bmap only
  changes how the image bytes reach the disk.

## related findings from the same session (context)

- modeenv burn-in trap: build.opt2/pc.img has modeenv mode=run /
  good_recovery_systems set -- the image file was booted during
  development, so its first-boot (device initialisation) is already
  burned in. Any dd of it skips install mode entirely; that is why
  our installed system showed no initialisation and kept the baked
  12.4G ubuntu-data. NEVER test installer flows with a reused image
  file; the payload must be a fresh CI-style build.
- snapd does not grow an EXISTING ubuntu-data: 21G image on a 64G
  disk installs with data at its baked size (12.4G), ~45G
  unallocated. The gadget declares ubuntu-data: 1G, and the docs
  state the data partition is "often minimally sized in the image
  but extended during device initialisation to use all the space
  available" -- i.e. the designed flow is a minimal fresh image
  whose data is extended at first boot. Verify extension on a fresh
  (never-booted) image; if it does not happen, the fallback is an
  install-device hook in the gadget (growpart + resize2fs).
- ubuntu-seed content is only 2.2G inside a 7G partition (gadget
  declares 7000M, sized for rollback headroom: UC keeps the
  previous recovery system). With bmap, partition padding costs
  nothing at install time, so oversized seed/boot are fine; shrink
  them only if artifact/download size ever matters (the xz already
  compresses the padding to nothing).

## artifact strategy (agreed)

- source of truth: the minimal, never-initialised image + .bmap,
  consumed by the ISO installer.
- the 20G ready-to-run dev image remains a dev convenience (the dev
  run flow burns its first boot anyway -- it is a consumable, never
  shipped).
- shipping a pre-expanded disk image artifact is optional; it can
  be derived from the minimal one (truncate + growpart + resize2fs)
  or dropped in favour of ISO-only.

## todos

- [x] LOCAL PROOF OF CONCEPT DONE (2026-11-12): the curtin bundled
      in the subiquity snap is patched (installer/patch_curtin_bmap.py)
      and shipped via a casper overlay layer; the ISO carries
      pc.img.gz + pc.img.gz.bmap. Verified end-to-end: install wrote
      7.47 GB (vs 21.5 GB full-dd), all 233 bmap range sha256 checks
      passed, the installed system booted to a serial login prompt.
      See ~/git/ucd-installer-iso installer/README.md.
- [x] artifact switched to zstd (commit a6c07d3): pc.img.zst +
      pc.img.zst.bmap, catalog type dd-zst:file, the patched writer
      streams with "zstd -d -c" (zstd is in the live env AND the
      subiquity snap ships the full zstd toolset usr/bin/zstd* --
      the snap is classic-confined so it sees the live env too;
      verified in the snap tree inside the ISO). zstd -1 builds the
      artifact in 27.8s; decompress of the 21.5G stream = 3.2s
      (vs 8.6s gz). dd-zst:file was recognized by subiquity/curtin
      in the verification install (the extract started).
- [x] ROOT CAUSE of the zstd install failure (2026-11-12, the
      current blocker): subiquity's Integrity controller aborts the
      install because CASPER'S MEDIUM MD5 CHECK FAILED
      (/run/casper-md5check.json, read by
      subiquity/server/controllers/integrity.py -- casper-md5check
      verifies every file in the medium's md5sum.txt). Local
      verification of the built ISO found THREE bad entries in our
      md5sum.txt:

        1. ./md5sum.txt lists itself with the hash of an EMPTY file
           (the shell redirect creates it before find runs) --
           d41d8cd98f00b204e9800998ecf8427e -- guaranteed mismatch.
        2. ./casper/efiboot.img and 3. ./casper/bios.img are listed
           but EXCLUDED from the ISO graft (xorriso -m, they are
           eltorito intermediates) -- "FAILED open or read".

      Fix in build-installer.sh: generate md5sum.txt excluding
      md5sum.txt, efiboot.img, bios.img:

        (cd "$ISO_STAGING" && find . -type f ! -name md5sum.txt \
         ! -name efiboot.img ! -name bios.img -print0 | \
         xargs -0 md5sum) > "$ISO_STAGING/md5sum.txt"

      (cd first so the entries are ./casper/... like casper expects).
      NOTE: the earlier full-dd (gz-era) install completed despite
      the same md5sum.txt bug -- the casper-md5check result likely
      raced the install or was skipped; do not rely on that.
      STATUS 2026-11-12: FIXED (commit b9154d5) and verified against
      the rebuilt ISO: all 18 entries pass, no excluded names. The
      next install run got PAST the Integrity check (no abort).
- [x] SECOND root cause of the zstd install failure (2026-11-12,
      found via the installer shell + serial dump of the curtin
      log): CURTIN'S util.sanitize_source() whitelist. It matches
      the source URI prefix against a hardcoded supported list
      (tgz, dd-tgz, dd-tbz, dd-txz, dd-tar, dd-bz2, dd-gz, dd-xz,
      dd-raw, fsimage, fsimage-layered) and DEFAULTS unknown
      prefixes to {'type': 'tgz', 'uri': <full uri>}. dd-zst was
      not in the list, so the source became type tgz; curtin
      extract only SKIPS types starting with dd- (source['type']
      .startswith('dd-') -> continue) and otherwise runs the
      generic wget pipeline -- hence "Resolving dd-zst (dd-zst)...
      failed: name resolution" and the install abort. dd-gz worked
      in the verified gz-era run ONLY because it happens to be
      whitelisted. Recognized dd-* sources are written by
      block-meta's write_image_to_disk() -- which is exactly the
      patched function (bmap branch sits before the extractor map
      lookup, so the bmap path needs only the whitelist; the
      dd-zst extractor-map entry is for the no-bmap fallback).
      FIX (commit 5cd5ac3): patch_curtin_bmap.py now also patches
      curtin/util.py (adds 'dd-zst' to the supported list,
      anchored on "'dd-gz', 'dd-xz', 'dd-raw',"); dry-run verified
      on a fresh snap extraction (py_compile OK).
- [x] FOURTH root cause (2026-11-12, the decisive one): the
      patched snap was never RUNNING at all. The installer layer
      pre-places the ORIGINAL subiquity snap at the RUNTIME path
      var/lib/snapd/snaps/ in addition to the seed path; the patch
      layer only shadowed seed/snaps/. snapd loop-mounts the
      runtime path, validates it against the seed assertions (the
      original matches -- it IS the asserted snap) and never reads
      our patched seed copy. Verified live in the VM: the union
      seed file is the patched snap (md5 e43dde90...), but
      /var/lib/snapd/snaps/ and /snap/subiquity/7403 were the
      ORIGINAL (f6d7e9f9..., dd-zst count 0). So BOTH curtin
      patches (bmap writer AND the sanitize_source whitelist)
      never executed -- the wget failure was the UNPATCHED curtin.
      Fix (commit 307e3d7): the patch layer now shadows
      var/lib/snapd/snaps/ as well.
- [x] FIFTH root cause (2026-11-12): the bmap branch
      BARE-RETURNED from write_image_to_disk(), discarding the
      return value meta_simple needs: rootdev =
      write_image_to_disk(...); mount rootdev /target. Symptom: the
      bmap write COMPLETED (all 233 ranges, 5137186816 bytes --
      blockstats 5.139 GB matched exactly), partprobe ran, then
      curtin crashed with "TypeError: expected str, bytes or
      os.PathLike object, not NoneType" at block_meta.py
      meta_simple's mount (rootdev=None). Fix (commit 641a179):
      the branch only skips the dd pipeline (_wrote_bmap flag
      wraps the dd subp call); the upstream tail (partprobe, 3x
      udevadm trigger/settle loop,
      block.get_root_device([devname], paths=["curtin",
      "system-data/var/lib/snapd", "snaps"])) runs for both paths.
      HISTORY CORRECTION: with the bare return present since
      1030aaa, NO TUI-driven install could have completed through
      the bmap path -- the earlier "end-to-end verified" runs
      completed via the dd fallback (21.5 GB), and the 7.47 GB /
      checksum / cmp evidence verified the WRITER alone (not the
      install flow). The zstd+bmap install pipeline is verified
      END-TO-END only after this fix.
- [x] THIRD issue found and fixed (2026-11-12): the PATCH LAYER
      CACHING. build-installer.sh built the patched-snap layer
      only if absent; staging persists across builds, so the
      previous ISO shipped the GZ-ERA layer (zcat writer, no
      dd-zst extractor entry) even though the patcher had been
      updated -- the zstd writer never reached the ISO. Fix (same
      commit): rebuild the layer when patch_curtin_bmap.py is
      newer (-nt) than the layer. LESSON (twice now): ANY change
      to build inputs (patcher, artifacts) must invalidate the
      staging cache, or verify the shipped ISO contents before
      trusting a rebuild.
- [x] NEXT STEP -- DONE (2026-11-12 16:3x): the zstd+bmap install
      is VERIFIED END-TO-END. Rebuilt ISO (8529c41d, 6.0G;
      pre-flight green: md5 all-pass, seed==runtime snap
      identical, util.py dd-zst=1, _wrote_bmap guard=3, helper=2,
      rootdev tail intact), fresh 64G VM, TUI drive: Integrity
      PASS -> dd-zst recognized -> bmap write 233 ranges /
      5137186816 bytes, all sha256 pass -> "Installation
      complete!" (total guest write 5.199 GB vs 21.5 GB full-dd =
      4.1x less data) -> ISO ejected via QMP -> reboot -> the
      installed system boots to "Ubuntu Core 26 ... core-desktop
      login:" on serial; partition layout on the installed disk
      verified with sfdisk --dump (bios 1M / seed 7G / boot 750M /
      save 32M / data 12.4G, data NOT extended -- expected: the
      source image is pre-initialised, modeenv burned in).
      Commits: b9154d5 (md5), 5cd5ac3 (sanitize_source), 307e3d7
      (runtime-path shadow), 641a179 (rootdev return). The
      clean-room desktop confirmation + the
      device-initialisation extension test still need a FRESH
      never-booted image (plain `build.sh --desktop gnome` -- see
      the correction at the extension-test todo below).
- [ ] file the curtin MR: bmap support in write_image_to_disk()
      (with fallback), cite the measurements above; note MAAS
      benefit. DEFERRED per the owner -- local verification
      first, MR not yet opened. Also MR 2 (separate): dd-zst
      entry in curtin's extractor map (dd-gz/dd-xz/dd-bz2 exist;
      dd-zst is missing upstream).
- [ ] bmaptool create step in the image build pipeline (+ CI
      assert that mapped% stays sane) -- currently done in the
      installer build (build-installer.sh); move into the
      canonical image build when the pipeline settles
- [ ] subiquity: plumb the bmap path through the source catalog /
      dd layout config (current hack: <image>.bmap filename
      convention resolved inside the patched curtin)
- [ ] ensure bmap-tools is present in the installer environment
      (N/A for the current hack: the patch streams zstd + writes
      ranges in python, stdlib only)
- [x] verify device-initialisation extension on a FRESH image:
      DONE (2026-11-12 23:5x) -- THE DECISIVE ANSWER: YES, IT
      EXTENDS. The owner built a fresh never-booted image
      (build/pc.img, 21G apparent, 2.3G allocated, mtime
      2026-11-12 23:23). Installed via the zstd+bmap ISO (total
      guest write 2.436 GB = exactly the 594316-block bmap; ~40s
      write phase), rebooted, first boot ran device
      initialisation (snapd seeding ~4 min), then the serial
      login appeared. Logged in as your_username: lsblk shows
      ubuntu-data EXTENDED 12.4G -> 56.4G (filling the 64G disk),
      df confirms the ext4 was resized too (/dev/vda5 56G, 6.4G
      used), modeenv mode=run with recovery system 20261112.
      CONSEQUENCE: minimal images are SAFE -- ship a small
      ubuntu-data, device initialisation claims the rest of the
      disk on first boot. No gadget install-device hook needed,
      no growpart/resize2fs instructions needed for the normal
      path. See `20261112-investigate-smaller-image-size.md`
      test 3.
      CONTEXT: at the time of the original note, no --image-size
      flag existed on build.sh (the 20G was hardcoded at build.sh's
      ubuntu-image call; an unknown flag makes build.sh exit "Unknown
      flag") -- the
      fresh 20G image was enough for the test; building SMALL
      images natively (the smaller-size note) needs a temporary
      local edit of that line or a real --image-size flag (small
      upstreamable improvement). /input in the build container
      is a READONLY bind of the build dir -- a different image
      goes to /root/newimg/ via lxc file push.
      HARDWARE GOTCHA (2026-11-12 23:32): lxc file push does NOT
      preserve sparseness -- the pushed pc.img materialized to
      21G dense in the container, and bmaptool create mapped
      5246976 blocks (~20 GiB/install -- the optimization
      silently dead). FIX in the container: "fallocate
      --dig-holes <img>" (content unchanged, md5 identical,
      allocation back to 2.3G), then regenerate the bmap. The
      artifact pc.img.zst was never affected (zstd compresses
      zeros either way; 2.1G for this image). Bind mounts (like
      /input) DO preserve sparseness.
- [ ] decide blkdiscard-before-write (hygiene on reinstall)
- [x] optionally: gadget PR shrinking ubuntu-seed 7000M ->
      5000M: DONE (2026-11-13, branch smaller-seed in
      pc-amd64-gadget-desktop, both amd64+arm64 yamls). Seed
      content measured 2.34 GiB (1.6G shared snaps + 649M
      per-system snaps + EFI); 5000M holds a worst-case
      full-seed remodel duplication (4.68 GiB). The PR is NOT
      hygiene-only anymore: the build-time image carries only
      BIOS Boot + ubuntu-seed (boot/save/data are created on
      first boot, verified), so the seed declaration sets the
      minimum image size. See
      `20261112-investigate-smaller-image-size.md` (which has
      the full measurements and the seed<declaration boot-loop
      proof). Install time is already solved by bmap
      (unchanged: the mapped block count is identical for the
      minimal image).
- [ ] update installer/README + the PR#95 parity note once
      landed

## verification state at compaction (2026-11-12 ~15:30)

- the md5-fixed ISO (b8aa16a6...) passed the Integrity check but
  the install STILL aborted: curtin wget'd the dd-zst URI
  (sanitize_source whitelist, see above). Its VM died at the
  "problem completing the installation" dialog; both root causes
  are now fixed (b9154d5, 5cd5ac3) and a rebuild with BOTH
  patches is in flight.
- debugging technique that worked: installer shell (TUI Help menu
  -> Enter shell), then type commands IN SMALL CHUNKS (qmp
  send-key drops keystrokes on long batches) writing to
  /dev/ttyS0, read via serial.log on the host. Key files in the
  live env: /var/log/installer/curtin-install.log,
  subiquity-traceback.txt, curtin-errors.tar.
- the harness: a QEMU-driven VM, the drive helper
  installer/test/qmp-drive.py, the TUI flow: language Enter ->
  storage Tab+Enter -> confirm down+Enter.
- worktree: ~/git/ucd-installer-iso branch installer-iso; the
  patcher regex cleanup (no-backslash) is UNCOMMITTED -- commit
  it.
