# Verify the KDE screen lock requires a password

## Impact / Priority

Priority: HIGH. Real end-user impact: with the bug, ANY input (mouse move)
unlocks the session with no password prompt -- a full auth bypass for a
machine left locked. This is the primary physical-security property of a
lock screen. Fix is committed (plasma-core-desktop b3916d6) but NOT yet
verified end-to-end on a rebuilt image; verification is the remaining work.

## Status at write-up (2026-10-12 ~22:25)

- Fix committed: plasma-core-desktop b3916d6 removes hook
  260-workaround-lack-of-pam-access.sh which shipped an IMMUTABLE
  ([$i]) system default `kscreenlockerrc [Daemon] RequirePassword=false`
  -> "require password when unlocking" OFF for every user. That setting
  is the entire unlock-on-any-input bug. The hook was a previous
  session's band-aid for the greeter PAM breakage, which is now fixed
  for real (see `20261013-fix-kde-screen-unlock.md` for the PAM chain).
- Rebuild chain (plasma snap -> pc.img) launched 22:22:52; expect
  roughly 20-40 min total.
- Known-good state before this fix: lock engages, greeter STARTS and
  stays alive, PAM worker initializes (no "Worker not ready" spam once
  /etc/pam.d/kde exists), hover input is delivered and rendered. Only
  the password requirement was missing.

## Verification procedure (after the build lands)

1. Boot the new pc.img, wait for SSH.
2. lock via `loginctl lock-session <seat-session>` or the desktop menu;
   confirm LockedHint=yes and greeter alive
   (`ps -eo comm= | grep -c ^kscreenlocker_g$`).
3. THE TEST: move the mouse -> the LOCK SCREEN MUST SHOW A PASSWORD
   PROMPT, not the desktop. Type your_username's password -> unlock.
4. If the prompt appears, the whole lock chain is done: also spot-check
   logout/login still works.

## If it still unlocks without a prompt

- Check no other etc/xdg/kscreenlockerrc exists in the content snaps
  (`unsquashfs -l plasma-core-desktop.snap | grep kscreenlockerrc`) --
  260 was the only writer, but verify.
- kscreenlocker debug: drop a user unit override for the snap
  plasma-kwin-wayland.service with QT_LOGGING_RULES=*.debug=true and read
  the greeter/kwin journal at kill time (that is how the grace/unlock
  path was traced this session).

## Resolution (2026-10-13)

DONE - verified end-to-end on a fresh pc.img (the image build, autologin
reproducer): three consecutive Super+L lock -> PASSWORD PROMPT ->
password -> unlock cycles all succeeded, i.e. the `[$i]
RequirePassword=false` system default is gone (plasma-core-desktop
b3916d6 removed hook 260-workaround-lack-of-pam-access.sh) and the
mouse-move unlock bypass no longer exists. Full chain evidence
(PAM/chkpwd helper fixes behind the prompt) in
`20261013-fix-kde-screen-unlock.md`.
