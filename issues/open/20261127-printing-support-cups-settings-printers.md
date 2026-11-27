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

## Approach: emulate the printer, then one physical pass

Do the implementation and as much verification as possible against a
software printer, and only take the result to real hardware once the
emulated matrix is green. The emulator is CUPS's own IPP Everywhere
printer application, `ippeveprinter`:

- It is already inside the cups snap as an app (`ippeveprinter`, with
  `network`, `network-bind`, `avahi-control`, `home` and `raw-usb`
  plugs), so it runs on the image under test with no extra packaging.
  The host has it too (`cups-ipp-utils`), which covers the
  cross-network case.
- It advertises itself over DNS-SD, serves IPP Everywhere, and writes
  every received job to a spool directory (`-k`), so discovery,
  driverless model generation, job submission and the document content
  itself are all observable and assertable in CI.
- Several instances on different ports emulate several printers
  (plain, duplex, authenticated, or one loaded from a specific PPD).

What it cannot emulate, and which therefore stays a hardware check:

- USB enumeration and hotplug. There is no usable USB-printer emulator
  here: `umockdev` fakes libusb only through LD_PRELOAD, which cannot
  reach a confined snap daemon; `ipp-usb` converts a real USB printer
  to IPP (the opposite direction); and USB/IP or QEMU `usb-host` both
  need a real device at the far end. A UDC-capable board presenting a
  printer-class gadget (`g_printer`/`raw-gadget`) is the only true
  emulation, and is not worth building unless the USB path turns out
  to hold the bugs.
- Legacy PPD-only printers: `-P <ppd>` advertises that model's
  attributes, but does not prove the image ships the right driver and
  ghostscript chain for it.
- Hardware faults: out of paper, jams, sleep/wake, colour accuracy.

So: implement and verify against the emulator, get all of Stage 1 below
green, and only then run Stage 2 once on a real printer - a network
AirPrint printer is enough to close it, with USB covered too if one is
available.

## Task

Make printing work end to end for a GNOME Core Desktop user: Settings >
Printers lists, adds, configures and removes printers, and applications
can print to them. Build it against the emulator described in
"Approach" and "Test rig": the only part that may wait for hardware is
the final physical pass.

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
   for why that matters for runtime-installed apps). Include
   `cups:avahi-control -> avahi:avahi-control`: without it cupsd (and
   the emulator) cannot advertise over DNS-SD, so discovery and
   `lpinfo -v` show nothing and only manual URIs work.
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
7. Land the emulator rig as a script (e.g. `tools/print-test.sh`):
   start `ippeveprinter`, print a known document through the image,
   assert the spool file, tear down. Keep it runnable by hand on a test
   VM too, since it is how most of this issue gets implemented.

## Test rig: ippeveprinter

On the image under test, inside the cups snap (no hardware, no
networking):

    sudo snap run cups.ippeveprinter -p 8631 -k -2 \
        -d /var/snap/cups/common/spooltest \
        -m "UCD Test Duplex" -l "Lab" -M "OpenPrinting" \
        "UCD Test Duplex"

(`-2` = reports duplex support; `-k` keeps the received files; `-d`
selects the spool directory.)

From the host, to exercise the network path (bridged/macvtap networking
in the VM - multicast does not cross QEMU user-mode NAT):

    ippeveprinter -p 8631 -k -2 -d /var/tmp/printspool \
        "UCD Test Duplex"

How to use it:

- Discovery: `ippfind` and `avahi-browse -rt _ipp._tcp` on the host, and
  `sudo snap run cups.ippfind` on the image, must list the service.
  This is what the Printers panel's device list is fed from. Inside the
  image the emulator needs the same `avahi-control` connection that
  cupsd uses (`snap connections cups`); without it it still serves IPP
  but is not discovered.
- Job proof: after printing, the spool directory holds the received
  document (PDF by default). Assert on it - file exists, expected page
  count, and a text or render match (`pdftotext`, or `pdftoppm -png` to
  look at it).
- More printers: further instances on 8632/8633 for a single-sided one,
  an `-A` authenticated one, and one loaded from a specific PPD with
  `-P /path/to/model.ppd`.
- CI: run the same command, print through the image, assert the spool
  file. This is the regression gate for printing; do not substitute the
  `file:` backend for it, which skips IPP and the driverless model path
  entirely.

## Verification

Two stages. Stage 1 is everything that can be done with the simulated
printer and must be fully green before Stage 2 starts; Stage 2 is the
single physical pass that repeats the same flows against real hardware.
Run both on a freshly built image (not a live-patched one) and record
the commands and output in this file. Stage 1 sections are tagged
`[emulated]`, Stage 2 `[hardware]`.

### A. Prerequisites: the daemon is up and the session can reach it

Applies to both stages.

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

### B. Add a printer over IPP [emulated]

1. Start the emulator per "Test rig" above - on the image itself, or on
   a bridged host. For the discovery checks it must be reachable from
   the image over the network.
