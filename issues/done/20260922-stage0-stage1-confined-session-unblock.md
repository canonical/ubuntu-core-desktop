# Stage 0/1 completed: confined GNOME session unblock (core26-desktop)

## Impact / Priority

Before this unblock, the confined GNOME session on Core 26 silently
lost confinement partway through startup: gnome-session delegates to
`systemd --user`, which ran unconfined, so gnome-shell and every
`org.gnome.SettingsDaemon.*` unit came up unconfined too. Impact derived
from the original note's described symptoms.

## Context

Status: DONE. This documents work that was already completed and
verified — kept as a historical record, not an open task. Extracted
from `proposed-plan.md`'s "Stage 0" and "Stage 1" sections when that
plan was processed and archived (Stage 2/3 remain open — see
`20260922-split-core26-desktop-base-snap.md`).

## What was done

Stage 0 (prep, done prior to the plan being written):

- Restored the GDM-registers-a-session fix (kept the
  `org.gnome.Shell@.service` unit template in core-base-desktop).
- Extended the `systemd-user-control` AppArmor interface with GetUnit +
  per-unit Properties.Get/GetAll (a deliberately broad stopgap — see
  "known follow-up" below).
- Got the full build+boot pipeline working end-to-end for the "24"
  variant.

Stage 1 (the actual unblock, confirmed live):

- Used the "custom base" tactic (Option A in `proposed-plan.md`):
  `ubuntu-desktop-session-snap` uses `base: core26-desktop`
  (build-base: core26) and plugs `systemd-user-control`.
  `scripts/run-session.sh` invokes plain `gnome-session --session=ubuntu`
  (no `--builtin` — upstream gnome-session on Core 26 dropped that flag
  entirely).
- Fixed a real confinement-loss bug found during verification: the
  confined session used to lose confinement partway through startup,
  because gnome-session delegates to `systemd --user`, which ran
  unconfined, so gnome-shell/gnome-settings-daemon units came up
  unconfined too. Fixed via static systemd drop-ins setting
  `AppArmorProfile=snap.ubuntu-desktop-session.ubuntu-desktop-session`
  on `gnome-session-manager@ubuntu.service`,
  `org.gnome.Shell@ubuntu.service`, and every
  `org.gnome.SettingsDaemon.*.service` unit (shipped in
  core-base-desktop's `static/usr/lib/systemd/user/<unit>.d/` overlay),
  with companion AppArmor policy in ubuntu-core-desktop-snapd's
  `interfaces/builtin/desktop_launch.go`,
  `interfaces/builtin/systemd_user_control.go`, and
  `interfaces/builtin/login_session_observe.go`.
- Verified end-to-end: confined session boots, comes up fully confined
  (checked via /proc/<pid>/attr/current on gnome-shell, gnome-session,
  and dbus-activated services), no org.freedesktop.systemd1 AppArmor
  denials, and basic desktop functionality (terminal, nautilus,
  screenshot) works.

Result: this is the currently-shipping architecture (confirmed live in
the codebase as of 2026-09-22 —
`ubuntu-desktop-session-snap/snap/snapcraft.yaml` still uses
`base: bare` + `build-base: core26` with content coming from the
`core26-desktop` base, and the project's verification notes document it
as working end-to-end). It is explicitly a tactical unblock, not the
long-term architecture — see `20260922-split-core26-desktop-base-snap.md`
for the Stage 2 (content interface) and Stage 3 (further snap splitting)
work that supersedes it.

## Known follow-up not yet done (carried into the base-splitting plan)

- The `systemd-user-control` AppArmor rules added in Stage 0 are broad
  (arbitrary unit-path wildcard). This was always meant as an internal
  stopgap, with a properly-scoped replacement (a restricted D-Bus proxy
  with an allow-listed unit-name set) to be designed once there's real
  usage experience — this is carried forward as its own step in the
  base-splitting plan.
- Two other open issues were also noted during verification but are
  unrelated to the Stage 1 unblock itself: gdk-pixbuf SVG loading can
  fail even after generating loaders.cache, and gnome-session can fail
  to start if a build hook strips the `org.gnome.Shell@.service` unit
  template. The project's verification notes track the current status of
  these.
