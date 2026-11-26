# gnome-session on resolute: findings and the fix for Ubuntu Core Desktop

Date: 2026-09-06

## Impact / Priority

The noble-era gnome-session patch cannot be ported to resolute
(--builtin and the builtin launching mode are gone upstream), so how
the confined session starts GNOME's systemd --user chain had to be
rethought; the wrong path here (a custom init-worker, a nested systemd
--user, or a fake systemd shim) would have meant either a broken
confined session or unmaintainable desktop code. The investigation
fixed the approach: treat it as an AppArmor/snapd-interface confinement
problem around the stock binaries.

Impact derived from the original note's symptoms.

## 1. Summary of investigation / findings

THE NOBLE (24.04) SITUATION
- Ubuntu Core Desktop currently ships a single-source patch on top of stock
  Ubuntu noble's gnome-session (46.0-1ubuntu4.1), via the
  desktop-snappers/core-desktop PPA (pinned to apt priority 1001 in
  hooks/001-extra-packages.chroot): debian/patches/ubuntu/
  add-builtin-session-mode.patch.
- That patch re-adds the --builtin / --systemd CLI flags to gnome-session's
  gnome-session/main.c, which upstream Ubuntu 46.x had already removed
  (commit 76534bcc). With --builtin passed, gnome-session sets
  use_systemd=FALSE and skips the whole code block that uploads the session
  environment to `systemd --user` and starts a `gnome-session-<mode>.target`
  systemd unit -- i.e. it avoids ALL systemd --user D-Bus interaction for
  session management, and instead uses gnome-session's old built-in
  autostart-file-based app launching.
- We strongly suspect (validated indirectly, see below, but NOT yet proven
  by actually building/booting with the patch removed) that this patch is
  load-bearing specifically because the confined ubuntu-desktop-session
  snap's AppArmor profile currently DENIES D-Bus calls from inside the snap
  to org.freedesktop.systemd1.Manager (e.g. ListUnits/StartUnit/GetUnit) on
  the user's real systemd --user instance. Live-tested on a running Core
  Desktop machine (noble): switching that snap's AppArmor profile to
  complain mode (`apparmor_parser --replace --complain <profile>`) let an
  equivalent dbus-send call to systemd1.Manager.ListUnits succeed, where it
  had been denied in enforce mode.
- We wrote `20260905-investigate-gnome-session.md` describing a concrete
  experiment to actually test dropping the patch on noble and see what
  breaks -- this has NOT been run yet.

THE RESOLUTE (26.04) SITUATION -- WHY THE OLD PATCH CANNOT SIMPLY BE PORTED
- On resolute, gnome-session ships GNOME 50.x. Upstream has since removed
  the --builtin/--systemd flags AND the whole "builtin" launching mode
  ENTIRELY (not just made it non-default) -- there is no `use_systemd`
  toggle anywhere in current gnome-session/main.c. The
  add-builtin-session-mode.patch cannot be ported forward at all: the code
  it patches doesn't exist anymore, and the builtin launching logic it
  re-enabled has been deleted upstream, not merely disabled. This is why we
  initially said "gnome-session has changed significantly" for resolute --
  that statement is correct as far as it goes.
- HOWEVER, we later found (by reading the actual current upstream source,
  not just changelogs) that the architecture changed in an important and
  more nuanced way than "systemd is now mandatory with no escape hatch":
  gnome-session was split into three binaries:

    1. `gnome-session` (gnome-session/leader-main.c) -- the process GDM
       actually launches. It sets up environment/locale, then
       unconditionally execs into:

    2. `gnome-session-init-worker` (built from gnome-session/leader-systemd.c)
       -- a SEPARATE, small, standalone executable at
       $LIBEXECDIR/gnome-session-init-worker. The upstream source comment
       says explicitly:

            "We've set up the environment, so now it's time for the init
            system to take over. The init system is responsible for
            starting up the rest of GNOME. Upstream we only support
            systemd, but to make it possible to integrate GNOME with other
            inits we've factored out the systemd-specific code into a
            separate init-worker binary."

       i.e. upstream GNOME deliberately designed this split so that a
       distro/vendor CAN ship an alternative gnome-session-init-worker
       binary (at the same libexec path) that talks to a *different* init
       system's equivalent API, without needing to patch gnome-session
       itself at all. This is the origin of what we said might be possible:
       "invoke/replace the non-systemd split binary directly" instead of
       patching gnome-session's main.c.

    3. `gnome-session-service` (gsm-manager.c, gsm-systemd.c, gsm-app.c,
       etc.) -- the actual long-running org.gnome.SessionManager D-Bus
       service (inhibitors, presence, client tracking, app-store/session
       fill logic). This is started by systemd as its own user unit,
       activated as part of the target chain below -- it is NOT part of
       the leader/init-worker split at all.

