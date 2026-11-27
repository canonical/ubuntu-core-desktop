# Printing: make Settings > Printers and printing from apps work

## Impact / Priority

High. A user who plugs in a USB printer or has an IPP/AirPrint printer
on the network expects to open Settings > Printers, see it, add it, and
print from any application. On the current image none of that can work:
the image ships no CUPS daemon at all, so the Printers panel can only
ever show an empty list and every application's print dialog shows no
destinations. Printing is a baseline desktop feature, and a user with a
printer has no path forward in the GUI (and no useful error either).
Priority derived from that expected end-user behaviour; nobody has yet
run the end-to-end test below, so the exact failure mode per step is
unconfirmed.

## Current state (checked 2026-11-27)

The printing chain is unbuilt, not merely broken:

- No CUPS daemon anywhere in the image.
  `ci/ubuntu-core-desktop-26-amd64.model` ships `avahi` but no `cups`
  snap. The KDE gadget list
  (`kde_gadget_connections` in `build.sh`) already declares
  `plasma-desktop-session:cups-control -> cups:cups-control` and
  `:avahi-control -> avahi:avahi-control`, pointing at the OpenPrinting
  `cups` snap (id `m1eQacDdXCthEwWQrESei3Zao3d5gfJF`, 2.4.20-1, base
  core26, `raw-usb` + `avahi-control` + `cups-host` plugs on cupsd);
  with no such snap in the image those connections are ignored. The
  GNOME gadget list has no cups/avahi connection at all.
- `ubuntu-desktop-session-snap` declares snap-level `cups-control` and
  `avahi-control` plugs, but no app references them (each name occurs
  exactly once, as the definition). In particular
  `gnome-control-center`'s plug list has no `cups-control`, no
  `avahi-control`, no `polkit-agent` and no `network`, so it has no
  mediated path to a cupsd even if one were running.
- No `cups-pk-helper` and no polkit policy for it in
  `gnome-desktop-runtime` (`unsquashfs -l` finds neither a
  `cupspkhelper` policy file nor a helper). The panel's admin path is
  real and hardcoded, so this is a concrete blocker, not a theory:
  strings in `usr/bin/gnome-control-center` reference
  `org.opensuse.CupsPkHelper.Mechanism` and the polkit action
  `org.opensuse.cupspkhelper.mechanism.all-edit`, and the panel carries
  the message "Your system does not have the cups-pk-helper's policy
  \"org.opensuse.cupspkhelper.mechanism.all-edit\" installed. Please
  check your installation" - which is exactly what a user will see when
  they press Add Printer or Unlock once cupsd exists. libcups alone
  can only query queues; it cannot add or modify them.
- `gsd-print-notifications` is wired as a session app (D-Bus
  `org.gnome.SettingsDaemon.PrintNotifications`), and `gsd-printer`
  exists in the runtime with no app wrapper; both are inert without
  cupsd.

What does already exist (so this is mostly wiring, not new packaging):

- GNOME's Printers panel itself: `gnome-printers-panel.desktop` and
  `gnome-control-center-print-renderer` in `gnome-desktop-runtime`.
- GTK3's CUPS print backend (`libprintbackend-cups.so`) plus
  `libcups.so.2` in `gnome-desktop-runtime`. GTK4 (4.14+) links its
  CUPS backend statically instead of shipping a module - do not
  conclude "missing backend" from the absence of a
  `gtk-4.0/*/printbackends` directory; verify by printing.
- The base's `/var/cups` mkdir workaround in
  `core-base-desktop/hooks/020-extra-files.chroot`, which exists to stop
  the `cups` interface creating writable mimics.

## Task

Make printing work end to end for a GNOME Core Desktop user: Settings >
Printers lists, adds, configures and removes printers, and applications
can print to them.

Decisions to take first (record them in this file when decided):

1. Provider. Use the OpenPrinting `cups` snap (already referenced by
   the KDE gadget connections, already supports core26 and USB via
   `raw-usb`) or build our own provider snap. Prefer the existing one
   unless it fails the USB/network tests below.
2. Transport to clients. The `cups` snap offers both the classic
   `cups-control` interface and a `cups` content slot
   (`cups-socket-directory: $SNAP_COMMON/run`), and it falls back to
   `$SNAP_COMMON/run/cups.sock` and port 10631 if `/run/cups/cups.sock`
   or TCP 631 are already taken. Pick one and make every client path
   below use it consistently; do not leave clients guessing between
   the socket, TCP 631 and TCP 10631.
3. Admin path. Add `cups-pk-helper` (plus its polkit policy) to the
   session content, and give `gnome-control-center` the `polkit-agent`
   and appropriate `cups-control`/`cups` plug, or justify a different
   mechanism in this file.
