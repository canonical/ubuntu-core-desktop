# Remove the App Center sudo/setuid workaround and use the normal polkit path

Date: 2026-09-15

## Impact / Priority

Installing Firefox from the Core Desktop 26 App Center failed with a
polkit diagnostic ("incorrect permissions on
/usr/lib/polkit-1/polkit-agent-helper-1 / Needs to be setuid root"); the
local workaround made the helper setuid and let the install proceed, but
the desktop session was then lost during snap installation/profile
updates. Impact derived from the original note's symptoms. No
priority level was stated in the original note.

Image: Ubuntu Core Desktop 26 amd64 dangerous

## Summary

Firefox installation from the Core Desktop 26 App Center reported:

    incorrect permissions on /usr/lib/polkit-1/polkit-agent-helper-1
    Needs to be setuid root

The current workaround changes that helper from mode 0755 to 04755 while
repacking the custom core snap during the image build (`build.sh`). This
is not the correct product fix. A regular Ubuntu 26.04 desktop uses a
non-setuid helper at this path and performs authorization through the
privileged polkit service and the logged-in polkit authentication agent.
Core Desktop should use the same polkit model rather than requiring a
sudo/setuid escape hatch.

## Investigation

1. The source Core 26 snap at core-base-desktop's `core.snap` contained:

       -rwxr-xr-x root root ... /usr/lib/polkit-1/polkit-agent-helper-1

   The generated custom-core.snap contained the same 0755 mode before
   the workaround was added.

2. The Ubuntu 24 VM successfully installed Firefox and ran it confined.
   The regular development host also has the helper at mode 0755:

       -rwxr-xr-x root root ... /usr/lib/polkit-1/polkit-agent-helper-1

   Therefore 04755 is not a universal Ubuntu requirement and should not
   be imposed on the Core Desktop image without evidence that the base
   system requires it.

3. The 04755 workaround was added to the image build (`build.sh`) and
   the image was rebuilt. The rebuilt VM showed:

       -rwsr-xr-x root root ... /usr/lib/polkit-1/polkit-agent-helper-1

4. Firefox installation then progressed through snapd:

   * snapd began installing Firefox at 19:38:34 UTC;
   * Firefox was mounted and snapd reloaded snap-confine profiles at
     19:38:45;
   * at 19:39:16 the active GNOME Shell session shut down;
   * snap-store reported "Error flushing display: Connection reset by
     peer";
   * the user PAM session closed and systemd stopped GDM cleanly.

   This demonstrates that changing the helper mode does not provide a
   safe end-to-end solution. It allowed installation to proceed, but the
   desktop session was then lost during snap installation/profile
   updates.

## Correct fix

Use Polkit 127's systemd socket-activated helper instead of the setuid
fallback:

* leave `/usr/lib/polkit-1/polkit-agent-helper-1` at mode 0755;
* enable `polkit-agent-helper.socket` in the factory writable `/etc`
  seed, so `/run/polkit/agent-helper.socket` exists after boot;
* allow the connected `polkit-agent` snap to access only that pathname
  socket, while retaining its legacy helper policy for older systems;
* keep polkitd, the logged-in GNOME authentication agent, and the App
  Center/snapd interfaces confined as before.

Do not make the helper setuid merely to silence the diagnostic or grant
the App Center unrestricted root access.

## Validation

1. Build the Snapd snap and the GNOME image with their repository build
   scripts, then boot the image in a test VM.
2. Confirm the helper remains 0755, the socket unit is enabled and
   active, and GNOME Shell's generated AppArmor profile contains the
   socket rule.
3. Confirm a confined GNOME Shell process can connect and systemd starts
   the per-connection helper.
4. Confirm a polkit authentication agent is present in the logged-in
   session.
5. Install Firefox from App Center without sudo.
6. Confirm the install completes, the GNOME session remains alive, GDM
   stays active, and Firefox is strictly confined.
7. Check the journal for polkit authorization failures, snapd profile
   reload errors, and desktop-session AppArmor/D-Bus denials.

Do not mark this work complete if installation only succeeds after
setting the helper setuid or if the graphical session is terminated
during install.

## Follow-up (2026-09-29)

The GNOME Shell process root sees the helper from its stock core26
base, at mode 0755; the helper is not from the GNOME content mount. The
separate 04755 helper seen by Snap Store is irrelevant to GNOME Shell's
polkit agent.

The host has Polkit 127's `polkit-agent-helper.socket` unit and the
socket-activated helper service, but the socket was disabled and
inactive. Polkit's agent library checks for
`/run/polkit/agent-helper.socket`; when it is absent, it falls back to
direct execution and reports that the helper needs to be setuid root.
The snapd `polkit-agent` interface also lacked permission for the
confined agent to access this pathname socket.

The source changes remove the helper's setuid chmod from
`ubuntu-core-desktop/build.sh`, enable the socket through the factory
writable `/etc` seed, and add a narrow socket-file rule to snapd's
`polkit-agent` interface. The Snapd snap and GNOME image were rebuilt in
an isolated worktree. The new test VM booted with the helper at 0755,
the socket enabled and active, and the generated GNOME Shell profile
containing the socket rule. A confined GNOME Shell process connected to
the socket and systemd started the per-connection helper.

On the user's test VM, the user entered their password at the expected
App Center Polkit prompt and Firefox installed successfully: revision
8969, strict confinement. The socket-activated helper completed
successfully, and GDM/GNOME remained active through snapd's profile
reload. The helper mode on that older live image was still 04755; the
separately rebuilt image confirmed the fixed source leaves it 0755. The
live VM's socket enablement and temporary AppArmor rule were used to
test the fix before a full image refresh.

## Resolution (2026-09-29)

Resolved by enabling Polkit 127's systemd helper socket and allowing the
connected `polkit-agent` plug to access its pathname socket. The setuid
workaround is removed from the image build. Commits: `0540d62868` in
`ubuntu-core-desktop-snapd` and `341774c` in `ubuntu-core-desktop`.
End-to-end Firefox installation succeeded without restarting the VM, and
the desktop session survived. Other Stage 2.6 verification gates remain
open in `20260922-split-core26-desktop-base-snap.md`.
