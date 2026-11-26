# Does snapcraft's built-in dedup cover the dropped manual cleanup parts?

Date: 2026-11-10

Mode: investigation only (nothing posted to GitHub/Launchpad) for the
core24 -> core26 desktop snap migration.

## Impact / Priority

The core24 -> core26 desktop snap migration dropped the manual
`cleanup` parts, betting on snapcraft's automatic deduplication; if
that bet were wrong, consumer snaps would ship conflicting or wasted
libraries against the base/content snaps. The investigation found the
automatic mechanisms real and the outcome better than expected, with
two concrete, narrow gaps that do materialize in our set (one in
thunderbird) plus one pure-waste artifact.

Impact derived from the original note's symptoms.

## 0. Executive summary / verdict

Aleasto's comment is RIGHT IN SPIRIT but incomplete in detail, and the
practical outcome for our snaps is better than his caveat suggests -
with two concrete, narrow gaps that do materialize in our set (one of
them in thunderbird).

What he said (ubuntu/thunderbird PR #70, 2026-11-10):

> "Snapcraft itself already tries to do remove duplicates of the base
> snap itself, and I think we should be able to rely on that. Although
> I believe the current implemention only filters out duplicate
> libraries originating from deb packages staged as recursive
> dependencies of `stage-packages`, so it might not be exactly the
> same as this manual cleanup part. If you find any concerns I'd
> encourage raising it in snapcraft itself."

Verified facts:

  1. He correctly describes the craft-parts base filter: it filters
     stage-packages by NAME against the BASE snap's package manifest,
     and it deliberately exempts explicitly-listed stage-packages.
     Recursive dependencies of stage-packages are what get filtered.
  2. What his comment (and the review thread) did not mention: since
     snapcraft 9.x the GNOME extension ITSELF injects a
     `gnome/cleanup` part for base >= core26 which removes from prime
     every `*.so`/`*.so.*` whose relative path exists in
     `gnome-core26-sdk` or `gtk-common-themes`
     (snapcraft/extensions/gnome.py:381-397). The GPU extension
     injects the analogous `gpu/cleanup` part running
     `gpu-2604-cleanup mesa-2604`. Aleasto authored that extension
     change himself (commit c05aed0c1, "feat(extensions): add core26
     support to the gnome extension (#6278)", 2026-10-01). So
     content-snap dedup IS automatic on core26; the reviewer who
     asked "is it safe to remove the core26 logic?" was pointing at
     the documented mechanism (docs "Library cleanup" section), and
     it is real.
  3. Empirically (built snaps inspected), the mechanism works: our
     core26 snaps are tiny (gedit 6 MB, eog 5 MB) and contain none of
     the GNOME runtime's libraries.

Two real gaps vs. the old manual cleanup parts, plus one pure-waste
artifact (GAP C):

  GAP A (base snap): files that reach prime via EXPLICITLY-LISTED
     stage-packages (or part build outputs) are never deduplicated
     against the base. The old manual cleanup removed those (its find
     loop included the base). Materialized example: thunderbird now
     ships liblz4 (liblz4.so.1 + liblz4.so.1.10.0) even though core26
     provides the byte-identical liblz4.so.1.10.0 - wasted space
     today, and a stale-shadow hazard after a future base security
     update of lz4.
  GAP B (content snap vs SDK proxy): `gnome/cleanup` matches against
     the SDK snap, but gnome-core26 (the content snap) is a superset
     of the SDK for libraries: it additionally stages deb-only
     packages (libgoa-1.0-0b, libicu78, libcanberra-gtk3-module,
     ibus/fcitx GTK3 modules, gstreamer plugin sets and their deps).
     App copies of THOSE libraries are not removed and shadow the
     content snap's copies at runtime (the snap's own dirs precede
     $SNAP/gnome-platform in LD_LIBRARY_PATH).
     Materialized example: gnome-contacts ships libgoa-1.0.so.0 +
     libgoa-1.0.so.0.0.0 although gnome-core26 provides libgoa-1.0-0b;
     the recipe comment even says "runtime lib comes from
     gnome-core26".

  GAP C (waste, not harm): recursive-deb copies of libraries whose
     build version differs from the SDK's source-built version
     survive as ORPHANS (soname symlink removed because its path
     exists in the SDK; real file kept because its versioned filename
     differs, e.g. archive cairo 1.18.4 vs SDK-built cairo 1.18.6).
     Nothing loads them at runtime (the soname resolves into
     $SNAP/gnome-platform), but they waste ~43 MB across our set and
     are confusing.

Answer to "did we drop a cleanup part somewhere we shouldn't have?":

  No snap in the set ships a *loaded*, conflicting library version
  versus the content snaps (no same-soname-different-build pair that
  actually resolves to the snap's copy was found - details in section
  3; gnome-core26 comparison data appended). The only
  regression-vs-core24 found is thunderbird's liblz4 duplicate of the
  BASE (byte-identical today), which is wasteful and a
  future-staleness hazard, not a current conflict.

(Sections 1-5 below contain the full evidence.)

## 1. The exact mechanisms (code-level)

### 1.1 Base-snap dedup: craft-parts stage-package filtering (aleasto)

Location: craft-parts 2.37.2 as shipped in snapcraft 9.2.1

    /snap/snapcraft/current/lib/python3.12/site-packages/craft_parts/packages/deb.py

  - deb.py:316-331  _get_filtered_stage_package_names():

        def _get_filtered_stage_package_names(
            *,
            base: str,
            package_list: list[DebPackage],
            base_package_names: set[str] | None,
        ) -> set[str]:
            """Get filtered packages by name only - no version or architectures."""
            if base_package_names:
                filtered_packages = base_package_names
            else:
                manifest_packages = {p.name for p in get_packages_in_base(base=base)}
                ignored_packages = _IGNORE_FILTERS.get(base, set())
                filtered_packages = manifest_packages - ignored_packages

            stage_packages = {p.name for p in package_list}

            return filtered_packages - stage_packages

    NOTE the last line: the base's package set MINUS the explicitly
    requested stage-packages. Explicitly-listed stage-packages are
    therefore EXEMPT from base filtering - exactly what aleasto said
    ("only ... recursive dependencies of stage-packages").

  - deb.py:865-918  DebPackage._fetch_stage_debs(): applies the filter
    at the apt-mark level:

        filtered_names = _get_filtered_stage_package_names(
            base=base,
            package_list=[DebPackage.from_unparsed(name) for name in package_names],
            base_package_names=cls.stage_packages_filters,
        )
        ...
        with AptCache(stage_cache=stage_cache_dir, stage_cache_arch=arch) as apt_cache:
            apt_cache.mark_packages(set(package_names))      # explicit + recursive deps
            apt_cache.unmark_packages(filtered_names)        # drop the ones in the base
            for pkg_name, pkg_version, dl_path in apt_cache.fetch_archives(...)

  - apt_cache.py:348-390  unmark_packages(): also never filters
    packages whose candidate has apt Priority "essential" (mark_keep
    instead), then runs _autokeep_packages() to drop auto-deps that
    are no longer needed.

  - deb.py:423-445  get_packages_in_base(): what "the base" means per
    base:

      * core18-      : hard-coded list
      * core20/22/24 : /snap/<base>/current/usr/share/snappy/dpkg.list
      * core26+      : /snap/<base>/current/var/lib/chisel/manifest.wall
                       (chisel NDJSON manifest; verified present in
                       core26 rev 750, 230 packages)

    Verified contents of core26's manifest include libglib2.0-0t64,
    libstdc++6, libgcc-s1, libdbus-1-3, libfreetype6, ... but NOT
    cairo/pango/atk/gtk/icu.

  - deb.py:844-846: if the requested stage-packages are chisel SLICES
    (`pkg_slice` syntax, deb_utils.has_slices), the whole filter is
    bypassed:

        if deb_utils.has_slices(package_names):
            return package_names

Scope of mechanism 1.1 (summary):

  * provider considered: BASE only (name-level manifest match)
  * origins considered: deb stage-packages only, and only those
    pulled in as recursive dependencies; explicitly-listed
    stage-packages are exempt
  * file origins NOT considered: build-packages, part build/override
    outputs, organize/copy artifacts
  * granularity: whole-package (deb) names, not files; no version
    comparison
  * applies at fetch/unpack time; nothing later removes base-duplicate
    files from prime

### 1.2 Content-snap dedup on core26: the GNOME extension's `gnome/cleanup` part

Location: snapcraft 9.2.1

    /snap/snapcraft/current/lib/python3.12/site-packages/snapcraft/extensions/gnome.py:381-397

(identical in the upstream checkout ~/git/snapcraft; introduced by
commit c05aed0c1 - PR #6278, authored by Alessandro Astone,
2026-10-01)

        if base >= 26:
            cleanup_srcs = [
                self.gnome_snaps.sdk,        # -> "gnome-core26-sdk" by default
                "gtk-common-themes",
            ]
            escaped_srcs = [f'"{w}"' for w in cleanup_srcs]
            parts["gnome/cleanup"] = {
                "after": list(self.yaml_data.get("parts", {}).keys()),
                "plugin": "nil",
                "build-snaps": cleanup_srcs,
                "override-prime": (
                    "set -eux\n"
                    f"for snap in {' '.join(escaped_srcs)}; do\n"
                    '    cd "/snap/$snap/current" && find . -type f,l \\( -name "*.so.*" -o -name "*.so" \\) -exec rm -f "$CRAFT_PRIME/{}" \\;\n'
                    "done\n"
                ),
            }

  Semantics: for every regular file or symlink under
  /snap/<provider>/current whose name matches `*.so` or `*.so.*`,
  delete $CRAFT_PRIME/<same relative path>. Pure PATH matching - no
  SONAME or content comparison.

  Scope:

  * providers: gnome-core26-sdk (the SDK/build snap, used as a PROXY
    for the gnome-core26 content snap) and gtk-common-themes
  * gtk-common-themes contains ZERO .so files (verified: it is
    themes/icons/sounds only), so that leg is a no-op for libraries
    (it mattered only in the pre-core22 world)
  * the BASE (core26) is NOT among the cleanup sources
  * mesa-2604 is NOT here - it has its own mechanism (1.3)
  * the content snap's deb-only libraries that the SDK lacks are NOT
    covered (this is GAP B; materialized in 3.2, runtime impact in
    1.5)

  Relationship SDK vs content snap (from the gnome-sdk repo, branch
  gnome-core26): gnome-core26 is BUILT FROM gnome-core26-sdk
  (`stage-snaps: [gnome-core26-sdk/latest/candidate]`, gnome-sdk
  snap/snapcraft.yaml:36-40) plus a `debs` part (stage-packages incl.
  libgoa-1.0-0b, libicu78, libcanberra-gtk3-module, ibus-gtk3,
  fcitx5-frontend-gtk3, gstreamer1.0-plugins-{base,good,extra}, ...)
  minus dev files (headers, `*.so` dev symlinks, .a, .pc, includes are
  removed). => for library files, gnome-core26-sdk is (almost) a
  subset of gnome-core26; the content snap's deb-only libs are the
  exception (GAP B).

### 1.3 mesa-2604 dedup: the GPU extension's `gpu/cleanup` part

  snapcraft/extensions/gpu_extension.py:185-204 (core26 branch):

        "gpu/cleanup": {
            "after": list(self.yaml_data.get("parts", {}).keys()),
            "source": "https://github.com/canonical/gpu-snap.git",
            "plugin": "nil",
            "override-prime": (
                "craftctl default\n"
                "${CRAFT_PART_SRC}/bin/gpu-2604-cleanup mesa-2604\n"
            ),
        }

  gpu-snap bin/gpu-2604-cleanup deletes $CRAFT_PRIME/<path> for every
  path in lists/mesa-2604.<arch>.list (maintained list; includes globs
  for dri/, libVkLayer_*, libdrm_*, libgallium-*, vdpau/, etc.).
  List-based rather than scan-based, covers all file types listed
  there.

### 1.4 What the dropped MANUAL cleanup parts did (for comparison)

  Typical form (e.g. ubuntu/thunderbird PR #70 diff - the removed
  part):

    cleanup:
      after: [thunderbird]
      plugin: nil
      build-snaps: [core26, gnome-core26]
      override-prime: |
        set -eux
        for snap in "core26" "gnome-core26"; do
          cd "/snap/$snap/current" && find . -type f,l -exec rm -f "$CRAFT_PRIME/{}" \;
        done

  Other snaps' variants filtered `-name *.so.*` and included
  gtk-common-themes (per the migration project's recipes). Note
  thunderbird's variant had NO `-name` filter at all: it removed EVERY
  file (any type) whose path existed in the base or the content snap.

  Coverage of the manual parts that the automatic mechanisms do NOT
  reproduce:

    * the BASE as a file-level provider (mechanism 1.1 is name-level
      and exempts explicit stage-packages and part outputs)  -> GAP A
    * the CONTENT snap's deb-only libraries not present in the SDK
      -> GAP B

  Coverage the automatic mechanisms ADD over the manual parts:

    * `*.so` (dev symlinks) in addition to `*.so.*`
    * mesa-2604 (many manual parts never covered mesa at all)
    * it is maintained centrally and runs for every gnome-extension
      snap

### 1.5 Runtime shadowing direction (why duplicates matter)

  The app's own library dirs come FIRST in LD_LIBRARY_PATH; the
  content snap's dirs are APPENDED afterwards by the desktop-launch
  chain:

  - snapcraft extensions/desktop/command-chain/desktop-launch:
        execs $SNAP/gnome-platform/command-chain/desktop-launch
  - snapcraft-desktop-integration gnome/desktop-exports:17-24
        function append_dir() { ... export "${!var}=${var:+$var:}${dir}"; }
    and :73-76
        append_dir LD_LIBRARY_PATH "$SNAP_DESKTOP_RUNTIME/lib/$ARCH"
        append_dir LD_LIBRARY_PATH "$SNAP_DESKTOP_RUNTIME/usr/lib/$ARCH"
        append_dir LD_LIBRARY_PATH "$SNAP_DESKTOP_RUNTIME/usr/lib"
        append_dir LD_LIBRARY_PATH "$SNAP_DESKTOP_RUNTIME/lib"

  => search order: $SNAP/lib{,/$TRIPLET} and $SNAP/usr/lib{,/$TRIPLET}
     (set by snapd) -> $SNAP/gnome-platform/{lib,usr/lib...} -> base
     default paths. I.e. the snap's own copy shadows the content
     snap's copy, and the content snap shadows the base.
     Same-soname-different-build leftovers in prime ARE the ones that
     get loaded. (This is exactly the failure mode the published docs
     warn about - see 1.6.)

### 1.6 The documentation claims (which we relied on)

  * Migration guide:

        https://documentation.ubuntu.com/snapcraft/latest/how-to/change-bases/change-from-core24-to-core26/

    (section "GNOME extension"):

      "On core26, the extension also adds automatic library cleanup,
       which removes bundled libraries provided by the content snaps.
       If your snap was relying on a different version of a GNOME
       library that is also provided in the GNOME content snap, it
       will no longer be allowed to do so under the same library
       SONAME."

  * GNOME extension reference:

        https://documentation.ubuntu.com/snapcraft/latest/reference/extensions/gnome-extension/

    section "Library cleanup" (anchor #library-cleanup, the one
    quoted in the PR thread):

      "On core26, the extension adds a `gnome/cleanup` part that runs
       after the project's parts. During the prime step, it removes
       shared libraries from the prime directory that are already
       supplied by the GNOME content snaps or gtk-common-themes snap.
       ... This cleanup prevents bundled libraries from overriding
       the content snap's libraries."

  Both claims match the code. The docs do NOT mention that (a) the
  base is handled only by the name-level stage-package filter with
  its explicit-list exemption, nor that (b) the content snap is
  proxied by the SDK and its deb-only libraries escape the cleanup.

## 2. Empirical check - mechanisms ran (snap contents)

Method: unsquashfs of every built snap in
~/git/snaps-core26-update/launchpad/{...} and
~/git/snaps-core26-update/github/{...} (all ~24 snaps), inventory of
usr/lib/**/*.so* (+ all files for the base comparison), providers
unsquashed from `snap download` (core26 rev 750, gtk-common-themes
rev 1535, gnome-core26 rev 33). Scratch work in a throwaway directory
(host untouched otherwise).

### 2.1 The cleanup demonstrably ran in the built snaps

  * gedit prime: 28 .so files, all either gedit's own built libs
    (libgedit-amtk/gfls/gtksourceview/tepl, plugins) or the
    deliberately staged libpeas/libuchardet (the recipes' comments
    document that gnome-core26 does not ship libpeas). No
    GTK/GLib/cairo/pango at all.
  * eog prime: 13 .so files (eog's own + libpeas + libexif/libexempi,
    all documented as not shipped by gnome-core26).
  * cheese prime: clutter/cogl stack (recipe comment: "clutter stack
    is not in the gnome-core26 content snap either") plus leftovers
    analysed in 3.2.
  * soname symlinks of SDK-provided libraries are ABSENT while the
    versioned real files may remain (e.g. cheese has
    libcairo.so.2.11804.4 but no libcairo.so.2) - the fingerprint of
    `gnome/cleanup`'s path matching.
  * zero prime .so paths overlap the core26 base in gedit/eog/cheese/
    gnome-contacts (the recursive-deb base filter works).

### 2.2 Provider facts

  * gtk-common-themes rev 1535: 0 files matching *.so / *.so.*  =>
    including it in the old manual loops was already a no-op for
    libraries.
  * core26 rev 750 (chiselled): 230 packages in
    var/lib/chisel/manifest.wall, 271 usr/lib .so files incl.
    libglib-2.0.so.0.8800.0, libstdc++.so.6.0.35, liblz4.so.1.10.0,
    libgcrypt.so.20.7.0, libdbus-1.so.3.38.3, libfreetype.so.6.20.5,
    ... Manifest includes libglib2.0-0t64, liblz4-1, liblzma5,
    libgcrypt20, libudev1, libstdc++6, libgcc-s1, libdbus-1-3,
    libfreetype6; NOT cairo/pango/atk/gtk/icu.
  * gnome-core26 rev 33: 1397 .so files, 1.3 GB unpacked. Runtime-lib
    set = gnome-core26-sdk (source-built GNOME stack: cairo 1.18.6,
    pango 1.58.2, gtk3+gtk4, librsvg 2.63.2, ...) plus deb-only
    libraries staged by the content snap that the SDK lacks:
    libgoa-1.0-0b, libicu78 (78.2), libcanberra-gtk3, libibus-1.0,
    gtk3 immodules (im-ibus, im-fcitx5, ...), gstreamer plugin
    packages, fonts, caches. Verified: no rav1e/codec2/dav1d in
    gnome-core26 (firefox's codec stack is genuinely its own).

## 3. Empirical check - duplicates per snap (representative four + full set)

Providers used for comparison: core26 rev 750 (sha3-384-verified
store download), gtk-common-themes rev 1535, gnome-core26 rev 33
(sha3-384 a4940f5b...95e1, verified). All 24 built snaps unsquashed
and inventoried.

### 3.1 Path overlap with the BASE (core26 rev 750) - across ALL 24 snaps

  * gedit, eog, cheese, gnome-contacts: 0 overlapping .so paths at
    all.
  * thunderbird: 2 lib files -

        usr/lib/x86_64-linux-gnu/liblz4.so.1.10.0  (real file, sha256
          IDENTICAL to core26's liblz4.so.1.10.0)
        usr/lib/x86_64-linux-gnu/liblz4.so.1       (soname symlink)

    Why: `liblz4-1` is an EXPLICITLY-LISTED stage-package of the
    `thunderbird-staged` part (snapcraft.yaml, "thunderbird-staged"),
    and explicitly-listed stage-packages are exempt from the base
    filter (deb.py:332 `filtered_packages - stage_packages`); the
    base is not among gnome/cleanup's sources. liblz4-1 IS in
    core26's chisel manifest (230 packages; verified), so it would
    have been filtered if it had only been a recursive dependency.
    The dropped manual cleanup part WOULD have removed it
    (thunderbird's variant had no -name filter and included core26).
    => GAP A materialized: ~150 KB waste today; stale-shadow hazard
    when the base gets a lz4 security update and this snap is not
    rebuilt. Also 7 byte-identical /usr/share/doc/*/copyright files
    (liblz4-1, liblzma5, libgcrypt20, libudev1, libuuid1, libblkid1,
    libgpg-error0) and meta/snap.yaml (expected to differ).
  * snap-tpmctl: usr/bin/systemd-cryptsetup exists in the base with
    DIFFERENT content - but snap-tpmctl never had a cleanup part (git
    history checked) and deliberately primes the file, so this is
    pre-existing GAP-A-class behavior, not a migration regression.
  * everything else: only meta/snap.yaml overlaps (expected).

### 3.2 Path overlap with gnome-core26 (rev 33) - across ALL 24 snaps

  * gnome-contacts only:

        usr/lib/x86_64-linux-gnu/libgoa-1.0.so.0       (link) - same
          path in gnome-core26 (content snap stages libgoa-1.0-0b;
          the SDK does NOT have goa at all - no goa part, no goa deb
          in gnome-core26-sdk)
        usr/lib/x86_64-linux-gnu/libgoa-1.0.so.0.0.0   (real file) -
          sha256 IDENTICAL to gnome-core26's copy (same 26.04
          archive deb).

    Why: gnome/cleanup matches against gnome-core26-SDK, which lacks
    goa; the content snap's deb-only libraries escape the cleanup =>
    GAP B materialized. Impact today: 0.3 MB pure waste; the hazard
    is the same stale-shadow class as 3.1 if the content snap's goa
    is ever rebuilt without this snap being rebuilt. The
    gnome-contacts recipe comment even documents the intent:
    "gnome-online-accounts integration (runtime lib comes from
    gnome-core26; only the build dependency was missing)" - in fact
    the snap's own copy shadows gnome-core26's at runtime.
  * no other snap ships any file whose path exists in gnome-core26.

### 3.3 Same-SONAME-different-CONTENT cases that would be LOADED at runtime

  NONE. In the whole set there is no prime file that (a) resolves to
  a soname provided by core26 or gnome-core26 and (b) has different
  content from the provider's copy. The only same-soname overlaps
  found (thunderbird liblz4 vs base, gnome-contacts libgoa vs
  gnome-core26) are byte-identical.

### 3.4 "Orphan" leftovers - version-skew duplicates that are NOT loaded

  Mechanism: a recursive-deb library copy whose soname-symlink path
  exists in the SDK gets its symlink removed by gnome/cleanup, but
  its real file has a different ABI-version filename than the SDK's
  source-built copy, so the real file survives. At runtime nothing
  loads it: the soname resolves through $SNAP dirs (symlink absent)
  into $SNAP/gnome-platform (newer SDK-built version). Pure waste, no
  shadowing.

  Version table (snap's orphaned archive copy vs gnome-core26 rev
  33's SDK-built copy; real filenames verified on both sides -
  upstream versions decoded from libtool filenames where
  unambiguous):

    library         snap ships (26.04 archive)   gnome-core26 has
    libcairo        libcairo.so.2.11804.4         libcairo.so.2.11806.6
    libpango-1.0    …so.0.5700.0                  …so.0.5800.2
    libgtk-4        …so.1.2200.4                  …so.1.2400.0
    librsvg-2       …so.2.61.3                    …so.2.63.2
    libsoup-3.0     …so.0.7.4                     …so.0.7.3
    libpsl          …so.5.3.4                     …so.5.3.8
    libgdk_pixbuf   …so.0.4400.5                  …so.0.4400.8
    libfontconfig   …so.1.16.1                    …so.1.17.0
    libatk-1.0      …so.0.26013.1                 …so.0.26209.1
    libharfbuzz     …so.0.61232.0                 …so.0.61450.0
    libgweather-4   …so.0.400.4                   …so.0.600.0

  Per-snap orphan waste (real files under usr/lib/x86_64-linux-gnu
  only; uncompressed on-disk sizes in prime):

    cheese           10 files   9.21 MB  (cairo x2, pango x3, atk,
                                          harfbuzz, gdk-pixbuf,
                                          fontconfig, rsvg)
    gnome-clocks     11 files   9.74 MB  (same set + psl + soup)
    gnome-contacts   17 files  22.86 MB  (same set + gtk4 [11.5 MB],
                                          gweather, harfbuzz-icu/
                                          subset,
                                          cairo-script-interpreter)
    simple-scan       2 files   0.40 MB  (fontconfig, psl)
    thunderbird       2 files   0.69 MB  (psl, soup)
    firefox           0         (its 9 family-matching files live
                                  under usr/lib/firefox/ -
                                  deliberately bundled private
                                  NSS/NSPR with rpath;
                                  path-distinct from
                                  gnome-core26's
                                  /usr/lib/x86_64…/libnss3, so
                                  neither the old nor the new
                                  cleanup ever removed them)
    others            0
    ---------------------------------------------
    TOTAL            42 files ~42.9 MB across the set

### 3.5 Libraries neither core26 nor gnome-core26 provides

  Correct, no dedup possible:

  clutter/cogl stack + libcheese (cheese - recipe documents the
  clutter stack is not in gnome-core26), EDS/folks/abseil/
  libphonenumber/qrencode stack (gnome-contacts, 262 files),
  libpeas/libuchardet (gedit, eog - documented as not shipped by
  gnome-core26), libexif/libexempi (eog), avahi-glib/geoclue/
  modemmanager (gnome-clocks), gstreamer codec set incl. rav1e/
  codec2/dav1d/x264 (firefox - gnome-core26 does not provide those
  families; verified), thunderbird's private usr/lib/thunderbird/*
  libs, opensc-pkcs11 (thunderbird/firefox - not in gnome-core26;
  thunderbird's layout bind-file for opensc-pkcs11.so therefore
  still resolves), sane stack (simple-scan, 336 files), Flutter
  plugin libs under bin/lib (snap-store, desktop-security-center),
  Go binaries' libs (authd, udp-*, snap-tpmctl: zero .so files at
  all).

## 4. Verdict on aleasto's statement

  * "Snapcraft itself already tries to remove duplicates of the base
    snap itself" - TRUE (craft-parts stage-package filtering, 1.1),
    and on core26 the base manifest source is the chisel manifest.
  * "the current implementation only filters out duplicate libraries
    originating from deb packages staged as recursive dependencies of
    stage-packages" - TRUE and precisely so (explicit stage-packages
    are exempt by `filtered_packages - stage_packages`; part outputs
    and build-packages are never considered; chisel-slice
    stage-packages bypass the filter entirely; Priority:essential
    packages are never unmarked).
  * What the comment omits (and what makes the overall conclusion
    still correct for our snaps): the GNOME/GPU extensions ALSO
    inject the file-level `gnome/cleanup` / `gpu/cleanup` parts on
    core26 - that is the "automatic library cleanup" the migration
    doc referenced, and it covers the content-snap side (via the SDK
    proxy) which his base-dedup mechanism does not. He knows this
    code (he authored it), but the thread's reasoning ("we can rely
    on snapcraft's own dedup") conflates the two mechanisms; the
    safe answer is "both run automatically on core26".
  * Overall: RIGHT IN SPIRIT, and the conclusion (dropping the manual
    cleanup parts is acceptable) holds for our set - with GAP A and
    GAP B as real, narrow regressions worth an upstream issue.

## 5. Snaps needing action

  * NO snap in the set ships a LOADED library that conflicts with a
    different build of the same soname provided by core26 or
    gnome-core26 (sections 3.1-3.3: the only same-soname overlaps are
    byte-identical copies). Nothing needs an urgent rebuild or
    revert; dropping the cleanup parts did not break library dedup
    for any of the 24 snaps.
  * Optional per-snap cleanups, in priority order:

    1. thunderbird: `liblz4-1` (explicit stage-package, duplicate of
       the byte-identical base copy; will stale-shadow the base's
       fixed lz4 after a future base security update). Audit the
       other explicit stage-packages of `thunderbird-staged` for
       base membership (libgcrypt20/libudev1/libuuid1/zlib1g/
       libblkid1/liblzma5 are all in the base manifest too - their
       .so files are currently cleaned only because
       gnome-core26-sdk happens to stage them as well; that is
       GAP-B-class fragility, one SDK change away from regressing).
    2. gnome-contacts: `libgoa` shadow of gnome-core26's copy
       (byte-identical today = pure 0.3 MB waste).
    3. Orphan waste (~42.9 MB across the set, section 3.4) - the
       proper fix is upstream (snapcraft issue drafted in section
       6), not per-snap.

  * Not a migration regression: snap-tpmctl's
    usr/bin/systemd-cryptsetup (pre-existing; that snap never had a
    cleanup part).

## 6. Draft snapcraft issue (DO NOT POST - for review first)

Proposed title:

  Base-dedup skips explicitly-listed stage-packages, and
  gnome/cleanup proxies the content snap with the SDK, so
  provider-provided files leak into prime

Proposed labels: bug, gnome-extension

Proposed repo: canonical/snapcraft (partly craft-parts; can be split)

---- draft body ----

Snapcraft 9.2.1 (craft-parts 2.37.2), base: core26, GNOME extension.

### Summary

Two gaps remain between what the classic manual `cleanup` part
removed and what the automatic mechanisms remove today. Both leak
provider-provided files into the prime of consumer snaps:

  Gap 1 (craft-parts, base snap): the stage-package base filter
  deliberately exempts explicitly-listed stage-packages, and it never
  looks at files produced by parts. Any file that reaches prime from
  an explicit stage-package or a part build step is shipped even if
  the base snap provides the identical file. The old manual cleanup
  part removed those.

  Gap 2 (snapcraft GNOME extension, content snap): on core26 the
  extension injects a `gnome/cleanup` part that removes prime files
  whose *path* exists in `gnome-core26-sdk` or `gtk-common-themes`.
  But the content snap `gnome-core26` is a superset of the SDK for
  libraries: it additionally stages deb-only packages
  (libgoa-1.0-0b, libicu78, libcanberra-gtk3-module, ibus-gtk3,
  fcitx5-frontend-gtk3, gstreamer plugin sets, ...). A consumer's
  copies of those libraries are not removed, and they *shadow* the
  content snap's copies at runtime, because the snap's own library
  directories come before $SNAP/gnome-platform in LD_LIBRARY_PATH.

### Repro 1 (Gap 1 - explicit stage-package duplicating the base)

Build any core26 snap with an explicit stage-package that is also in
the base's chisel manifest, e.g.:

    parts:
      foo:
        plugin: nil
        stage-packages: [liblz4-1]

Real example: ubuntu/thunderbird (base core26) stages `liblz4-1`
explicitly in its `thunderbird-staged` part. The built snap contains
usr/lib/x86_64-linux-gnu/liblz4.so.1.10.0, byte-identical (same
sha256) to core26's copy. liblz4-1 IS in
/snap/core26/current/var/lib/chisel/manifest.wall, so it would have
been filtered if it had only been a recursive dependency of some
other stage-package; being explicitly listed exempts it
(craft_parts/packages/deb.py, `_get_filtered_stage_package_names`:
`return filtered_packages - stage_packages`).

Under core24 the snap's manual cleanup part removed this file at
prime time (it scanned the base snap's tree). There is no replacement
mechanism: the base is not among gnome/cleanup's cleanup sources.

Consequences: wasted payload today; worse, after a base security
update of lz4, the consumer keeps loading its own stale copy (snap
dirs precede the base in the dynamic-linker search order) until it is
rebuilt.

Suggested fix: extend the base dedup to prime time at file level, or
stop exempting explicitly-listed stage-packages (or at least document
loudly that explicitly listing a base package reintroduces the
duplicate).

### Repro 2 (Gap 2 - content snap's deb-only libraries)

Real example: ubuntu/gnome-contacts (base core26, extensions:
[gnome]) needs libgoa-1.0 for its online-accounts integration. The
recipe's comment says the runtime library comes from gnome-core26;
only the build dependency is declared. gnome-core26 indeed provides
libgoa-1.0.so.0 (it stages the libgoa-1.0-0b deb). But:

  * gnome-core26-sdk (the cleanup's reference) does NOT contain goa
    at all,
  * so `gnome/cleanup` leaves the snap's own staged copy in place,
  * and the snap's copy (libgoa-1.0.so.0 + libgoa-1.0.so.0.0.0)
    shadows gnome-core26's at runtime.

Today the two files happen to be byte-identical (same archive build),
so the impact is 0.3 MB of waste; in general the content snap's copy
can be newer than the consumer's stale one - the exact failure mode
the extension docs warn about ("a content snap update could
introduce a dependency on a new symbol that an older bundled library
doesn't provide").

Related, same mechanism: the SDK builds newer library versions from
source than the Ubuntu archive provides (cairo 1.18.6 vs 1.18.4,
pango 1.58.2 vs 1.57.0, gtk4 4.24.0 vs 4.22.0, librsvg 2.63.2 vs
2.61.3, ...). Consumer snaps that stage archive debs pull
recursive-dependency copies of those libraries; gnome/cleanup
removes their soname symlinks (path matches the SDK) but keeps their
versioned real files (path differs). Result: dead files in prime
that nothing loads. Across ~24 rebuilt Ubuntu desktop snaps this is
~43 MB of waste (e.g. gnome-contacts carries a full archive
libgtk-4.so.1.2200.4 - 11.5 MB - that is never loaded).

Suggested fixes (any of):

  a) also clean against the content snap itself (mount/stage
     gnome-core26, not just the SDK), or maintain the content-snap
     file list in the extension;
  b) compare SONAMEs (readelf) instead of paths: remove any prime
     ELF whose DT_SONAME is provided by a provider snap;
  c) for the version-skew case, remove prime files whose *soname
     symlink* was removed by the cleanup (the real file is then
     unreachable anyway).

### Notes

* gtk-common-themes contains no shared libraries at all, so that leg
  of gnome/cleanup is a no-op for libs (kept for file types other
  than .so).
* mesa-2604 is handled separately by the GPU extension's
  `gpu/cleanup` (gpu-snap list-based cleanup) and is not affected.
* Chisel-slice stage-packages bypass the base filter entirely
  (craft_parts/packages/deb.py: `if deb_utils.has_slices(
  package_names): return package_names`), and apt Priority:essential
  packages are never unmarked - both worth documenting in the same
  context.

---- end draft body ----

## APPENDIX

- A. File/line references (authoritative copy: snapcraft 9.2.1
  classic snap)
- B. Raw per-snap classification numbers
- C. Method and reproduction commands

### A. File/line references

craft-parts 2.37.2 (= latest upstream release, in /snap/snapcraft/9.2.1):

    craft_parts/packages/deb.py:316-332   _get_filtered_stage_package_names()
                                          (line 332: `filtered_packages -
                                          stage_packages` = explicit-list
                                          exemption; identical line numbers
                                          in canonical/craft-parts@main)
    craft_parts/packages/deb.py:844-846   chisel-slice bypass of the filter
    craft_parts/packages/deb.py:865-918   _fetch_stage_debs(): mark/unmark
                                          flow
    craft_parts/packages/apt_cache.py:348-390  unmark_packages(): Priority:
                                          essential packages never unmarked;
                                          _autokeep_packages() cleanup
    craft_parts/packages/deb.py:423-445   get_packages_in_base(): core26+
                                          reads /snap/<base>/current/var/
                                          lib/chisel/manifest.wall

snapcraft 9.2.1 (identical in ~/git/snapcraft @c8fabc3fc):

    snapcraft/extensions/gnome.py:381-397 gnome/cleanup part for base >= 26
    snapcraft/extensions/gnome.py:29-33   _SDK_SNAP: core26 ->
                                          gnome-core26-sdk
    snapcraft/extensions/gpu_extension.py:185-204  gpu/cleanup for core26
    docs/reference/extensions/gnome-extension.rst:158-177  "Library
                                          cleanup"
    extensions/desktop/command-chain/desktop-launch  -> execs the
                                          content snap's command-chain

History:

    c05aed0c1 (snapcraft PR #6278, aleasto, 2026-10-01):
    "feat(extensions): add core26 support to the gnome extension" -
    introduced gnome/cleanup.

gnome-sdk repo (github.com/ubuntu/gnome-sdk):

    branch gnome-core26 snap/snapcraft.yaml:36-40   content snap
                                          stages gnome-core26-sdk +
                                          debs (libgoa-1.0-0b :205,
                                          libicu78 :214, ...) minus
                                          dev files (:63-66 removes
                                          `*.so` dev links)
    branch gnome-core26-sdk snapcraft.yaml: parts build cairo 1.18.6
                                          (:170-), pango, gtk3/gtk4,
                                          librsvg, ... from source;
                                          debs part :1298-

snapcraft-desktop-integration (content snap's runtime env):

    gnome/desktop-exports:17-24  append_dir()  :73-76  LD_LIBRARY_PATH
    gets $SNAP_DESKTOP_RUNTIME (=$SNAP/gnome-platform) dirs APPENDED
    after snapd's $SNAP dirs => snap's own libs shadow the content
    snap's; content snap shadows the base.

gpu-snap (github.com/canonical/gpu-snap):

    bin/gpu-2604-cleanup + lists/mesa-2604.<arch>.list

### B. Raw per-snap classification numbers (all 24 built snaps)

Classification of every prime .so/.so.* file vs gnome-core26 rev 33:

    DUP-EXACT        same path exists in gnome-core26
    SHADOW           soname link in prime whose family is in
                     gnome-core26 but whose exact path is not (=>
                     snap's copy IS loaded)
    ORPHAN           real file whose soname link was removed (path
                     exists in gnome-core26 via symlink) but whose
                     versioned filename does not (=> NOT loaded)
    OWN              neither path nor family in gnome-core26
                     (correct to ship)

    snap                        DUP-EXACT  SHADOW  ORPHAN(n/MB)   OWN(n/MB)
    gedit                           0        0       0            28/4.1
    eog                             0        0       0            13/2.5
    cheese                          0        0      10/9.21       18/2.7
    evince                          0        0       0            12/1.3
    gnome-calculator                0        0       0             0/0
    gnome-calendar                  0        0       0            64/19.7
    gnome-characters                0        0       0             1/3.3
    gnome-clocks                    0        0      11/9.74       6/1.3
    gnome-contacts                  2/0.3    0      17/22.86     258/18.2
    gnome-logs                      0        0       0             0/0
    gnome-text-editor               0        0       0             5/0.5
    simple-scan                     0        0       2/0.40      336/64.3
    thunderbird                     0        0       2/0.69*     32/228.3*
    firefox                         0        0       0/3.2**     47/247.3
    snap-store                      0        0       0             9/32.4
    desktop-security-center         0        0       0             9/27.4
    authd-google                    0        0       0             0/0
    snap-tpmctl                     0        0       0             0/0
    snapd-desktop-integration       0        0       0             0/0
    prompting-client                0        0       0             0/0
    ubuntu-desktop-bootstrap        0        0       0             0/0
    ubuntu-desktop-init             0        0       0             0/0
    factory-reset-tools             0        0       0             0/0

  * thunderbird ORPHAN = libpsl.so.5.3.4 + libsoup-3.0.so.0.7.4 in
    usr/lib/x86_64-linux-gnu; its 9 family-matching NSS/NSPR files
    under usr/lib/thunderbird/ are deliberate private bundling
    (rpath-loaded, path-distinct from gnome-core26's libs) and are
    counted under OWN.
  * firefox's 9 family-matching files are likewise under
    usr/lib/firefox/ (private NSS/NSPR), deliberate, not
    cleanup-relevant.
  * Base (core26 rev 750) overlap: only thunderbird liblz4 pair
    (sha-identical real file + link) + 7 copyright files;
    snap-tpmctl usr/bin/systemd-cryptsetup (pre-existing,
    deliberate).

### C. Method and reproduction

    # built snaps
    unsquashfs -f -d <name> <path/to/<snap>.snap   # all 24 snaps in
      ~/git/snaps-core26-update/{launchpad,github/*}/
    # providers (anonymous store downloads; sha3-384 verified)
    snap download core26 gtk-common-themes gnome-core26
    # (gnome-core26 needed ranged parallel fetch + sha3-384 check;
    #  the store CDN intermittently 504s ranges and throttles
    #  snapd's downloader)
    # classification scripts
    ~/scratch-dedup/classify2.py        # vs gnome-core26
    # base comparison: python walk vs unsquashed core26 tree
    # (sha256 on both-real files)
    # code inspection: /snap/snapcraft/current/lib/python3.12/
    #   site-packages/{snapcraft,craft_parts}/ (9.2.1 = the exact
    #   code that ran the builds; cross-checked identical against
    #   ~/git/snapcraft @c8fabc3fc and canonical/craft-parts@main)
    # repro of injected parts:
    snapcraft expand-extensions   # on a minimal core26 gnome project

The scratch directory was deleted after the investigation (moved out
of /tmp, which hit its tmpfs quota); the commands above reproduce
everything.