4. Discovery. Keep the `avahi` snap (already in the model) and decide
   whether `cups-browsed` (part of the cups snap) is the discovery
   path, so the panel's device list is populated without the user
   typing a URI.

## Work items

1. Add the cups snap to the GNOME model (and keep it in the KDE model,
   where the connections are already declared but the snap is absent),
   with the `avahi`/`cups`/`cups-control` connections in
   `gnome_gadget_connections`/`kde_gadget_connections` rather than a
   runtime retry loop (gadget connections only apply at seed/remodel
   time - see
   `20260915-app-center-installed-snaps-need-desktop-interface-connections.md`
   for why that matters for runtime-installed apps).
2. Extend `gnome-control-center`'s plugs in the session snap
   (`cups-control`, `polkit-agent`, and `network` if clients are to use
   TCP), and add `cups-pk-helper` + its polkit policy to
   `gnome-desktop-runtime`.
3. Wrap `gsd-printer` as a session app if the notification daemon needs
   it (it is the CUPS-queue event source that fans out to
   `gsd-print-notifications`).
4. Make the panel's admin requests actually reach the helper: verify
   the polkit action is prompted and granted for a normal user in the
   `sudo`/`admin` group on this image (see the `polkit-client`
   investigation for how confined clients prompt:
   `20261029-polkit-client-interface-for-kcm-prompts.md`).
5. Decide the app story for non-session snaps (Store-installed apps
   that print): `cups`/`cups-control` are deny-auto-connection, so a
   store app gets no printer access unless the user connects it. Decide
   whether that is acceptable and document the `snap connect <app>:cups`
   incantation, or whether the session should expose a socket every app
   inherits.
6. Document the result in `docs/` (a "printing" section in
   `gdm-graphical-session.md` or a new short doc): which snap provides
   cupsd, which socket/port clients use, which interface is connected
   where, and how to debug a stuck queue.

## Verification

Run on a freshly built image, not a live-patched one, and record the
commands and their output in this file. A physical printer is
preferred; the no-hardware path in step G is mandatory too, because it
is what CI can run.

### A. Prerequisites: the daemon is up and the session can reach it

1. `snap list cups avahi` and `snap connections | grep -i cups` -
   cupsd's system daemon is active, and every intended plug
   (`ubuntu-desktop-session:cups-control` or `:cups`,
   `plasma-desktop-session:cups-control`) shows a connected slot.
2. `snap services cups` shows `cups.cupsd` (and `cups.cups-browsed` if
   discovery relies on it) enabled and active; `snap logs -n 100
   cups.cupsd` has no bind/permission error.
3. From the host, `cups.lpstat -h /run/cups/cups.sock -t` (or
   `cups.lpstat -t`) reports the scheduler is running and lists zero or
   more queues.
4. Open Settings > Printers. Expected: the panel opens without an error
   banner and the list is empty (not stuck on a spinner).
5. From inside a session app's confinement, the socket is reachable:
   the panel is not a shell, so use the panel itself plus
   `journalctl -b --user | grep -i print` to confirm it did not log
   "Failed to connect to server" / EACCES when it queried cupsd.
6. The admin helper is present: open Settings > Printers, press Add
   Printer (or Unlock). Expected: no message about
   "cups-pk-helper's policy ... installed". That exact message means
   the helper/policy from "Current state" is still missing, and no
   printer can be added or modified from the GUI regardless of cupsd.

### B. Add a network (IPP/AirPrint) printer

1. Put the printer on the same network as the VM (bridged/macvtap, not
   user-mode NAT - multicast discovery does not cross user-mode
   networking; see `docs/build-tools.md` QEMU networking notes).
2. Settings > Printers > Add Printer. Expected: the printer appears in
   the discovered device list by itself (this is the avahi/cups-browsed
   path). If it does not, note that as a failed discovery check but
   continue.
3. Add it by URI as the fallback path: enter
   `ipp://<printer-ip>/ipp/print` (or the URI the printer reports).
   Expected: the panel finds a driver automatically (driverless/IPP
   Everywhere) and adds the queue without asking for a PPD file.
4. Confirm the queue exists and is accepting work:
   `cups.lpstat -t` lists `<printer>` and shows "accepting requests",
   `cups.lpinfo -v` lists the `ipp://` device.
5. Print the panel's own test page (printer menu > Print Test Page).
   Expected: paper comes out, and the queue shows a completed job.

### C. Add a USB printer

1. Boot the image, log in, then plug the printer in (hotplug is the
   case that matters; also test a printer already attached at boot).
2. `lsusb` shows the printer; `dmesg | tail` shows it enumerating.
3. `cups.lpinfo -v` lists a `usb://<vendor>/<model>` device; Settings >
   Printers shows it in the discovered list.
