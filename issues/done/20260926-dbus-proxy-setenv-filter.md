# Filtering D-Bus proxy for mutter's Setenv / UpdateActivationEnvironment calls

## Impact / Priority

High. Same underlying user impact as
`20260926-replace-fixup-xauthority-race.md` and the App Store launch
failures: clicking a desktop icon for any snap other than the desktop
session itself can fail outright (hard launch failure / "cannot open
display :0"), because confined mutter/gnome-session currently has an
unfiltered path to overwrite the *global* systemd --user / D-Bus
activation environment with snap-private values that other confined
snaps cannot see. This item is specifically about the proxy-based fix
design (previously discussed and agreed to be worth pursuing); see
`20260926-replace-fixup-xauthority-race.md` for the alternative "shim a
subprocess exec" design and the precondition check below for which one
actually applies.

## Important precondition (check this first)

`20260926-replace-fixup-xauthority-race.md` step 1 asks whether
gnome-session's handling of mutter's Setenv D-Bus call execs a separate
`dbus-update-activation-environment` subprocess, or calls the D-Bus
methods directly in-process. If it execs a subprocess, a much smaller
argv-filtering shim binary is sufficient and this whole proxy should
NOT be built (do that simpler fix instead). Only proceed with this item
if that investigation shows there is no subprocess exec boundary to
intercept, or if the shim approach is separately rejected for another
concrete reason. Do not start Step 1 below until this has been
confirmed one way or the other; record the finding at the top of this
file when you do.

## Context: why a full custom bus router is NOT what we want

A prior discussion considered writing one bespoke Go process that
speaks the entire D-Bus wire protocol for mutter's whole session-bus
connection (matches, introspection, fd-passing, the works). Rejected as
too large/risky: reimplementing full D-Bus router semantics correctly
is a lot of surface area for something that only needs to change the
handling of exactly two method calls (org.gnome.SessionManager.Setenv
and/or org.freedesktop.DBus.UpdateActivationEnvironment — also check
org.freedesktop.systemd1.Manager.SetEnvironment as a possible second
path, since `dbus-update-activation-environment --systemd` talks to
both the session bus and systemd --user).

Instead: use `xdg-dbus-proxy` (already used elsewhere in the snapd/
flatpak world for exactly this "let a sandboxed process talk to a bus,
but restrict it" purpose) to handle the bulk, general-purpose bus
proxying, and add only a small, separate filtering layer in front of it
that special-cases the handful of method calls we actually care about
and passes every other message through unmodified (including any
SCM_RIGHTS fds).

Whitelist (vars allowed through Setenv/UpdateActivationEnvironment as
currently understood — confirm/adjust during implementation):
WAYLAND_DISPLAY, DISPLAY, XDG_SESSION_TYPE, XDG_CURRENT_DESKTOP,
XDG_SESSION_DESKTOP, XCURSOR_THEME, XCURSOR_SIZE, GNOME_SETUP_DISPLAY.
XAUTHORITY and XDG_RUNTIME_DIR specifically must NOT be forwarded as
given by mutter — they must be forced/rewritten to the fixed real
values ($XDG_RUNTIME_DIR/.Xauthority and the real /run/user/<uid>)
rather than either passed through or silently dropped, since other code
(see core-desktop-session-wrapper.sh) already expects those exact fixed
values to be present in the environment.

## Two candidate architectures (pick one before Step 1)

### Option A: decoy socket + chained xdg-dbus-proxy

    mutter/gnome-session (confined)
        -> connects to a decoy AF_UNIX socket (its
           DBUS_SESSION_BUS_ADDRESS is pointed here instead of the real
           bus)
        -> [Go filter process] decodes only message headers (path/
           interface/member) for every message
             - if it matches one of the targeted methods: decode body,
               filter/rewrite args, re-encode, forward
             - otherwise: pass the raw bytes through completely
               unmodified (splice), including any fds
        -> forwards to a locally running `xdg-dbus-proxy` instance,
           configured with a policy covering everything else
           gnome-shell legitimately needs on the bus
        -> real session bus / systemd --user

### Option B (recommended): single dumb byte-shoveler

No xdg-dbus-proxy at all:

    mutter/gnome-session (confined)
        -> connects to a decoy AF_UNIX socket
        -> [single Go/Rust process] reads one whole D-Bus message at a
           time (fixed 16-byte header + variable header-fields array +
           body_length bytes of body, per the D-Bus wire format —
           enough parsing to find message boundaries, nothing more) and
           for each message:
             - if it is NOT one of the targeted methods: relay the
               exact bytes read (header + body) unmodified to the real
               bus, along with any SCM_RIGHTS ancillary fds that
               arrived on the same recvmsg() call (must forward
               message-at-a-time, not arbitrary byte chunks, so fds
               stay correctly associated with their message)
             - if it IS one of the targeted methods: decode only that
               message's (simple, well-known) body signature, apply the
               whitelist/rewrite, re-encode, forward
        -> real session bus / systemd --user directly (no second
           process)

Recommendation: Option B. Reasons:

- No dependency on correctly enumerating an xdg-dbus-proxy policy
  covering every legitimate bus interaction a real desktop session
  needs (own names, matches, broadcasts, etc.) — that allowlist is
  large, likely to be incomplete on the first attempt, and an
  incomplete policy silently breaks legitimate functionality rather
  than failing loudly.
- Single process, single socket hop — simpler to reason about, package,
  and operate than two chained proxies.
- The only protocol knowledge required for the 99% pass-through case is
  D-Bus *message framing* (a small, stable, well-documented part of the
  spec: fixed header + header-fields array giving the body length) —
  not the semantics of the bus itself (no name ownership, match rule,
  or policy state to maintain). This is a meaningfully smaller and more
  bounded piece of code than standing up and correctly configuring
  xdg-dbus-proxy for a whole real session.
- Blast radius of a bug is naturally limited to framing/fd-forwarding
  correctness (testable in isolation, e.g. against a scenario that is
  known to pass fds, such as a notification with an icon or a portal
  call) rather than "did we allow every method this desktop session
  turns out to need".

Keep Option A only as a fallback if Steps 1/3 below show that
message-level fd-passing cannot be made reliable in the dumb-relay
design — record that finding here if so, rather than silently
switching approaches.

Each step below is a self-contained unit of work with a hard
verification gate. Do not proceed to the next step until the current
one's gate passes; if a gate fails, stop and report which check failed
rather than improvising a workaround.

### Step 1: Stand up a working dumb-relay passthrough (no filtering yet)

Task: on the dev VM (or a scratch Ubuntu machine), write the minimal
message-framing relay described in Option B: a process that accepts a
connection on a decoy AF_UNIX socket, reads one whole D-Bus message at
a time (parse just enough of the fixed header + header-fields array to
know the total message length; do not decode the body), and relays it
byte-for-byte to a real connection to the session bus, including
forwarding any SCM_RIGHTS ancillary fds that arrived on the same
recvmsg() call for that message. Do this with NO filtering logic yet —
pure passthrough, to validate the framing/fd-relay mechanics in
isolation first. Point a test client at the decoy socket (e.g.
`busctl --address=unix:path=<decoy> list`, `gdbus call --address
unix:path=<decoy> ...` against a real service like org.gnome.Shell)
instead of the real bus address.

Verification gate (must ALL pass before Step 2):

a. `busctl --address=unix:path=<decoy> list` returns the same bus names
   as `busctl --user list` run directly.
b. At least one real method call with a non-trivial reply succeeds
   identically through the decoy socket vs. direct.
c. At least one signal/broadcast is received correctly through the
   decoy socket (subscribe and trigger it, e.g. a property change).
d. At least one real call that passes a file descriptor (e.g. a
   desktop notification with an icon, or any portal call known to use
   UNIX_FD) round-trips correctly through the decoy socket — this is
   the highest-risk part of the dumb-relay design and must be proven
   working before relying on it.

If any of a/b/c/d fail, STOP — do not proceed. Report exactly which
check failed. If (d) specifically cannot be made reliable after a
reasonable attempt, record that finding here and fall back to Option A
(xdg-dbus-proxy) instead of continuing to debug indefinitely.

### Step 2: Prove a transparent proxy doesn't break the session

Task: in a scratch/test copy of the session (NOT the production
core-desktop-session-wrapper.sh yet), redirect the confined
gnome-shell/mutter app's DBUS_SESSION_BUS_ADDRESS to the Step-1 decoy
socket (plain passthrough, still no filtering). Boot/login a full
desktop session through it on the VM.

Verification gate: the desktop session comes up normally end-to-end
(login completes, gnome-shell renders, at minimum one already-working
app or the Home desktop icon appears) with ONLY the transparent
xdg-dbus-proxy inserted in the bus path — confirming that inserting a
proxy at all is transparent enough not to break the session by itself,
independent of any filtering logic. If this fails, STOP — the whole
proxy approach is not viable regardless of the filtering layer; report
what broke (this result should be escalated, not worked around).

### Step 3: Build the minimal Go filtering layer, tested in isolation

Task: extend the Step-1 dumb-relay process with the one piece of real
filtering it needs: for messages matching
org.gnome.SessionManager.Setenv /
org.freedesktop.DBus.UpdateActivationEnvironment /
org.freedesktop.systemd1.Manager.SetEnvironment, decode that message's
(simple, well-known) body signature, apply the whitelist + forced
XAUTHORITY/XDG_RUNTIME_DIR rewrite described above, re-encode, and
forward the modified message; every other message continues to use the
Step-1 unmodified-relay path (including fds) exactly as already proven.
A Go D-Bus library such as github.com/godbus/dbus/v5 may help with
encoding/decoding just this one message's body, but the framing/relay
logic from Step 1 should not need to change. If, contrary to Step 1's
finding, fd-passing turns out not to survive this extended version,
investigate whether raw byte splicing (without full decode) is possible
for the non-target-method case, decoding only enough of the header to
route the decision.

Do NOT wire this into the real session yet — test standalone first
using a throwaway bus, e.g. `dbus-run-session -- <test>`.

Verification gate (must ALL pass before Step 4):

a. A synthetic client call to Setenv/UpdateActivationEnvironment with
   both whitelisted and non-whitelisted vars (including a deliberately
   bad XAUTHORITY/XDG_RUNTIME_DIR) results in only the whitelisted
   vars, plus the forced correct XAUTHORITY/XDG_RUNTIME_DIR, actually
   landing in the environment observed on the far side of the proxy
   (e.g. inspect the test bus's own activation environment after the
   call).
b. The non-whitelisted/bad values are confirmed NOT present anywhere
   downstream.
c. A separate, unrelated method call (e.g. Introspect or Ping) placed
   through the same running proxy instance still round-trips correctly.

If any of a/b/c fail, STOP and report which check failed with the exact
input/output observed — do not proceed to Step 4 with a partially
working filter.

### Step 4: Wire into a real test session and re-run the actual click-test

Task: replace the Step-2 transparent passthrough with the Step-3 Go
filtering proxy in the same scratch session setup. Boot a full desktop
session through it on the VM, log in for real, and click the App Store
desktop icon (a real click, not a synthetic D-Bus caller — the
project's methodology explicitly requires this, since log-only/
synthetic-caller testing has previously produced misleading "fixed"
conclusions here).

Verification gate (must ALL pass before Step 5):

a. Poll the global `systemctl --user show-environment` repeatedly
   across the whole session lifetime (not just once at login) and
   confirm XAUTHORITY/XDG_RUNTIME_DIR always show the fixed real
   values, never a snap-private path, at any point observed.
b. snap-store's window actually opens end-to-end from the real icon
   click.
c. The rest of the session still behaves normally (no new AppArmor
   denials introduced by the proxy's own confinement/placement; check
   `journalctl` for new DENIED lines correlated with the proxy
   process).

If any of a/b/c fail, STOP and report which check failed — do not
proceed to packaging with a partially working fix.

### Step 5: Package it for real (generic, templated design), verify from scratch

Task: only after Step 4 fully passes, implement real packaging. Build
the GENERIC, templated design from the start (per-snap-name decoy
socket + one shared proxy daemon, matching the originally-sketched
`dbus-proxy@.socket` / `%i` pattern), not just a one-off fixed socket
for mutter — the expectation is that other confined daemons/snaps will
need the same "controlled global-bus mutation" treatment as they get
locked down over time, and it is cheaper to build the reusable form now
than to redo this packaging work per future snap. See "Concrete wiring
mechanism" below for the concrete mechanism and the open ownership
question it raises (where the shared proxy binary/package actually
lives). Add the systemd user socket/service units and the
snapcraft.yaml changes needed so each covered snap's decoy socket
exists before that snap's confined daemon starts, and
DBUS_SESSION_BUS_ADDRESS is pointed at it. For this item's scope, wire
up mutter/gnome-shell inside ubuntu-desktop-session as the first
consumer of the generic mechanism; do not block this item on finding a
second consumer, but do not hard-code the design to only ever support
one.

Remove/replace core-desktop-session-wrapper.sh's old fixup_xauthority
function and its dbus-update-activation-environment pre-seed line (see
`20260926-replace-fixup-xauthority-race.md`) once this supersedes it.

## Concrete wiring mechanism (generic, templated design)

Built generically from the start: expect other confined daemons/snaps
to need the same "controlled global-bus mutation" treatment as they get
locked down in the future, so a single shared proxy serving multiple,
not-yet-known consumer snaps is the target, not a one-off bundled
inside ubuntu-desktop-session's own snapcraft.yaml.

This surfaces an OPEN DESIGN QUESTION that must be resolved as part of
Step 5, not assumed: snapd's own `daemon:`/`sockets:` snapcraft.yaml
keys generate units scoped to that ONE snap's own named app (e.g.
`snap.ubuntu-desktop-session.dbus-proxy.socket`) — they do not give you
a true `%i`-templated unit that can transparently pick up an arbitrary,
not-yet-onboarded consumer snap at runtime the way a hand-written
`dbus-proxy@.socket` file can. Two candidate ownership models:

(A) Proxy as its own dedicated snap, using normal snapd daemon/sockets
keys. Each consumer snap gets its own named socket entry added to the
proxy snap's snapcraft.yaml as it is onboarded (not fully dynamic —
onboarding a new consumer means a new release of the proxy snap), but
the proxy stays snap-confined with its own `plugs: [dbus]`, consistent
with the rest of this project's confinement model.

