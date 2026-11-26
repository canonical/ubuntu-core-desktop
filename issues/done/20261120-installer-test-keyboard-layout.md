# Wizard keyboard-layout selection has no effect (always English US)

## Impact / Priority

The keyboard layout chosen in the first-boot wizard was silently
ignored (the session stayed on English US), so keys produce different
characters than the selected layout maps them to. For a password field
with no per-character feedback, a password can end up being something
other than what the user intended, whenever it includes characters
mapped differently on their layout. Impact lifted from the original
note's described symptoms.

After building a no-user image and booting the VM, the first run
installer runs. I select a language English United Kingdom and click
Next. It shows accessibility in Ubuntu page I click Next. It now shows
select your keyboard layout. I choose "English (UK)" and click/focus
in the box where it says "Type here to test your keyboard". I hit
shift-f3 to type £ but instead it types #. If I choose layout "English
(US)" and do the same test it prints #. So it looks like the keyword
isn't being changed, it's just defaulting to English US. I suspect
this would cause anyone who doesn't get feedback in their password,
the password will be set to something that they're not expecting if
they include Characters that are mapped differently on their keyboard
layout that they are expecting.

SSH into the VM, introspect it and figure out what's happening and fix
it.

## Resolution (2026-11-20)

Root cause: the confined session's gnome-shell was using GLib's
per-snap keyfile GSettings backend, not the real dconf database.
GLib 2.88 picks the keyfile backend (priority 110) when
`snapctl is-connected desktop` succeeds but
`snapctl is-connected gsettings` does not (gportalsupport.c). The
session snap has a *slot* named desktop (connected to snap-store), and
Ubuntu Core has no :gsettings slot, so every confined session app
silently used its private keyfile store. provd writes the wizard's
layout selection to dconf (through the session's dconf service);
gnome-shell never saw it, fell back to the built-in "us" layout and
Shift+3 stayed #. Two secondary blockers: libgio's compiled-in
/usr/lib/<triplet>/gio/modules does not exist in the session snap's
base (stock core26) so the dconf backend module was not even
loadable, and DCONF_PROFILE=gnome-initial-setup's stock profile only
exists in the core26-desktop system base (missing in the confined
session), which makes dconf fall back to the null configuration.

Fix (all confined-session side; the owner chose one live store for the
whole session rather than dconf only for gnome-shell):
- ubuntu-desktop-session (desktop/26) 4839f0a: add a plug literally
  named "gsettings" (interface dbus, name ca.desrt.dconf) for
  gnome-shell; point GIO_EXTRA_MODULES at the gnome-desktop-runtime
  content's gio modules; ship
  usr/share/dconf/profile/gnome-initial-setup.
- ubuntu-desktop-session (desktop/26) c95e724: set
  GSETTINGS_BACKEND=dconf in the snap environment and add the
  gsettings plug to every GSettings client (all 63 apps that plug
  systemd-user-control plus 7 others). A well-known-name send to
  ca.desrt.dconf needs the plug's peer rule; the generic same-snap
  rule does not cover it (the wizard chord's keybinding seeding hit
  exactly that AVC).
- core-base-desktop (desktop/26) 521a8e9: the session wrapper stops
  exporting GSETTINGS_BACKEND=keyfile (it would override the snap
  environment); the a11y handover/mirror scripts are migrated to
  dconf (dconf-first reads, the greeter write through the greeter
  session's own dconf service, apply dconf-first with the keyfile as
  a fallback). This supersedes the earlier keyfile mechanism.
- ubuntu-core-desktop (desktop/26) 65dac0e: gadget-connect
  ubuntu-desktop-session:gsettings to its own dbus-dconf slot (the
  plug name is the literal-name probe GLib looks for; the dbus
  interface supplies the AppArmor grant).

Verified three ways:
1. Live on the old image (bind-mounted run.sh + profile grant,
   gdm restart): a gsettings write of sources=[('xkb','gb')] flipped
   a GDK wl_keyboard probe from numbersign (0x23) to sterling (0xa3)
   and the shell's keyboard menu changed English (US) -> English (UK).
2. Rebuilt session snap + a fresh no-user image (separate build dir):
   gadget connection shows in `snap connections`; the confined shell
   reports `Found default implementation dconf (DConfSettingsBackend)`;
   in the wizard, selecting English (UK) and typing Shift+3 in the
   test box shows £. provd logs SetInputSource(gb) and the user's
   dconf DB contains [('xkb','gb')].
3. FINAL image (c95e724 content) end-to-end, which is what closes the
   report: after the wizard creates the user, the USER's session types
   £ for Shift+3 too (Super, Shift+3 in the shell search entry), and
   the whole a11y chain still works on dconf (chord, handover
   live-read override, automatic greeter speech both directions, zero
   dconf denials). The full a11y-chain re-verification is recorded in
   the a11y spike work records.
The rebuilt image was removed after verification (scratch policy).
