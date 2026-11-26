# Verify the App Center only lists snaps (no Debian packages)

## Impact / Priority

On Ubuntu Core Desktop, if the App Center surfaces Debian
packages, users will accidentally try to install them — and the
install will obviously fail, a confusing dead end. Verify that
the App Center only actually lists snaps.

Impact derived from the original note's described symptoms.

## Task

On Ubuntu Core desktop, the App Center should only be listing
snaps. Verify that this is actually the case. We don't want
people to accidentally try to install Debian packages, which
will obviously fail.
