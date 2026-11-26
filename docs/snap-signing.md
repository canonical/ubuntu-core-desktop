# Snap model signing for image builds

How model assertions are signed during image builds, and the signing
gotchas that have bitten before.

## Signing in build.sh

`build.sh` signs the model assertion from its `*.json` source via
`snap sign`, defaulting the key to the registered `test` key so image
builds work out of the box:

    snap sign -k "${SNAP_SIGN_KEY:-test}" --update-timestamp "${model_json}"

Override the key per invocation with the `SNAP_SIGN_KEY` environment
variable.

## Signing gotchas

- For unattended/CI signing, `snap sign` needs a GPG keyring usable
  non-interactively (no passphrase prompt). A one-off interactive
  prompt to *create* the keyring is fine even for a non-logged-in
  user, but the resulting key should have a blank/no password so
  subsequent `snap sign` calls never prompt.
- If a booted VM reports a signing-key ID or model value that looks
  wrong but the current source JSON/model files are already correct,
  the image simply hasn't been rebuilt with the corrected model yet —
  rebuild rather than re-editing source files that are already right.
  Stale values can also linger in backup/editor files (`*~`,
  `*.bak`); those are harmless and don't need fixing.
