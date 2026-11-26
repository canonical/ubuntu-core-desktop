# Fix KDE Plasma session AppArmor denials (polkit-agent, powerdevil)

Date: 2026-09-18

## Impact / Priority

Medium. The desktop renders and is usable, but two session services fail
to start, so some desktop features are silently missing.

What a real user would observe (grounded in a real boot, not just
logs):

- plasma-polkit-agent fails to start, so there is no authentication
  agent: any action that needs a polkit prompt (e.g. mounting a disk,
  changing system settings that require elevation) will not show a
  password prompt and will silently fail or hang. A user would see
  "nothing happens" when trying an admin action.
- plasma-powerdevil fails in a restart loop, so power management is
  broken: no automatic suspend/blanking, no battery/AC handling, no
  brightness keys. A user on a laptop would see the screen never dim or
  sleep, and brightness controls not working.

These were observed on the live core24 KDE test VM via journalctl; the
exact end-user impact of each has NOT been reproduced by actually
exercising the feature (e.g. triggering a polkit prompt or changing
brightness), so the "what a user sees" above is inferred from the
service failures, not a real end-to-end test. Investigation to pin down
the real impact: trigger a polkit-gated action and a brightness change
on the live VM and confirm they fail.

## Context / root cause

Two distinct AppArmor confinement gaps (same class as the GNOME
confined-session gaps already being worked):

1. plasma-polkit-agent:
   - AppArmor denies reading /proc/<pid>/cgroup
     (apparmor="DENIED" operation="open" name="/proc/45072/cgroup"),
     which makes polkit fail with "Cannot create unix session: No
     session for pid" -> "Cannot register authentication agent".
   - Separately, a missing Qt xcb platform plugin dependency:
     "Could not load the Qt platform plugin \"xcb\"" / "From 6.5.0,
     xcb-cursor0 or libxcb-cursor0 is needed to load the Qt xcb
     platform plugin". The content snap is missing libxcb-cursor0.

2. plasma-powerdevil:
   - AppArmor denies dbus_bind on the session bus for name
     org.kde.org_kde_powerdevil
     (apparmor="DENIED" operation="dbus_bind" bus="session"
     name="org.kde.org_kde_powerdevil"), so it can't register its D-Bus
     name and exits, restarting in a loop.

These are KDE-specific instances of the AppArmor D-Bus mediation gaps
documented in the project's diagnostics documentation ("Two independent
D-Bus denial mechanisms") and in the confined-session AppArmor work
already done. The fix likely lives in the plasma-desktop-session snap's
AppArmor policy (or the snapd interface templates), analogous to the
GNOME confined-session AppArmor fixes.

Note: this is KDE-specific and NOT a duplicate of the existing GNOME
AppArmor items (nautilus/gvfs, bwrap, app-center) — those are different
snaps/interfaces. But the fix approach (complain-mode gap collection,
then add rules) is the same methodology.
