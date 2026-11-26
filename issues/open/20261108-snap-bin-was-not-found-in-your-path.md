# snap install warns: /snap/bin was not found in your $PATH

## Impact / Priority

Installing a snap emits the warning "/snap/bin was not found in your
$PATH" — on this image, installed snaps would not be launchable from
the shell via /snap/bin, which is how users normally run installed
snaps (e.g. `snap install chromium`). Impact derived from the original
note's described symptoms.

## Reproduction

1. `snap install chromium`

   gives

       warnings: /snap/bin was not found in your $PATH
