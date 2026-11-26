# Fix KDE boot errors: kcminit 127, AppArmor env denials, wayland-0

## Impact / Priority

PRIORITY: High. A real user logging into the KDE image sees two failed
session units on every login (plasma-kcminit, plasma-ksplash) and the
polkit authentication agent crash on its first start; the ksplash splash
screen never renders. The desktop itself does come up (env lands ~10s
later via kwin's export, polkit agent succeeds on its 2nd attempt), so
the visible symptom is boot-error noise plus a ~10s window in which any
D-Bus-activated Qt app that does not auto-restart dies silently. Polkit
prompts may also have been delayed/lost during that window -- not yet
verified with a real sudo-from-GUI prompt test (see "Done when").

Context: three independent bugs, diagnosed on the test VM (image built
2026-10-14, branch desktop/26 of plasma-desktop-session; snapd = our
ubuntu-core-desktop-snapd fork)

1. plasma-kcminit exit 127 -- upstream dropped kcminit in Plasma 6.8.
   The Neon suite is a floating track (by design) and rolled under us:
   current snaps are Plasma 6.8.0 / KF6 6.31.0 / Qt 6.11.1 (was
   6.7.5/6.30/6.11.1). Verified: plasma-workspace 6.8.0 deb ships NO
   kcminit/kcminit_startup binary (6.7.5 was the last). Every boot:
     run-after.sh: exec: $SNAP/plasma/usr/bin/kcminit_startup: not found
   Do NOT fix by pinning versions (the `=` pin in kf6-core26's
   snapcraft.yaml is an emergency brake only); fix our wiring.

2. First-attempt ABRTs of D-Bus/systemd-activated units (ksplash,
   polkit agent): "no Qt platform plugin could be initialized" ->
   ANOM_ABEND sig 6. Root cause: startplasma-wayland,
   kwin_wayland_wrapper and ksmserver all push DISPLAY/WAYLAND_DISPLAY
   etc. into the session bus activation env + systemd --user manager
   env, and ALL FOUR calls are AppArmor-DENIED:
     dbus-daemon: DENIED dbus_method_call member=UpdateActivationEnvironment
       (session bus) label=snap.plasma-desktop-session.plasma-desktop-session
       / plasma-kwin-wayland / plasma-ksmserver, peer unconfined
     DENIED member=SetEnvironment interface=org.freedesktop.systemd1.Manager
       label=plasma-ksmserver
   The env only lands later via `systemd-user-control`-allowed
   UnsetAndSetEnvironment (kwin wrapper's KUpdateLaunchEnvironmentJob),
   so units activated before that (ksplash at +1s, polkit agent 1st
   attempt) inherit a stale env and die. Our snapd fork already has the
   dedicated `systemd-user-environment` interface
   (ubuntu-core-desktop-snapd/interfaces/builtin/
   systemd_user_environment.go: session-bus UpdateActivationEnvironment
   + Manager.UnsetAndSetEnvironment); GNOME's session snap plugs it
   (ubuntu-desktop-session-snap snap/snapcraft.yaml, README "broker"
   section). plasma-desktop-session does not plug it anywhere.
   Red herring, do NOT chase: "xcb-cursor0 or libxcb-cursor0 is needed"
   -- libxcb-cursor.so.0 IS present in the kf6-core26 snap; the real
   failure is the missing display env.

3. run-after.sh (plasma-desktop-session/scripts/run-after.sh)
   hardcodes `export WAYLAND_DISPLAY=wayland-0` as fallback -- but
   kwin's socket is wayland-1 inside the snap-private runtime dir
   (/run/user/1000/snap.plasma-desktop-session/wayland-1; the public
   /run/user/1000/wayland-0 -> snap.plasma-desktop-session/wayland-0
   symlink is DEAD). The fallback can never connect. Also
   plasma-ksplash still waits on org.kde.KWinWrapper (claimed before
   the compositor serves anything); plasmashell and the polkit agent
   already wait on org.kde.KWin -- ksplash should too.

4. (Cosmetic, optional) kwin/plasmashell log "pw.conf: can't load
   config client.conf" every ~5s, and kwin logs one "Failed to create
   PipeWire context" at startup: pipewire's client.conf is not
   reachable at the conf search path inside the session namespace.
   Defaults apply, so this is log noise, not a functional break.
   Investigate $PIPEWIRE_CONFIG_DIR / build-time conf dir before
   attempting a fix (e.g. stage a minimal client.conf or point the
   env var at the pipewire snap's share dir).

## Work

1. Drop the dead plasma-kcminit app from
   plasma-desktop-session/snap/snapcraft.yaml: remove the whole
   `plasma-kcminit:` app block, the `dbus-kde-kcminit` dbus slot
   (`name: org.kde.kcminit`), and the `after: [plasma-kcminit]` entry
   in plasma-ksmserver's `after:` list. Grep the repo for remaining
   kcminit references afterwards.

2. Plug `systemd-user-environment` on the three env-exporting apps
   (app-level `plugs:`, NOT just top-level -- a top-level-only plug
   gets no AppArmor grant):
     - plasma-desktop-session (startplasma-wayland)
     - plasma-kwin-wayland (kwin_wayland_wrapper)
     - plasma-ksmserver
   Also add "systemd-user-environment" to `simple_plugs` in
   ubuntu-core-desktop/build.sh `kde_gadget_connections()` (same list
   GNOME uses) so the plug auto-connects on the dangerous image.
   Note ksmserver may still log one Manager.SetEnvironment denial (the
   interface grants UnsetAndSetEnvironment, not SetEnvironment) --
   harmless: dbus-daemon syncs the activation env into the manager
   itself, so UpdateActivationEnvironment succeeding is sufficient.
   Only extend the fork interface if verification shows a real gap.
   The image's snapd already is the fork; if `snap interface
   systemd-user-environment` is missing on the VM, rebuild the snapd
   snap and rebuild the image so the new snapd snap gets baked in.

3. Fix scripts/run-after.sh: replace the hardcoded wayland-0 with
   socket discovery under $XDG_RUNTIME_DIR (the snap-private dir
   snap run gives it), e.g. iterate "$XDG_RUNTIME_DIR"/wayland-* and
   export WAYLAND_DISPLAY=<first real socket's basename>; keep the
   "only if unset" guard. Change plasma-ksplash's wait name from
   org.kde.KWinWrapper to org.kde.KWin (matches plasmashell/polkit
   agent reasoning, documented in the yaml comment on
   plasma-plasmashell).

4. (Optional, last) silence pw.conf per investigation above.

## Compile

Rebuild all three KDE snaps in parallel (version-skew check included)
and then the image in ubuntu-core-desktop -- the image build resolves
snaps by mtime and checks the session snap's embedded git revision vs
HEAD, so commit before building. Then boot the rebuilt image. Commits
on desktop/26.

## Verify (on the new test VM)

(ssh root@<vm-ip> works; a root shell is also available on the serial
console.)
  a. `systemctl --user -M your_username@ list-units --state=failed` ->
     EMPTY (was plasma-kcminit + plasma-ksplash).
  b. `journalctl -b | grep -a 'apparmor="DENIED"' | grep
     -E 'UpdateActivationEnvironment|SetEnvironment'` -> no hits from
     snap.plasma-desktop-session.* labels.
  c. `journalctl -b | grep -a kcminit` -> nothing; no 127/exit-code
     failures for the session snap.
  d. `journalctl -b | grep -a ksplashqml` -> no ANOM_ABEND/coredump;
     plasma-ksplash.service exits 0 on FIRST activation; polkit agent
     starts on attempt 1 (no "Scheduled restart job" for
     plasma-polkit-agent).
  e. End-to-end login proof (NOT just daemons-running): desktop renders
     (panel, wallpaper, icons), plasmashell QSGRenderThread active;
     launch a real app; run a real sudo action from the GUI to
     exercise the polkit agent prompt.
  f. Re-check pw.conf noise (expect unchanged unless item 4 done).

## Done when

All of a-f verified on a freshly built+booted image, with the fixes
committed on desktop/26 (and build.sh's gadget change committed on the
ubuntu-core-desktop branch holding kde_gadget_connections), and any
leftover noise (ksplash xcb messages, pw.conf) either fixed or
explicitly recorded as known-cosmetic.

## Resolution (2026-11-03)

Implementation DONE - all three work items landed on desktop/26:
plasma-desktop-session 712fc51 (drop dead plasma-kcminit app/slot/
ordering - work item 1, plus the run-after.sh wayland-socket fallback
fix from item 3), 148f241 (systemd-user-environment plugged on
startplasma-wayland/kwin-wayland/ksmserver; ksplash now waits on
org.kde.KWin - work items 2-3), and build.sh kde_gadget_connections
wires systemd-user-environment (build.sh:161,283). Subsequent 6.8.1
release-train QA boots (2026-10-27, test VM) exercised the session
end-to-end. CAVEATS, recorded rather than re-derived: the per-item
verification checklist (a-f) was never formally recorded run-by-run;
item e (real GUI sudo prompt) is superseded by
`20261029-polkit-client-interface-for-kcm-prompts.md` - the
client-side CheckAuthorization gap is still open, so no GUI polkit
prompt can succeed until that lands. Item 4 (pw.conf noise) remains
known-cosmetic, uninvestigated.
