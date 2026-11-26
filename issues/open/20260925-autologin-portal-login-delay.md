# autologin still has a ~25-27s black-screen delay despite the manual-login fix

## Impact / Priority

Medium-High. Password-based GDM login is reported working after the
xdg-desktop-portal ordering fix, but enabling GDM autologin on
core26-desktop still leaves a black screen for roughly 25-27 seconds
before the desktop appears. The desktop eventually starts; this is a
startup delay rather than a permanent session failure.

## Reproduction

VM: the core-desktop test VM.

GDM was configured with:

    [daemon]
    AutomaticLoginEnable = true
    AutomaticLogin = your_username

The fresh autologin boot/session showed:

    Starting org.gnome.Shell@ubuntu.service       [220.465296]
    Starting xdg-desktop-portal.service            [220.689725]
    Started org.gnome.Shell@ubuntu.service        [246.478583]
    portal is not running: Timeout was reached    [271.656093]
    xdg-desktop-portal.service: start operation
        timed out                                   [310.834444]

The GNOME Shell startup interval is 26.013 seconds. Later attempts
after restarting GDM reproduced the same pattern:

    Starting org.gnome.Shell@ubuntu.service       [777.339651]
    Started org.gnome.Shell@ubuntu.service        [802.937127]
    portal is not running: Timeout was reached    [828.049152]

The user observed the corresponding black screen and confirmed that the
desktop eventually returned.

## What is already fixed / ruled out

The main `/usr/lib/systemd/user/xdg-desktop-portal.service` on the VM
does not contain `After=graphical-session.target`; it contains only:

    PartOf=graphical-session.target
    Requires=dbus.service
    After=dbus.service

The shipped GTK portal unit likewise has no
`After=graphical-session.target`. The earlier manual-login bug was
fixed in core-base-desktop by replacing those units rather than using a
drop-in reset.

The VM's boot-time session-connection service was also complete before
this autologin session began. Its AppArmor profile reloads finished at
approximately monotonic time 219.82, the service finished at 219.886,
and the autologin session opened at 220.051. This is therefore not the
previous first-login race where GDM accepted a login while
`ensure-desktop-session-connections.service` was still rebuilding the
confined snap profile.

The relevant GNOME portal implementation still contains:

    After=graphical-session.target
    Requisite=graphical-session.target

in `/lib/systemd/user/xdg-desktop-portal-gnome.service`. The snap
replacement unit used on this image has no equivalent ordering, but the
implementation is still part of the portal activation path.

## Autologin session-selection experiment

The initial autologin process inherited:

    GDMSESSION=gnome-greeter
    DESKTOP_SESSION=gnome-greeter
    XDG_CURRENT_DESKTOP=GNOME-Greeter:GNOME

This was suspected to be the difference from a manual
`ubuntu-desktop-session` login. The experiment:

1. Backed up `/var/lib/AccountsService/users/your_username`.
2. Set its AccountsService session to `ubuntu-desktop-session`.
3. Applied the live D-Bus `SetSession` update and restarted GDM.
4. Confirmed the resulting launcher inherited:

       GDMSESSION=ubuntu-desktop-session
       DESKTOP_SESSION=ubuntu-desktop-session
       XDG_CURRENT_DESKTOP=ubuntu:GNOME

This did not remove the delay. GNOME Shell still took approximately
25-26 seconds to become ready, and the portal still logged `portal is
not running: Timeout was reached`. The AccountsService file and live
property were restored to their original empty session state afterward.
GDM was restarted again and returned to the normal autologin desktop.

## Current interpretation

The autologin path still causes confined GNOME Shell to request
`org.freedesktop.portal.Desktop` synchronously before
`graphical-session.target` is active. The portal implementation also
has an ordering/requisite relationship with that target. This remains a
circular startup path, but the exact reason it is exercised by
autologin while ordinary password login is reported fixed is not yet
proven.

The AccountsService session identity is not sufficient to fix it. The
remaining difference may be the timing and launch context of autologin:
GDM starts the user session immediately as part of its own startup,
whereas a password login starts later through the selected desktop
entry. Compare a clean manual login and autologin from the same boot,
including the complete user-manager environment, session target
timestamps, portal activation, and GNOME Shell D-Bus calls.

## Next steps

1. Capture a clean password-login and autologin pair on the same image
   and compare:

   - `GDMSESSION`, `DESKTOP_SESSION`, `XDG_*`, and `SNAP_*` variables;
   - `gnome-session@ubuntu.target` and `graphical-session.target`
     activation times;
   - portal and portal-backend activation order;
   - GNOME Shell's first D-Bus request for
     `org.freedesktop.portal.Desktop`.

2. Inspect the loaded user-manager graph with
   `systemd-analyze --user critical-chain` and verify whether the portal
   GNOME implementation is being activated through the packaged
   `/lib/systemd/user` unit or the snap-generated replacement.
3. Test a supported full replacement of
   `xdg-desktop-portal-gnome.service` with the same ordering relaxation
   used for the main and GTK portal units. Do not edit the packaged
   unit in place.
4. If removing the GNOME implementation ordering does not help, obtain
   a GNOME Shell backtrace or strace for the first portal request in
   autologin and manual sessions; the current logs prove the wait but
   not the exact synchronous call site.

State: Reproduced on 2026-09-25; manual-login fix remains intact;
autologin-specific cause unresolved. The VM test configuration was
restored after the failed session-selection experiment.

Update (2026-09-26): the unrelated xdg-document-portal/FUSE-mount
crash-loop bug (fixed by the FUSE-mount broker work) was initially
suspected as a possible contributing cause of this delay. Confirmed NOT
related: with that bug fully fixed and xdg-document-portal starting
cleanly on first try, this exact same ~25-27s "portal is not running:
Timeout was reached" / org.freedesktop.portal.Desktop timeout pattern
still reproduces identically on a fresh autologin boot. This rules out
xdg-document-portal's startup reliability as a cause — the remaining
suspects are still the org.freedesktop.portal.Desktop /
graphical-session.target ordering and/or colord, as originally noted
above. Still open.

Update (2026-09-27): on a fresh autologin boot with the
`G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START_AT_CONSTRUCTION` portal fix, the
PAM session opened at monotonic 232.255, GNOME Shell started at
232.797 and reached `Started` at 234.554, and DING launched at 236.348.
The portal was requested at 232.995 and reached `Started` at 233.419.
The 25-27-second black-screen delay was not reproduced in this run.
This was not paired with a manual-login boot, so the issue remains open
pending the comparison above and confirmation on another fresh boot.
