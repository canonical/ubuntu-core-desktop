# Porting Ubuntu Core Desktop from noble (24.04) to resolute (26.04)

Date: 2026-09-06

core-base-desktop project status / remaining work

## Impact / Priority

A large amount of noble→resolute patch-porting work had reportedly been
done, but none of it had been verified end-to-end, and that verification
was the current critical path / blocker for the whole project: until it
was proven on a real resolute-based VM, nothing could be trusted to
actually boot and work.

Impact derived from the original note's symptoms.

CONTEXT: The desktop-snappers/core-desktop PPA carries a set of Ubuntu-Core-
Desktop-specific patches on top of noble packages. The project goal is to
rebuild the equivalent functionality using native resolute (26.04) sources
instead of relying on that noble-targeted PPA, then verify the result
actually boots and works on real resolute-based Ubuntu Core Desktop. A large
amount of patch-porting work was reportedly already done before this session
("we spent a lot of time porting patches from noble to resolute"), but NONE
OF IT HAS BEEN VERIFIED END-TO-END YET. That verification is the current
critical path / blocker for the whole project.

## 1. Highest priority: end-to-end verification on a real resolute VM

- Stand up an actual Ubuntu 26.04/resolute Ubuntu Core Desktop VM (QEMU) and
  install the rebuilt packages (currently believed to be just: shadow,
  adduser, gnome-shell -- provd can stay stock). CONFIRM this package list is
  still accurate/complete before proceeding -- it was derived from reasoning
  about gnome-session's --builtin flag not being needed, not from a full
  patch-by-patch audit (see item 2).
- This has been blocked for a long time by the gnome-session/AppArmor issue
  (see item 3) preventing GNOME from even starting. A staged workaround plan
  was agreed:
    a. Drop --builtin from the session launch command (resolute's stock
       gnome-session 50.1 doesn't support that flag anyway -- confirm this
       is still true against whatever exact 50.x version resolute ships).
    b. Expect an AppArmor denial when gnome-session tries to talk to
       systemd --user.
    c. Temporarily relax via `apparmor_parser --replace --complain
       <snap.ubuntu-desktop-session.ubuntu-desktop-session profile path>`
       (validated live on noble; should work identically on resolute, but
       not yet tried there).
    d. Verify gnome-shell / gsd-* services actually activate correctly under
       complain mode.
    e. Only once that's confirmed working, move on to a proper permanent fix
       (see item 3) instead of shipping with AppArmor left in complain mode.
- Use a cloud-init seed to give the VM a working user + SSH access from
  first boot, instead of relying on console-conf
  (which is disabled on this image) or manual netcat shells. Remember to also
  apply the GDM initial-setup fix (item 5) so the VM boots straight to the
  login greeter instead of the desktop-provision wizard.
- Actually record what breaks, with real error messages/journal output, so
  remaining porting work can be prioritized by real evidence instead of
  guesswork.

## 2. Full audit of desktop-snappers PPA patches vs. what's been ported

- Only shadow, adduser, and gnome-shell have been confirmed as needing a
  resolute rebuild so far, largely reasoned out rather than exhaustively
  checked. Do a complete pass: enumerate every source package the
  desktop-snappers/core-desktop PPA carries for noble (Launchpad API:
  getPublishedSources against ~desktop-snappers/+archive/ubuntu/core-desktop),
  diff each package's patches against the plain Ubuntu noble version to see
  what's actually changed, then determine for each:
    - Does resolute's stock version already behave equivalently (patch
      obsolete)?
    - Does the patch still apply / is still needed, and needs porting to
      resolute's version of that source package?
    - Is the patch's underlying need itself questionable (see gnome-session,
      item 3) and worth challenging rather than blindly porting?
- gnome-session was already identified as NOT needing its patch under the
  current plan (resolute's 50.1 doesn't support --builtin regardless), but
  this is still unverified in practice -- see
  `20260905-investigate-gnome-session.md`, which
  describes a concrete experiment (on noble first) to test dropping the
  patch and see what actually breaks. The resolute equivalent of that
  experiment still needs to be run once a resolute VM is working (item 1).

## 3. Proper fix for the AppArmor / systemd --user D-Bus block

- AppArmor complain-mode is a validated but TEMPORARY unblocking hack, not a
  shippable fix. Need to:
    - Get the exact AUDIT/DENIED log line(s) (interface, member, path, peer
      label) for the specific systemd1.Manager D-Bus call(s) gnome-session's
      systemd-mode needs.
    - Determine the correct permanent fix: most likely an AppArmor policy
      addition/snapd interface grant that allows the confined
      ubuntu-desktop-session snap to make specific systemd --user management
      calls (ListUnits/StartUnit/etc.) without wholesale complain mode.
      Research whether snapd already has (or would need) an interface for
      this (e.g. something in the family of the "desktop" or "systemd"
      related snapd interfaces), and whether it needs upstream snapd changes
      or can be done via a local AppArmor policy addition shipped by this
      repo.
    - Implement and test the real fix on the VM (enforce mode, not complain),
      confirm gnome-session/gsd-*/gnome-shell all still work correctly.
- This is the fix that would make dropping the gnome-session patch (item 2)
  actually viable in enforce mode, rather than only in complain mode.

## 4. Make the GDM "boots to welcome wizard instead of greeter" fix permanent

- The InitialSetupEnable=false fix for /etc/writable/gdm3/custom.conf was
  only applied live/manually on the test machine this session, NOT baked
  into the repo. Options to make it durable, in priority order of
  "actually fixes the root cause" vs. "papers over it":
    a. (Best) Figure out why accounts-daemon never registers users created
       via cloud-init's extrausers-backed users/chpasswd modules (unlike
       whatever `snap create-user`/console-conf's flow does that DOES
       register them), and fix that registration gap properly, so
       ListCachedUsers correctly reflects extrausers accounts regardless of
       how they were created. This would let GDM's normal user-detection
       logic work as designed for ANY provisioning method, not just
       console-conf.
    b. (Pragmatic fallback) If (a) isn't feasible, bake
       `InitialSetupEnable=false` into this repo's build (e.g. in
       hooks/002.1-add-gdm.chroot, alongside where console-conf is already
       disabled and gdm3 is installed/configured) so freshly-built images
       never show the desktop-provision wizard at all, and document why.
- Whichever is chosen, this needs to be decided/implemented before it's
  reasonable to rely on cloud-init-based provisioning (item 1's VM setup) as
  the standard way to get a working test VM going forward.

## 5. Minor / lower-priority cleanup items

- Fix the stale "live-config" comment in
  hooks/004-remove-openssh-server-host-keys.chroot (it references a tool
  that isn't installed/used anywhere in this image; the real mechanism is
  snapd.sshd-keygen.service / core-sshd-host-keygen). Offered, not yet done.