(B) Proxy shipped as a plain, unconfined trusted OS component in the
base image (core-base-desktop's static/usr/lib/systemd/user/,
alongside other already-shipped static units like
gnome-keyring-daemon.service), with a genuine hand-written
`%i`-templated unit pair as originally sketched:

    static/usr/lib/systemd/user/dbus-proxy@.socket
      [Unit]
      Description=D-Bus Proxy Socket for %i snap
      [Socket]
      # %t is the real XDG_RUNTIME_DIR; %i is the consuming snap's
      # instance name, supplied by whatever starts this per snap.
      ListenStream=%t/snap.%i/dbus-proxy.sock
      DirectoryMode=0700
      [Install]
      WantedBy=sockets.target

    static/usr/lib/systemd/user/dbus-proxy@.service
      [Service]
      ExecStart=/usr/lib/core-desktop/dbus-proxy %i

This gives real, runtime-dynamic templating (any consumer snap name
works without a proxy release), at the cost of the proxy being a new
unconfined trusted OS component rather than a confined snap — its own
security posture (why it's safe to trust it despite being unconfined,
matching how dbus-daemon/systemd/gdm are already unconfined trusted
components on this image) needs to be argued explicitly when this is
implemented, not assumed by analogy.

Recommendation: prototype (B) first, since it is the only one of the
two that actually delivers "future daemons can reuse this without a
proxy-package release," which is the stated goal — but do not treat
this as settled; record which was actually chosen and why once Step 5
is implemented.

