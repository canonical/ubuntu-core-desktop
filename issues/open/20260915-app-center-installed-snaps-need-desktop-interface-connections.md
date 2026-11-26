# App Center apps have no display path and silently fail to launch

Date: 2026-09-15

## Impact / Priority

Display part: reproduced end-to-end (Firefox installed from App Center:
every "Open" click does nothing, no window, no error, short-lived zombie
`snap run firefox` processes accumulate - see Summary/Root cause below).
High for anyone using App Center on this image: third-party apps are
simply dead on launch.

Audio part (scope added 2026-10-29): same root cause suspected, but the
end-to-end impact is NOT yet reproduced - expected symptom is "app
launches but produces no sound" once the display plugs are connected;
needs the investigation in the 2026-10-29 update below before a priority
can be honestly rated (degraded-but-usable vs app-dead).

Image: Ubuntu Core Desktop 26 amd64 dangerous (desktop26)

## Summary

While retesting the gnome-46-2404/mesa-2404/snap-store-2/stable dependency
update (see `20260915-remove-app-center-sudo-workaround.md`), Firefox was
installed from App Center and appeared to install successfully, but
clicking "Open" did nothing -- repeatedly. No window ever appeared, no
error was shown to the user, and no crash occurred.

## Root cause

`snap connections firefox` showed `wayland`, `x11`, and `desktop` all
unconnected (`-`):

    desktop       firefox:desktop       -   -
    wayland       firefox:wayland       -   -
    x11           firefox:x11           -   -

By contrast, `snap-store` has these same three interfaces manually
connected to `ubuntu-desktop-session`'s slots (baked in by a boot-time
`snap connect` retry loop in the image build):

    desktop   snap-store:desktop   ubuntu-desktop-session:desktop   manual
    wayland   snap-store:wayland   ubuntu-desktop-session:wayland   manual
    x11       snap-store:x11       ubuntu-desktop-session:x11       manual

Every attempt to launch Firefox spawned real processes
(snap-confine/desktop-launch/firefox) which were then denied by AppArmor
when trying to connect to the Wayland socket:

    apparmor="DENIED" operation="connect" profile="snap.firefox.firefox"
    name="/run/user/1000/wayland-0" ... comm="firefox"
    [firefox] Wayland Proxy Error: CheckWaylandDisplay(): Failed to
    connect to Wayland display ... Permission denied
    Error: we don't have any display, WAYLAND_DISPLAY='wayland-0' DISPLAY=':0'

The process then exited (status 1) with nothing shown to the user --
this is what "clicking Open does nothing" looks like from the outside.
Each click from App Center leaked another short-lived dead process
(`snap run firefox`); several accumulated as zombies before this was
diagnosed.

Why this happens here specifically: on a stock Ubuntu Desktop host,
`wayland`/`x11`/`desktop` are implicit slots provided by the system
itself, and snapd auto-connects them for any strictly-confined app by
policy. On this image, those same interfaces are instead provided as
slots by the `ubuntu-desktop-session` *snap* (not the system), which
means snapd's normal auto-connect policy does not apply -- every
consuming snap needs an explicit `snap connect`. `snap-store` got this
via a hand-written boot-time connection loop; nothing does this for
apps a user subsequently installs through App Center.

## What was fixed this session (workaround only, not the general fix)

- Live on the VM: `snap connect firefox:desktop ubuntu-desktop-session:desktop`,
  same for `:wayland` and `:x11`. Retested: Firefox launched a full real
  process tree (parent + content/tab/utility/GPU processes), no AppArmor
  wayland denials, and the GNOME session/GDM remained alive throughout.
- `ubuntu-core-desktop` image build: added `firefox:desktop`,
  `firefox:wayland`, `firefox:x11` to the same boot-time `snap connect`
  retry loop already used for `snap-store` (uncommitted -- see git diff).
  This only re-establishes the connection for Firefox specifically, and
  only if Firefox happens to already be installed at boot time; it does
  not generalize to any other app.

## Correct fix (not yet done)

