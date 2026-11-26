# Investigate replacing our xdg-fuse-broker with Defused

## Impact / Priority

No direct end-user impact is described in the original note; this is
an architecture/maintenance decision: this project's xdg-fuse-broker
is bespoke, and Defused (https://github.com/Skyb0rg007/defused) is a
candidate standardized upstream replacement that OpenSUSE is
apparently already looking into.

Impact derived from the original note's symptoms.

https://github.com/Skyb0rg007/defused

- Apparently OpenSUSE is already looking into using Defused
- Adopting a standardized upstream solution is better than building our own

## Task

- Replace our xdg-fuse-broker with defused
- Does it work?