For EITHER model, the consumer-side half is the same and matches the
originally-sketched snapcraft.yaml pattern, applied first to mutter/
gnome-shell inside ubuntu-desktop-session as the first onboarded
consumer:

    apps:
      gnome-shell:
        command: usr/bin/mutter ...
        # No `dbus` plug here any more -- this removal is the actual
        # security boundary; everything else is plumbing to make that
        # survivable.
        environment:
          DBUS_SESSION_BUS_ADDRESS: "unix:path=$XDG_RUNTIME_DIR/dbus-proxy.sock"

Because the consuming snap's own private $XDG_RUNTIME_DIR/snap.<name>/
directory is where `%t/snap.%i/dbus-proxy.sock` resolves to for its own
instance name, no extra plumbing is needed on the consumer side beyond
removing its `dbus` plug and pointing DBUS_SESSION_BUS_ADDRESS at that
fixed per-snap path.

The socket unit existing/listening (rather than an ordinary
`daemon: simple` service mutter would have to wait for) is what matters
for ordering: it means the decoy socket is present and accepting
connections as soon as the unit graph reaches `sockets.target`,
independent of whether the proxy binary itself has finished starting up
— so a consumer's connect() to its decoy socket cannot race an
unstarted proxy process.

Remaining ordering requirement: the relevant
`dbus-proxy@<snap>.socket` instance must be active before
core-desktop-session-wrapper.sh's `exec "/snap/bin/$snap_cmd"` line
runs mutter (and, for any future consumer, before that consumer's own
confined daemon starts). This must be verified explicitly as part of
Step 5's testing (e.g. confirm the socket file exists and is listening
at the relevant point on a real boot) rather than assumed from
`sockets.target` ordering alone.