This is app-specific plumbing standing in for a missing general
mechanism. Any other snap installed via App Center (not just Firefox)
will hit the exact same silent failure. The real fix should make
`wayland`/`x11`/`desktop` connect automatically for apps installed via
App Center/snapd on this image, without needing to hand-enumerate every
app snap-name in the image build. Options to investigate:
  - Have App Center itself request/perform the interface connections
    right after install (it already has a "snapd-control"-style
    privileged path per the App Center polkit work item -- extend that
    to cover connecting these three interfaces post-install).
  - Look at whether `ubuntu-desktop-session`'s slot declarations can be
    marked to auto-connect for classic/strict snaps generally (check
    snapd's base-declaration/interface policy for content-style slots
    provided by a snap instead of the system), rather than requiring
    per-plug-snap allowlisting.
  - Compare against how a real snap-store-published (non-dangerous)
    `ubuntu-desktop-session` handles this via gadget.yaml static
    connections -- gadget connections only apply by real snap-id (the
    caveat the project documentation flags), so a locally-built/dangerous
    `ubuntu-desktop-session` snap needs the same kind of workaround this
    project already uses elsewhere (oneshot `snap connect` unit) until
    the snap has a genuine store snap-id.

## Validation

1. Install a snap via App Center that was never previously connected
   (not just Firefox -- pick a second, unrelated app) and confirm it
   launches on first try, no manual `snap connect` required.
2. Confirm no AppArmor DENIED entries for that app's `wayland`/`x11`/
   `desktop` plugs in the journal.
3. Confirm no leftover zombie `snap run <app>` processes after repeated
   clicks on "Open" before the fix would have applied.

Do not mark this complete if fixing it requires hand-adding every
individual app snap name to the image build's connection loop --
that only works for this test image, not for general App Center use.

Update 2026-09-16: re-confirmed identical symptom/root cause (Firefox
installed via App Center, "Open" silently hangs, wayland/x11 plugs
unconnected) while testing the unrelated
`20260916-confine-gnome-session-user-units.md` fix. Manual
`snap connect firefox:wayland ubuntu-desktop-session:wayland` (+`:x11`)
again fixed it immediately. Confirms this is still open and is not
caused by, or fixed by, the gnome-session/gnome-shell confinement work.

## Update 2026-10-29: scope expanded to audio; status corrections

- Status correction: the boot-time `snap connect` retry loop in
  the image build described above is gone - connections are now
  baked into gadget.yaml at image build (build.sh
  gnome_gadget_connections/kde_gadget_connections; the firefox/snap-store
  display plugs are gadget connections now). The runtime-install gap
  itself is unchanged and still open.
- Why audio is in scope: this image has NO system audio slot at all.
  audio-playback/pulseaudio/pipewire are ImplicitOnClassic-only in
  snapd (interfaces/builtin/{audio_playback,pulseaudio,pipewire}.go)
  and core26-desktop strips the pipewire/wireplumber/pipewire-pulse
  daemons, so the only audio slots are the pipewire snap's
  (pipewire:pipewire, :audio-playback, :audio-record, :pulseaudio).
  The session's own audio plugs are gadget-connected to them; a
  runtime-installed app has no path to them at all.
- Policy nuance (do NOT assume audio is broken): unlike
  wayland/x11/desktop/pipewire/pulseaudio, audio-playback has no
  deny-auto-connection in its base declaration, and the auto-connect
  checker evaluates the installing app's snap-declaration plug rule
  first (an unasserted slot side counts as no declaration). Whether a
  store app's audio-playback auto-connects to the pipewire snap's slot
  at install time depends on that app's declaration - must be tested,
  not assumed.
- Investigation (end-to-end): on a VM with display working, install a
  never-before-connected audio-using snap via App Center, run
  `snap connections <app>`, actually play audio, then collect
  journalctl for pipewire/pulse/audio denials. Re-rate the audio
  priority from the result.
- Structural note: gadget connections only apply during seeding or
  remodeling (snapd overlord/ifacestate), so no build-time mechanism
  can cover runtime installs - the fix must come from the "Correct
  fix" options above, now extended to the audio interfaces.
- KDE note: the KDE image ships no pipewire snap and its gadget wires
  plasma-desktop-session:pipewire -> system:pipewire (and
  :pulseaudio -> system:pulseaudio), which are likely silent no-ops
  (no implicit system slots for these interfaces on UC). KDE audio
  needs its own reconciliation - see
  `20261029-migrate-gadget-connections-to-store-gadget.md`.
