# Core Desktop Models

The model definition is a signed assertion that describes the snaps
that make up an Ubuntu Core Desktop system. The format is described here:

https://ubuntu.com/core/docs/reference/assertions/model

There are two model definitions, one per Platform. Each Platform's files live together under `platforms/<platform>/`:

| Platform | Model | JSON definition | Pre-signed assertion |
| --- | --- | --- | --- |
| GNOME | `ubuntu-core-desktop-26-amd64-dangerous` | `platforms/gnome/model.json` | `platforms/gnome/model.signed` |
| KDE | `ubuntu-core-desktop-kde-26-amd64-dangerous` | `platforms/kde/model.json` | `platforms/kde/model.signed` |

The dangerous model's `grade` property allows us to build with
unpublished snaps, which is primarily intended to allow testing of
modified snaps prior to publishing them to the store.

## Modifying the models

To modify the snaps for a Platform, edit its `platforms/<platform>/model.json`. In addition, remember to make the following changes:

1. update the `timestamp` property to the current time. The command
   `date -u --iso=seconds` will output it in the required format.
2. increment the `revision` property. The default value for `revision`
   is `0`, so if the property doesn't currently exist set it to `1`.

The repository's `build.sh` defaults to the Platform's JSON model and signs it with `snap sign`; select the key with `SNAP_SIGN_KEY` (default: `test`). For builds using the checked-in pre-signed assertion, pass `--model platforms/<platform>/model.signed`. The model account-key assertion is still supplied separately with `--model-account-key` (for example, `ci/account-key.assert` for the checked-in assertion).

The Canonical brand account key is controlled by IS, so publishing an updated official model requires filing an RT request with the new JSON files attached. Commit the updated signed assertions alongside the model definitions when they are available.

Foundations has also asked us to add copies of the models to the
[`snapcore/models`](https://github.com/snapcore/models) repository.
