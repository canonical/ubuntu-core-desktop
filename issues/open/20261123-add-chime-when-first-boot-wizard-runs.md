# Add a chime when the first-boot wizard runs

## Impact / Priority

A blind user gets no audible cue that the first-boot installer has
started, so they may not know when to turn on their screen reader and
begin the install; the regular (non-core) Ubuntu desktop installer
plays such a chime when the installer runs.

Impact derived from the original note's symptoms.

Following
`20261109-bring-accessibility-up-to-regular-ubuntu-desktop-levels.md`.

Apparently in the regular non-core Ubuntu desktop installer a chime
plays when the installer runs. This chime alerts a blind user to the
fact that the installer is running and they can now turn on their
screen reader and start doing the install. This appears to be missing
in our accessibility work. Investigate this and add a chime.

If you need a reference for the original non-core installer, you can
use the stock Ubuntu 26.04 desktop ISO (ubuntu-26.04-desktop-amd64.iso).