Verification gate: a fresh image build, full VM reboot (not the same
live-patched VM used for Steps 1-4), real autologin, and a real icon
click all pass exactly the Step 4 checks (a/b/c above) on this
from-scratch build. Also re-check the X11-socket bind-mount issue in
snapd's x11 interface — that is a SEPARATE, still-open bug and is not
expected to be fixed by this work; confirm this item doesn't
accidentally mask or get confused with it when judging "does the icon
click fully work now."

## Note on the stale prior "done" record

`20260926-xwayland-xauthority-private-runtime-dir.md` records an
EARLIER attempted fix for this same underlying leak (pinning
XDG_RUNTIME_DIR via snapcraft.yaml `environment:` overrides on the
gnome-shell/ubuntu-desktop-session apps) as "RESOLUTION: Fixed". That
fix was later found to be unsound and was reverted — as documented in
the App Store investigation's "Wrong fix that was tried and reverted"
section, redirecting XDG_RUNTIME_DIR wholesale caused AppArmor DENIED
errors (gnome-shell writing directly into /run/user/<uid>/ which its
profile doesn't grant) and broke the session entirely (Xwayland
crashes, sessions bouncing back to GDM). Do not repeat that approach.
That "done" record has not yet been corrected/reopened; whoever picks
up this work should flag its stale status rather than editing the
record directly (imported records are not edited ad hoc).

## Resolution (2026-09-27)

The GNOME environment leak was handled by integrating the patched
`gnome-session-service` with a filtered session-environment broker,
rather than inserting a transparent D-Bus proxy. The broker
authenticates the GNOME caller, filters and rewrites environment
updates, and is easier to audit and test for this known producer. A
generic proxy would add a session-bus routing layer that must preserve
unrelated traffic, replies, signals, and file descriptors; the broader
reuse benefit was hypothetical and did not justify that complexity
while the source of the environment updates was available to patch.
See `ubuntu-desktop-session-snap` commit
`c1f10338f6de7d43955a1b43115b0883a8d7d8be`.

This closes the proxy work for the GNOME path, not a general mechanism
for every desktop. KDE is not covered by the GNOME broker: inspection
found KWin publishing an `XAUTHORITY` path inside the Plasma session
snap's private runtime directory. Treat KDE filtering as a separate
source-side integration if pursued; do not build the generic proxy
solely on the assumption that GNOME's solution applies to KDE.
