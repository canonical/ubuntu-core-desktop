# Core Desktop Models

The model definition is a signed assertion that describes the snaps
that make up an Ubuntu Core Desktop system. The format is described here:

https://ubuntu.com/core/docs/reference/assertions/model

We currently have two model definitions:

* `ubuntu-core-desktop-26-amd64-dangerous` (the dev model)
* `ubuntu-core-desktop-26-amd64` (the release model)

Both are `grade: dangerous`, signed with the locally registered `test`
key: the release model resolves what it can from the Snap Store
(each snap's `default-channel`), but the base (`core26-desktop`) is
deliberately never store-published (the plan is to drop it for a
plain `core26` base), and `grade: signed` requires every model snap to
be store-published. The dev model is identical apart from the name;
local snaps passed to `build.sh` (`--snap`, `--base-snap`, ...) always
override the model's channel resolution, which is how the dev
fast-path keeps working while snaps are migrated to the store one at
a time (see notes/todo/20261103-publish-core-desktop-snaps-to-the-store.txt).

The `grade` property allows us to build with unpublished snaps, which
is primarily intended to allow testing of modified snaps prior to
publishing them to the store.

## Modifying the models

To modify the list of snaps in the model, edit the model's json
file. In addition, remember to make the following changes:

1. update the `timestamp` property to the current time. The command
   `date -u --iso=seconds` will output it in the required format.
2. increment the `revision` property. The default value for `revision`
   is `0`, so if the property doesn't currently exist set it to `1`.

Next, it is necessary to get the model signed. The Canonical brand
account key is controlled by IS, so this is done by filing an RT
request with the new json files attached.

When the new models are signed, they can be committed back to this
repository.

In addition to this, Foundations has asked us to also add a copy of
the model to the
[`snapcore/models`](https://github.com/snapcore/models) repository.
