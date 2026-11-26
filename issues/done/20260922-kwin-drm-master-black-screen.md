# KDE black screen = kwin never acquires DRM master (kernel-verified)

## Impact / Priority

KDE sessions intermittently came up as a pure black screen:
kwin_wayland never became DRM master, so its DRM atomic commit failed
and nothing was ever composited to the display. Every black screen
corresponded to logind holding DRM master; the "successful" logins were
the rare ordering where logind drops master and kwin grabs it. Impact
derived from the original note's described symptoms.

## Context

Date 2026-09-22, on the test VM, Core 26 KDE plasma-desktop-session.

## Definitive root cause (supersedes the "incomplete payload" theory)

The black screen is NOT AppArmor, NOT run-session.sh, NOT missing QML/
decoration/cursor plugins. It is:

    kwin_wayland never becomes DRM master, so its DRM atomic commit
    (drmModeAtomicCommit, the only way to present a frame on a KMS/atomic
    display) returns EPERM "Permission denied", and kwin composites nothing.

Kernel-verified repeatedly on the live VM via /sys/kernel/debug/dri/1/clients:

    systemd-logind  1059  1  y  y  0     <- logind holds DRM master (dev 1)
    kwin_wayland    28235 1  n  y  1000  <- kwin master=n (NOT master)

kwin's "master" bit is always n; logind's is y. Every black screen
corresponds to this state; the "successful" logins are the rare ordering
where logind drops master and kwin grabs it.

## Evidence chain

- kwin logs: "atomic commit failed: Permission denied" (the real fatal
  error).
- The "Failed to load cursor theme default", "Could not locate decoration
  plugin org.kde.breeze", "module org.kde.milou is not installed",
  "Failed to connect PipeWire" lines are ALL red herrings (benign,
  non-fatal).
- gnome-shell (the GDM greeter, unconfined) renders fine and logs
  "Created gbm renderer for /dev/dri/card1" + "using atomic mode
  setting".
- /dev/dri/card1 has ACL user:your_username:rw- (DAC fine). No AppArmor
  denial matches the atomic commit (AppArmor fine). So the gap is purely
  the logind DRM-master handoff.

## Why intermittent

Whether it renders depends on logind's DRM-master handoff timing vs when
kwin starts. First login after boot sometimes hands off cleanly; a
logout/login (greeter re-grabs card1) leaves logind holding master and
kwin denied.

## Fix direction (not yet implemented)

kwin must acquire DRM master via the systemd-logind device handshake
(TakeDevice / TakeControl on the session's seat device), which is what
GNOME's gnome-session/gnome-shell does but the KDE snap's
startplasma-wayland / kwin_wayland_wrapper path does NOT. Candidates:

- make startplasma/kwin call the logind TakeDevice/TakeControl
  handshake, or
- ensure the greeter releases DRM master before the session's kwin
  starts, or
- run kwin with a backend/flag that does not require DRM master (e.g.
  --virtual / nested) as a stopgap.

Manipulations already tried and proven INEFFECTIVE at giving kwin
master: `loginctl activate <session>`,
`loginctl terminate-session <greeter>`, `systemctl --user restart
plasma-kwin-wayland`. logind keeps master each time; kwin stays
master=n.

## Live verification (2026-09-22)

The note was validated against the live test VM. During the black
screen, the kernel DRM client table showed:

    systemd-logind  dev 1  master y
    kwin_wayland    dev 1  master n

The controlled test was:

1. Stop systemd-logind with `sudo systemctl stop systemd-logind.service`.
2. Terminate the specific existing kwin_wayland process so the KDE
   wrapper respawns it and it reopens /dev/dri/card1.
3. Re-read `/sys/kernel/debug/dri/1/clients`.

After the respawn, the new kwin_wayland instance showed `dev 1 master y`
and the display path was able to acquire DRM master. This confirms that
logind's held DRM-master fd is sufficient to explain the black screen;
the test does not depend on missing decoration, cursor, QML, PipeWire,
or AppArmor functionality.

systemd-logind and GDM were then restored with `sudo systemctl restart
gdm3.service`. Logging into KDE again reproduced the failure: KWin was
running but showed `dev 1 master n` while systemd-logind showed `dev 1
master y`, and the screen went black. Therefore the normal
GDM-to-Plasma handoff remains the reproducible fault.