- We read the ACTUAL logic inside the current init-worker
  (leader-systemd.c) line by line. It does exactly this, and nothing more:

    a. Connects to the (real) session bus.

    b. Calls org.freedesktop.systemd1.Manager.GetUnit("graphical-session.target")
       + reads the Unit's ActiveState property, to bail out if a graphical
       session is already running.

    c. Calls org.freedesktop.systemd1.Manager.ResetFailed() (clears any
       previously-failed unit states before starting fresh).

    d. Calls org.freedesktop.systemd1.Manager.StartUnit(
       "gnome-session@<mode>.target", "fail") -- this is the SINGLE call
       that actually kicks off starting the whole desktop (gnome-shell,
       gsd-*, portals, etc. are all systemd --user units pulled in via that
       target's dependency chain).

    e. Opens a FIFO at $XDG_RUNTIME_DIR/gnome-session-leader-fifo and waits;
       a separate `gnome-session-monitor.service` (a systemd --user unit)
       writes to this FIFO / signals sd_notify(STOPPING=1) as part of
       coordinated shutdown; on SIGTERM/SIGINT/HUP it calls StartUnit on
       "gnome-session-shutdown.target" to unwind everything cleanly.

  In other words: the "non-systemd split binary" is not actually
  non-systemd at all in its current, only-shipped-upstream form -- it is a
  thin, systemd-D-Bus-only shim. The "designed to be pluggable for other
  inits" comment is an invitation to WRITE a genuinely different
  implementation (e.g. for a non-systemd distro), not an indication that
  one already exists upstream. There is no ready-made non-systemd
  init-worker to just switch to.

- This also means the actual GNOME session activation surface that needs to
  work from inside the confined snap is fairly small and well-defined:
  Manager.GetUnit, Manager.ResetFailed, Manager.StartUnit, and
  Unit.ActiveState (property get) on org.freedesktop.systemd1 -- plus,
  separately, the `gnome-session@<mode>.target` /
  `gnome-session-shutdown.target` / `graphical-session.target` /
  `graphical-session-pre.target` unit tree and `gnome-session-monitor.service`
  must actually exist as loadable systemd --user units (this part isn't a
  D-Bus permission issue, it's a "are the right unit files installed/
  enabled" issue, and needs separate verification for whatever
  session/desktop package layout Core Desktop ends up using on resolute).

RELEVANT PLATFORM DETAIL FOUND DURING THIS PROJECT (not yet connected up)
- The pc-desktop gadget's gadget.yaml sets, as system defaults:
    experimental.user-daemons: true
    experimental.dbus-activation: true
  `daemon-scope: user` is a real (now non-experimental, per snapd's own
  test suite comments) snapd `apps:` stanza feature: a snap can declare an
  app with `daemon: simple, daemon-scope: user`, and snapd itself generates
  and manages the corresponding systemd --user unit for it, presumably also
  handling whatever AppArmor/confinement grants are needed for snapd (as
  the deliberate broker) to install/start/stop THAT unit on the snap's
  behalf. This is a concrete, already-enabled building block that seems
  directly relevant to solving this problem the "proper" way -- see
  recommendation below. We have NOT yet examined exactly what AppArmor
  access `daemon-scope: user` grants a snap, whether it covers arbitrary
  StartUnit calls against non-snap-declared unit names (like
  "gnome-session@ubuntu.target", which is a session/desktop-authored unit,
  not a snap-declared daemon app) or only lets snapd itself manage units it
  generated -- this needs concrete investigation, not assumption.

## 2. Critique of the earlier proposed analysis and options

Their framing of the noble situation ("Canonical's intervention... was
simply re-enabling --builtin execution mode") is correct.

Their framing of "why it broke on resolute" is CORRECT IN SPIRIT but
imprecise/unverified as stated:
- They say "the systemd execution logic was isolated into
  gnome-session-init-worker" -- true, and we've now confirmed this
  precisely against the actual current upstream source (see section 1).
- They say "--builtin mode was completely removed upstream rather than
  just disabled" -- true, confirmed directly in current main.c: there is no
  use_systemd/--builtin/--systemd anywhere anymore.
- Their claim that this happened "in GNOME 47/48" is a specific version
  claim we have not independently verified against gnome-session's git
  history/NEWS -- treat as unconfirmed rather than fact until checked
  against the actual version resolute ships and the commit that introduced
  the init-worker split.

Their three options and analysis:

Option 1 ("adapt gnome-session-init-worker to route through snapd's
existing daemon-scope:user infrastructure") -- directionally the right
answer, BUT the specific mechanism they describe is invented/wrong:
  - They describe "a custom worker [that] intercepts calls and maps them to
    the systemd units that snapd dynamically generates on the host" and
    "snapd securely brokers those requests to the host's systemd --user
    instance." This is not how anything here actually works, and no such
    snapd broker layer exists today. In reality: the stock, unmodified,
    upstream gnome-session-init-worker ALREADY talks directly, over
    standard D-Bus, to the real systemd --user instance that Ubuntu Core
    already runs (this is exactly what we read in leader-systemd.c). There
    is no "custom worker" needed and no "mapping/brokering" layer to build
    -- the problem is not an API mismatch between GNOME and Ubuntu Core's
    init, it's that ONE participant (the confined snap process) is being
    denied permission by AppArmor to make a small, specific, enumerable set
    of D-Bus calls it's already trying to make with the stock binary.
  - Their stated "con" (Canonical must maintain a custom worker API-
    compatible with GNOME's D-Bus expectations forever) would be a real
    cost IF a custom worker were required -- but per our reading of the
    source, no custom worker/binary is required at all if the AppArmor gap
    is closed properly. This meaningfully understates how tractable the
    real fix is and overstates the ongoing maintenance burden.

Option 2 (nested/private systemd --user instance inside the snap) --
their cons are basically correct and match our own reasoning: giving a
confined snap direct cgroups v2 delegation to run its own private
systemd --user would either require breaking out of strict confinement
(cgroup delegation needs write access to the cgroup tree, which AppArmor/
snap confinement specifically restricts) or would produce a second,
disconnected systemd --user instance that doesn't share unit state with
whatever manages other user services (pipewire, xdg-desktop-portal, D-Bus
activation for non-snap-graphical apps, etc.) -- correctly identified as a
split-brain problem. We agree this option is not viable.

Option 3 (non-systemd shim reimplementing --builtin-like behaviour against
the new init-worker split) -- their cons are correct: Ubuntu Core actually
runs real systemd, so building and maintaining a fake systemd-API shim
purely to route around an AppArmor policy gap is solving the wrong layer
of the problem, and each upstream GNOME release could add new dependencies
on the real systemd --user unit graph (target chains, Type=notify
readiness protocols, etc.) that a hand-rolled shim would have to keep
re-discovering and re-implementing. We agree this option is the weakest of
the three.

Overall verdict on that earlier analysis: the final recommendation
(pursue the systemd-integration path, don't go non-systemd, don't run a
nested user session manager) is the RIGHT high-level conclusion, but the
proposed mechanism for how to achieve it is not grounded in the actual
architecture and invents components/behaviour (a "custom init-worker"
and a "snapd broker") that don't need to exist. Recommend against
implementing anything based on that mechanism description literally.

## 3. Our recommendation

Do NOT write a custom/patched gnome-session-init-worker, and do NOT patch
gnome-session at all. Use the stock upstream gnome-session-init-worker
as-is. Instead, treat this purely as an AppArmor / snapd-interface
confinement problem, since the stock binary already does precisely what
Ubuntu Core Desktop needs (talk to the real systemd --user instance) -- it
is currently just being blocked from doing so.

Concrete recommended path:

1. Get the exact enumeration of AUDIT/DENIED AppArmor log lines produced
   when the confined ubuntu-desktop-session snap runs the stock
   gnome-session (no --builtin, since it no longer exists) on resolute --
   specifically for: GetUnit, ResetFailed, StartUnit on
   org.freedesktop.systemd1.Manager, and Properties.Get("ActiveState") on
   org.freedesktop.systemd1.Unit (this is the exhaustive, small call list
   from leader-systemd.c -- section 1 above -- so this should be a short,
   closed list, not an open-ended fishing expedition).

2. Determine whether snapd's already-enabled `experimental.user-daemons` /
   `experimental.dbus-activation` gadget defaults (or the `daemon-scope:
   user` apps stanza feature they enable) already provide, or can be
   extended/configured to provide, exactly this AppArmor allowance --
   i.e. permission for the ubuntu-desktop-session snap to make these
   specific systemd1.Manager/Unit calls against unit names it doesn't
   necessarily own/declare itself (gnome-session@<mode>.target is a
   session-authored unit name, not something snapd generates from the
   snap's own `apps:` stanza, so this may require snapd's `daemon-scope:
   user` interface to be widened, or a distinct/new snapd interface, rather
   than simply turning on the existing experimental flags and hoping they
   cover it -- verify this empirically rather than assuming).

3. If existing snapd features don't already cover this: propose the
   narrowest possible addition -- either (a) a new/extended snapd interface
   that grants a snap's AppArmor profile permission for exactly the
   GetUnit/StartUnit/ResetFailed/ActiveState-on-Unit call pattern against
   systemd --user (scoped by the calling snap's own security label, so
   confinement isn't meaningfully weakened elsewhere), or (b) if that's a
   larger snapd change than can land in time, a locally-shipped AppArmor
   policy fragment (installed by this repo, similar to how
   static/usr/share/pam-configs/snappy-extrausers or other static/ policy
   files are shipped today) that allows just this call list for the
   ubuntu-desktop-session snap's profile specifically, clearly labelled as
   an interim measure pending a proper snapd interface.

4. Separately (and this is NOT an AppArmor problem, don't conflate the
   two): confirm the actual systemd --user unit files gnome-session's
   session-startup path now depends on (gnome-session@<mode>.target,
   graphical-session.target, graphical-session-pre.target,
   gnome-session-shutdown.target, gnome-session-monitor.service, and all
   gsd-*/gnome-shell per-component units pulled in via those targets) are
   correctly installed, unmasked, and enabled inside the snap's session
   environment for whatever exact session package layout Core Desktop uses
   on resolute. This is a completely separate, "did we package/enable the
   right unit files" verification step, independent of whether AppArmor
   allows the D-Bus calls that start them.

5. Validate end-to-end on a resolute VM using the previously agreed staged
   approach (still useful even with this more precise understanding):
   temporarily set the snap's AppArmor profile to complain mode to confirm
   the stock gnome-session/gnome-session-init-worker chain fully works
   once AppArmor is out of the way (isolating "does the systemd unit graph
   itself work" from "is AppArmor the only remaining blocker"), THEN
   implement and switch to the real fix from steps 2-3, and re-verify in
   enforce mode before considering this done. Do not ship with the profile
   left in complain mode.

Net effect vs. the noble approach: instead of forking/patching
gnome-session itself (which is no longer possible on resolute -- the code
path is gone), the fix moves one layer down into AppArmor/snapd
interface policy, which is more precisely scoped, easier to keep in sync
with upstream GNOME (since it no longer requires carrying a
gnome-session source patch/rebuild at all), and directly addresses the
root cause identified via live testing (the AppArmor complain-mode
experiment) rather than working around it with a deleted upstream
compatibility flag.

## Resolution (moved to done 2026-09-22)

This recommendation was implemented: the confined session now uses the
stock upstream gnome-session-init-worker chain, unmodified, with the
`systemd-user-control` AppArmor interface extended to allow exactly the
GetUnit/ResetFailed/StartUnit/Properties.Get("ActiveState") call pattern
this doc identified. Verified end-to-end on the core26 gnome VM: confined
session boots, stays fully confined, no org.freedesktop.systemd1 AppArmor
denials. See `20260922-stage0-stage1-confined-session-unblock.md` for the
fuller resolution writeup. Note: the systemd-user-control rules as
shipped are still broader (wildcard unit path) than this doc's
narrowly-scoped recommendation — a properly-scoped proxy replacement is
carried forward as Stage 3D in
`20260922-split-core26-desktop-base-snap.md`.