2. Settings > Printers > Add Printer. Expected: the emulated printer
   appears in the discovered device list by itself (this is the
   avahi/cups-browsed path). If it does not, record that as a failed
   discovery check but continue.
3. Add it by URI as the fallback path:
   `ipp://<emulator-host>:8631/ipp/print`. Expected: the panel finds a
   driver automatically (driverless/IPP Everywhere) and adds the queue
   without asking for a PPD file - this is the same code path a real
   AirPrint printer uses.
4. Confirm the queue exists and is accepting work:
   `cups.lpstat -t` lists `<printer>` and shows "accepting requests",
   `cups.lpinfo -v` lists the `ipp://` device.
5. Print the panel's own test page (printer menu > Print Test Page).
   Expected: a job file appears in the emulator's spool directory and
   the queue shows a completed job.
6. Repeat with the second emulated instance (single-sided) and confirm
   the two queues are listed separately and the panel shows each
   printer's own options (duplex present only on the first).

### C. Physical pass: real printer [hardware]

Run this once, after every Stage 1 section is green. A network
AirPrint printer closes this step on its own; do the USB part too if a
USB printer is available, since USB enumeration cannot be emulated
(see "Approach").

Network (AirPrint) printer:

1. Put the printer on the same network as the VM (bridged/macvtap, not
   user-mode NAT - multicast discovery does not cross user-mode
   networking; see `docs/build-tools.md` QEMU networking notes).
2. Settings > Printers > Add Printer. Expected: the real printer is
   discovered by name, and adding it needs no PPD, exactly as with the
   emulator in step B.
3. Print the panel's test page: paper comes out. Then print from one
   application (D) and confirm the same.

USB printer:

4. Boot the image, log in, then plug the printer in (hotplug is the
   case that matters; also test a printer already attached at boot).
5. `lsusb` shows the printer; `dmesg | tail` shows it enumerating.
6. `cups.lpinfo -v` lists a `usb://<vendor>/<model>` device; Settings >
   Printers shows it in the discovered list.
7. Add it, then print the test page. Expected: output on paper, job
   completes.
8. Unplug and replug while the panel is open: the panel must not crash
   or hang, and the queue must go to "unplugged/stopped" rather than
   silently vanishing.

Anything that fails here but passed in Stage 1 is a hardware-only
defect: record it and keep this section open until it is fixed and
re-run.

### D. Print from applications [emulated]

1. GTK3 app: open a document, Ctrl+P. Expected: the print dialog lists
   the emulated printer, the options from its attributes (duplex on the
   `-2` instance) are populated, and the job lands in the spool
   directory as a valid PDF.
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

### E. Queue and job management in Settings > Printers [emulated]

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

### F. Persistence, reboot and multi-user [emulated]

1. Reboot with the queue configured (emulator restarted, same port and
   name): the printer is still there, still the default, and still
   prints. (Nothing in the chain may live in a tmpfs or a per-boot
   directory.)
2. Log in as a second local user: the queue is visible (queues are
   system-wide), and that user can print without re-adding it.
3. Log the second user out and back in while a job is queued: the job
   is unaffected.
4. Confirm the queue survives `snap refresh cups` (if the snap is
   refreshed between those steps), i.e. queue state lives in
   `$SNAP_COMMON`, not in the snap revision.

### G. Job-content assertion and CI gate [emulated]

This is the check CI runs; it must fail if printing regresses.

1. Print a known document to the emulated queue from an app and from
   `cups.lp`, then assert on the spool file: it exists, has the
   expected page count, and its text or rendered image matches what was
   sent (`pdftotext`, or `pdftoppm -png` and compare).
2. Assert the *absence* of the failure signatures instead of only a
   non-zero exit: no `apparmor="DENIED"` for the session/cups profiles
   in `journalctl -b`, no "Unable to connect to server" in the panel
   log, no job stuck in `cups.lpstat -o`.
3. Sanity-check the raw chain once, without IPP: a queue writing
   straight to a file (`cups.lpadmin -p ucd-test -E -v
   file:/var/snap/cups/common/ucd-test.out -m raw`, then `echo hello |
   cups.lp -d ucd-test`) must produce that file. This skips IPP and
   driverless, so it is a sanity check only - step 1 is the real gate.
4. Remove the test queues afterwards.

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

- Stage 1 (A-G, `[emulated]`) is fully green on a freshly built image
  against the `ippeveprinter` rig, with the commands and spool-file
  assertions recorded in this file.
- Stage 2 (C's `[hardware]` half) has been run once on a physical
  printer - a network AirPrint printer is sufficient; USB is covered
  too where hardware allows - and prints successfully end to end.
- The decisions in "Task" are recorded here, the wiring is documented
  in `docs/`, and the emulator rig plus its assertion is reachable in
  one command (work item 7) so CI can keep printing working.
- Anything not run (legacy PPD/driverless-less printers, hardware
  faults, USB if no device was available) is marked explicitly as
  untested rather than assumed to work.

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
