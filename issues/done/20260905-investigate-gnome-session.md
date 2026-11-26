# Determine whether Ubuntu Core Desktop still needs its patched gnome-session

Date: 2026-09-05

Repo: core-base-desktop. Builds the Ubuntu Core Desktop base/core snap
(core24-desktop) via debootstrap + chroot hooks under hooks/*.chroot.

## Impact / Priority

Unknown at the start: the image's only gnome-session delta vs stock
Ubuntu (the PPA's --builtin patch) was suspected to be load-bearing for
the confined session, and dropping it without understanding the real
blocker risked breaking the confined desktop session entirely; the
investigation settled the approach (fix the AppArmor/snapd confinement
gap instead of patching gnome-session — see
`20260906-gnome-session-investigation-findings.md`).

Impact derived from the original note's symptoms.

## Background / why this matters

This image installs a PATCHED gnome-session package instead of the stock Ubuntu
noble one. The patching happens via the "desktop-snappers/core-desktop" PPA,
which is added and pinned to the highest apt priority in
hooks/001-extra-packages.chroot:

    Pin: release o=LP-PPA-desktop-snappers-core-desktop
    Pin-Priority: 1001

    echo "deb http://ppa.launchpad.net/desktop-snappers/core-desktop/ubuntu noble main" \
        > /etc/apt/sources.list.d/desktop-snappers.list

Because of this pin, `apt-get dist-upgrade` (also in that hook) pulls in the
PPA's gnome-session build (version 46.0-1ubuntu4.1+ucd1) instead of the stock
archive version (46.0-1ubuntu4.1). The ONLY delta in that PPA build vs. stock
Ubuntu is a single patch:

    debian/patches/ubuntu/add-builtin-session-mode.patch
    "Add back the builtin session handling flags removed in 76534bcc."
    - Re-adds the --builtin / --systemd command-line flags to gnome-session's
      main.c, which stock Ubuntu 46.x had removed.
    - When --builtin is passed, gnome-session sets use_systemd=FALSE, which
      skips the code block where it uploads the session environment to
      `systemd --user` and creates/starts a `gnome-session-<type>.target`
      systemd unit (and per-app systemd units) for the session. Instead it
      falls back to gnome-session's legacy internal ("builtin") app-launching
      logic that does NOT talk to systemd at all.

WHY THIS MATTERS: the actual GNOME session on Ubuntu Core Desktop runs *inside*
a confined snap (ubuntu-desktop-session), launched via
static/usr/bin/core-desktop-session-wrapper.sh. Earlier investigation in this
project (live-tested on a running Ubuntu Core Desktop machine) found that the
confined snap's AppArmor profile DENIES D-Bus calls from inside the snap to
`org.freedesktop.systemd1.Manager` methods (e.g. ListUnits/StartUnit) on the
user's `systemd --user` instance. Switching the snap's AppArmor profile to
complain mode (`apparmor_parser --replace --complain <profile>`) made an
equivalent `dbus-send` call succeed, which had failed in enforce mode.

This strongly suggests --builtin mode exists specifically so that gnome-session,
when run inside the confined snap, avoids making the systemd --user D-Bus calls
that AppArmor currently blocks -- i.e. the patch is very likely load-bearing,
not a leftover/unneeded delta. But this has NOT been proven end-to-end (no one
has actually booted a build with the *unpatched* gnome-session yet). That is
what this task is for.

Note: the actual `gnome-session ... --builtin` invocation is NOT in this repo
-- it lives in the separate `ubuntu-desktop-session` snap (prebuilt dependency,
not rebuilt by this task). If the stock gnome-session no longer accepts
--builtin at all, that snap's session-launch command may need a corresponding
change; investigate what actually happens (unknown-option failure? silent
fallback? full desktop launch failure?) rather than assuming.

## Goal

1. Modify this repo's build config so that the STOCK Ubuntu archive
   gnome-session package (46.0-1ubuntu4.1, source "noble") is installed
   instead of the PPA's patched one (46.0-1ubuntu4.1+ucd1), WITHOUT disabling
   the desktop-snappers PPA entirely (other packages from that PPA may still
   be needed -- check
   hooks/001-extra-packages.chroot and hooks/002.1-add-gdm.chroot for what else
   comes from it before assuming it's safe to fully disable).

   The cleanest approach is a targeted apt pin exclusion, e.g. in
   /etc/apt/preferences (or a new preferences.d snippet) added in
   hooks/001-extra-packages.chroot, something like:

        Package: gnome-session gnome-session-bin gnome-session-common gnome-session-canberra
        Pin: release o=LP-PPA-desktop-snappers-core-desktop
        Pin-Priority: -1

   (list all binary packages produced by the gnome-session source package --
   check `apt-cache showsrc gnome-session` / the PPA's binary package list to
   get the full set; don't guess). Verify with `apt-cache policy gnome-session`
   during the build (or dry-run) that the resolved candidate version is now the
   stock noble one, not +ucd1.

2. Build the image using the image build script (`build.sh`), and boot it in
   the VM run script (use the project's build/run tooling as-is; do not write
   your own image-build or VM-boot tooling).

3. Also build/boot an unmodified "before" image (stock repo, patched
   gnome-session still installed) using the same scripts, for comparison. If a
   "before" image
   already exists (check the working directory / ask before rebuilding
   unnecessarily), reuse it instead of rebuilding.

4. Compare "before" vs "after" boot behavior. Specifically check, on the "after"
   (unpatched gnome-session) VM:
     - Does GDM start and show a login greeter (not stuck at a black screen /
       crash loop)?
     - After logging in, does gnome-shell actually come up (check
       `systemctl --user status gnome-session-*.target`,
       `journalctl --user -u gnome-session-*`, and `ps aux | grep gnome-shell`
       from a VM console/serial login, or SSH in if reachable)?
     - Check `journalctl -b` (system) and the user session journal for AppArmor
       DENIED messages (`dmesg | grep -i apparmor`, or
       `journalctl -k | grep -i apparmor`) related to
       snap.ubuntu-desktop-session.* and systemd1.Manager -- this is the
       specific failure this task expects to see if the hypothesis above is
       correct.
     - Check whether gnome-session itself fails outright (e.g. logs
       "Unknown option --builtin" or similar CLI parsing error) vs. starts but
       then individual components (gnome-shell, gsd-*) fail to activate due to
       the systemd D-Bus denial.

## Expected outcomes / what to do in each case

CASE A: The "after" VM boots to a fully working GNOME session (GDM greeter,
login, working gnome-shell desktop) with no relevant AppArmor denials.
  -> The patch is NOT needed (perhaps AppArmor policy or something else has
     since changed to make the systemd D-Bus path work). Remove the
     desktop-snappers PPA pin/pull for gnome-session permanently from this
     repo (keep the apt preferences change from step 1), document the finding
     in the commit message, and note whether the PPA itself should also be
     asked to stop shipping the patched gnome-session.

CASE B (my expectation): The "after" VM fails in some way -- GDM greeter may or
may not appear, but gnome-shell/session components fail to start correctly,
and/or AppArmor denials for snap.ubuntu-desktop-session.* against
org.freedesktop.systemd1.Manager appear in the journal/dmesg.

  -> Do NOT just revert to using the patched gnome-session and stop there.
     Investigate the actual root cause (the AppArmor confinement gap) and look
     for a real fix at the AppArmor/snapd-interface level rather than
     perpetuating the out-of-archive gnome-session patch as a workaround, e.g.:

  - Identify exactly which D-Bus method call(s) are denied (full audit
    message: interface, member, path, peer label).
  - Determine what snapd interface (if any) is supposed to grant a snap
    access to make systemd --user D-Bus management calls on the session
    bus (research snapd's interfaces, e.g. dbus/systemd-related
    interfaces, or whether this requires a new/updated AppArmor policy
    group shipped by this repo or by snapd itself).
  - Propose (and if feasible, implement + test) a fix: either an updated
    AppArmor profile/policy snippet installed by this repo (check
    static/ and hooks/800-remove-unneeded-profiles.chroot for where
    AppArmor policy lives in this repo) that allows the specific D-Bus
    calls gnome-session's systemd-mode needs, or documented follow-up
    work if a proper fix requires changes outside this repo (e.g. in
    snapd or the ubuntu-desktop-session snap).

  Re-test with the fix applied (rebuild + reboot the VM) to confirm the
  stock gnome-session now works end-to-end without the PPA patch.

Only fall back to keeping the patched gnome-session (i.e. revert step 1) if
a proper fix genuinely isn't achievable within this task, and clearly explain
why in the final report.

## Deliverables

- A patch/commit to core-base-desktop implementing step 1 (apt pin exclusion),
  and, if Case B's real fix is found and is in-scope for this repo, that fix
  too.
- A written summary (in the PR/commit description, not a new markdown file)
  covering: what was tested, exact journal/dmesg evidence for what failed (or
  didn't), which case (A or B) applied, and the final recommendation/state.
- Do not leave the image build in a partially-modified state -- if you end up
  reverting the pin change because the stock gnome-session doesn't work and no
  fix was found, make sure hooks/001-extra-packages.chroot is restored to
  behave as it did before (patched gnome-session installs), and say so
  explicitly in your summary.
