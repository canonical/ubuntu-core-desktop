# The system-user assertion never applies: model name typo in system-user.json

Date: 2026-09-17

## Impact / Priority

The `--nouser` user-seeding mechanism silently never worked: snapd
ignored the system-user assertion on every boot because of the model
name mismatch, so no test user was ever created via that path (only the
cloud-init seed created one). Impact derived from the original note's
described symptoms. No priority level was stated in the original note.

## Context

Discovered while implementing/testing `--autologin`/`--nouser` flags
for the image build (`build.sh`). `26.img` is always built with
`--assertion auto-import.assert` unless the new `--nouser` flag is
passed (the `NOUSER=1` build), which is meant to seed a `your_username`
system-user account via snapd's system-user assertion mechanism on
first boot.

In practice, on every boot of `26.img` (checked via `journalctl`), snapd
logs:

    snapd[NNNN]: users.go:192: ignoring system-user assertion for
      "chris.bainbridge@canonical.com": "ubuntu-core-desktop-26-amd64-dangerous"
      not in models ["ubuntu-core-26-amd64-dangerous"]

Root cause: the `system-user.json` used to build `auto-import.assert`
(in the repo working tree - note the active copy has a trailing `~` and
there is no plain `system-user.json` in the working tree at all;
`old/system-user.json` has the same bug) has:

    "models": ["ubuntu-core-26-amd64-dangerous"]

but the actual model used to build `26.img` is
`ubuntu-core-desktop-26-amd64-dangerous` (see
`ubuntu-core-desktop-26-amd64-dangerous.model`/`.json` in the repo) -
missing the `-desktop` in the middle. Because of this mismatch, snapd
silently ignores the assertion on every single build, regardless of
`--nouser`. In current practice, `your_username` has only ever actually
been created via the independent cloud-init `seed.iso` mechanism (built
by `build-cloud-init.sh`, always attached when booting the test VM),
which is unrelated to `auto-import.assert`/`--nouser` and unaffected by
this bug.

This means `--nouser`'s own logic (conditionally dropping
`--assertion auto-import.assert`) is implemented correctly and has been
verified at the raw-disk level (confirmed via `dd`/`debugfs`/`mtools`
inspection of a freshly-built image's partitions: no system-user
assertion is embedded, no user entry exists pre-boot) - this bug is in
the assertion content itself, predates the flags work, and is
orthogonal to it.

## Goal

Fix the model name in `system-user.json` (or whichever file is the
canonical source - check if `system-user.json~`/`old/system-user.json`
should be consolidated into a single tracked `system-user.json`) so it
reads `"models": ["ubuntu-core-desktop-26-amd64-dangerous"]`, matching
the real model name, then regenerate `auto-import.assert`
(`snap sign system-user.json --chain > auto-import.assert`) and verify
on a fresh (non-`--nouser`) image build/boot (without the cloud-init
`seed.iso` attached, to isolate this mechanism) that `your_username`
now actually gets created via the assertion, with no more "ignoring
system-user assertion ... not in models" log line.

## Suggested investigation approach

- Check git history / other model files (e.g.
  `ubuntu-core-26-amd64-dangerous.model` under `old/`) to understand
  whether the project was recently renamed from `ubuntu-core-26-*` to
  `ubuntu-core-desktop-26-*` and this is simply a leftover from that
  rename that never got updated in `system-user.json`.
- Decide whether the two stray usernames across the two file variants
  (`system-user.json~` uses `"username": "admin"`,
  `old/system-user.json` uses `"username": "your_username"`) also need
  reconciling - the cloud-init seed and the rest of the tooling assume
  the test user's name, so whichever file becomes canonical should most
  likely use `"username": "your_username"` to match.
- Also double check why the `auto-import.assert` build rule (which
  depends on `system-user.json`, no tilde) hasn't errored on
  missing-prerequisite in recent builds - likely because a pre-built
  `auto-import.assert` already exists in the working tree and nothing
  has forced a rebuild; worth understanding this properly as part of
  the fix so the build rule stays correct/functional going forward.

## Resolution

Decided not to fix the model-name typo: since `your_username` has only
ever actually been created via the cloud-init `seed.iso` (built by
`build-cloud-init.sh`, always attached when booting the test VM), the
system-user assertion mechanism was pure dead weight, and the cloud-init
seed already covers user seeding with fewer moving parts (no
signing/model coupling, password auth in addition to SSH keys, pins a
persistent SSH host key). Dropped the mechanism entirely instead of
repairing it:

- Removed the `auto-import.assert` Makefile rule, all
  `--assertion auto-import.assert` usages (`core26.img`, `24.img`,
  `26.img`), and the tracked `auto-import.assert` file itself.
- Deleted the stray untracked/ignored `system-user.json~` and
  `old/system-user.json` sources.
- `--nouser`/`NOUSER=1` is kept (still needed to force
  `ubuntu-desktop-init`'s first-boot wizard) but repurposed: `26.img`
  now drops a `26.img.nouser` marker file instead of omitting an
  assertion, and the test-VM boot tooling checks for that marker to
  decide whether to attach `seed.iso`, rather than relying on the
  never-working assertion path.

Committed as ae6fb03 in ubuntu-core-desktop.