4. Add it, then print the test page. Expected: output on paper, job
   completes.
5. Unplug and replug while the panel is open: the panel must not crash
   or hang, and the queue must go to "unplugged/stopped" rather than
   silently vanishing.

### D. Print from applications

1. GTK3 app: open a document, Ctrl+P. Expected: the print dialog lists
   the added printer, paper size/duplex options are populated, and
   printing produces output on paper.
2. GTK4 app: same check. (This is the one that proves the "no
   printbackends directory" question above is a non-issue.)
3. A non-GTK app that prints (LibreOffice or any Qt app present in the
   image): same check.
4. "Print to File" / "Save as PDF" still works with cupsd stopped -
   this is the negative control proving the dialog itself is fine when
   CUPS is not.
5. A Store-installed app (e.g. LibreOffice from the store if not
   preinstalled): record whether the printer appears, and whether
   `snap connect <app>:cups cups:cups-host` changes it. Whatever the
   answer, it must match the decision in work item 5.

### E. Queue and job management in Settings > Printers

1. The printer's detail page shows state (idle/processing/stopped),
   location, model/driver, and its job list.
2. Print two jobs, then cancel one from the panel. Expected: the
   cancelled job disappears from `cups.lpstat -o` and the other
   completes.
3. Disable the printer (or stop cupsd's queue), print, re-enable:
   the job is held and then prints, and the panel reflects the state
   change.
4. Set the printer as default; confirm `cups.lpoptions` reports it and
   that a print from an app with "no printer chosen" goes there.
5. Remove the printer from the panel: it disappears from `cups.lpstat
   -t`, and Settings > Printers goes back to the empty state.
6. Add, then re-add the same printer: no duplicate queue is created.

### F. Persistence, reboot and multi-user

1. Reboot with the queue configured: the printer is still there, still
   the default, and still prints. (Nothing in the chain may live in a
   tmpfs or a per-boot directory.)
2. Log in as a second local user: the queue is visible (queues are
   system-wide), and that user can print without re-adding it.
3. Log the second user out and back in while a job is queued: the job
   is unaffected.
4. Confirm the queue survives `snap refresh cups` (if the snap is
   refreshed between those steps), i.e. queue state lives in
   `$SNAP_COMMON`, not in the snap revision.

### G. No-hardware path (mandatory, this is the CI-runnable check)

1. Add a queue that writes to a file instead of a device:
   `cups.lpadmin -p ucd-test -E`
   `-v file:/var/snap/cups/common/ucd-test.out -m raw`
   (or through the panel if it accepts a manual `file:` URI), then
   `cups.lpstat -t` shows `ucd-test`.
2. `echo hello | cups.lp -d ucd-test` and confirm
   `/var/snap/cups/common/ucd-test.out` appears and contains
   "hello". This proves the client -> cupsd -> filter -> backend chain
   including confinement and the socket/port choice, without hardware.
3. Do the same through a GUI app (print the app's document to
   `ucd-test`) and confirm the file grows.
4. Remove the queue afterwards.

### H. Evidence to collect when any step fails

- `snap connections | grep -Ei 'cups|avahi'` and `snap interface
  cups-control`.
- `journalctl -b` filtered for `cups`, `apparmor="DENIED"` with
  `cups`, and the session snap's profile; `snap logs -n 200 cups.cupsd`
  and `... cups.cups-browsed`.
- The panel's own failure text (screenshot), plus
  `journalctl -b --user | grep -i print`, and whether polkit logged a
  prompt/dismissal for the cups-pk-helper action.
- `cups.lpstat -t`, `cups.lpinfo -v`, `cups.lpoptions -p <printer> -l`,
  and the cupsd.conf `Listen`/`Port` lines actually in use.

## Definition of done

Steps A-G pass on a freshly built image with a real printer (network and
USB) and with the no-hardware queue, the decisions in "Task" are
recorded here, and the wiring is documented in `docs/`. Steps that
cannot be run for lack of hardware must be marked explicitly as
untested rather than assumed.

## References

- `20260915-app-center-installed-snaps-need-desktop-interface-connections.md`
  - runtime-installed apps get no gadget connections; same problem class
  as a Store app that needs `cups`.
- `20261029-polkit-client-interface-for-kcm-prompts.md` - confined
  clients prompting through polkit, which is also the Add Printer path.
- `20260927-gnome-keyring-secret-service-activation.md` - same pattern
  of "system service exists but nothing in the session can activate or
  reach it".
- `docs/core-base-desktop.md` (base build, `/var/cups` workaround) and
  `docs/gdm-graphical-session.md` (session snap architecture).
