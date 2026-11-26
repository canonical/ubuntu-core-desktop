# snapd: private /tmp is per-snap, not per-user; cross-uid collisions inherent

Date: 2026-11-20

Found during the Ubuntu Core Desktop a11y gate-8 session (the
companion to the mutter ownership-check issue; the full incident is
written up in the T53 tmpfs-collision-fix session notes and the
a11y spike todo's [2026-11-18] entries).

## Impact / Priority

After the first-boot wizard creates the user, that user's first
login to the desktop fails: their confined mutter finds
/tmp/.X11-unix owned by the wizard session's dynamic uid and refuses
it, and gnome-shell SIGABRTs — a login "failure" that looks like a
password problem. On this project's own deployment the defect is
currently masked by a boot-time root-owned normalization (the
session snap's ensure-x11-dir daemon:oneshot); it remains for any
multi-user snap writing /tmp content without that workaround.

Impact derived from the original note's symptoms.

## The mechanism (pinned from source: snap-confine's
   InterfacesTmpFiles / the per-snap tmpfs bind, verified live)

snap-confine mounts a PRIVATE TMPFS over /tmp for every confined
process of a snap — ONE tmpfs PER SNAP, SHARED by all users of that
snap (the mount is per-snap-instance, not per-user; root:root 01777
over /tmp). Any /tmp content a snap process creates is therefore
shared by every later session of that snap, regardless of which
user runs it.

## The live incident (verbatim)

The first-boot wizard session (dynamic uid 60578) ran a confined
mutter that created /tmp/.X11-unix owned by 60578 inside the shared
per-snap tmpfs. The created user (uid 1000) then logged in: their
confined mutter found the dir owned by a foreign uid and refused it
(mutter's ownership check — a companion mutter issue), and
gnome-shell SIGABRT'd: the login "failure" that looked like a
password problem for days.

## The design flaw

For any multi-user snap whose processes write /tmp content (display
servers, indexers, daemons with sockets), the per-snap shared tmpfs
makes cross-uid ownership collisions INHERENT: the first session's
uid owns the dir, every later session with a different uid trips
the ownership checks of whatever consumes it.

## The upstream ask (candidates, to discuss with snapd maintainers)

a. Per-USER private tmpfs (the tmpfs mounted per (snap, uid) pair
   instead of per snap) — the cleanest isolation; the cost: the
   inter-user snap-socket sharing needs the explicit paths (the
   existing snapd socket-sharing mechanism covers the declared
   slots).
b. snapd pre-creates the standard root-owned entries in the snap
   tmpfs at the first mount (e.g. /tmp/.X11-unix root:root 1777 per
   the classic X layout) — the minimal fix for the display-server
   class.

## Tasks

1. UPSTREAM-FIRST: search snapd's GitLab for the private-tmpfs
   design discussions (the InterfacesTmpFiles / the BROWSER_
   TESTING... the snap-confine tmpfs mount) and any prior per-user
   proposals.
2. THE MINIMAL REPRO: a snap with two users running its confined
   app, each creating a /tmp file with the strict perms — the
   second user's process sees the first user's file (the shared
   tmpfs) and/or fails the ownership-sensitive operations.
3. THE PROPOSAL: per-user tmpfs vs the pre-created root-owned
   entries — the design note with the trade-offs (the socket
   sharing across the users of the same snap needs the explicit
   mechanism either way).
4. SUBMIT to snapd upstream (the same channel as the tracking-
   flake and revert-orphans candidates — the snapd issues list is
   tracked in the spike todo's upstream-candidates entries).

## Status

[2026-11-20] Issue created. NOT STARTED. Our own deployment is
masked by the boot-time root-owned normalization (the session
snap's ensure-x11-dir daemon:oneshot) — the upstream defect
remains for any multi-user snap writing /tmp content without
that workaround.
