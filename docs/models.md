# Core Desktop Models

The model definition is a signed assertion that describes the snaps
that make up an Ubuntu Core Desktop system. The format is described here:

https://ubuntu.com/core/docs/reference/assertions/model

We currently have two model definitions:

* `ubuntu-core-desktop-22-amd64`
* `ubuntu-core-desktop-22-amd64-dangerous`

They are identical except for the `grade` property: the regular model
requires all snaps in the seed be signed and published by the store,
while the dangerous model allows us to build with unpublished snaps.

The dangerous model is primarily intended to allow testing of modified
snaps prior to publishing them to the store.

## Modifying the models

To modify the list of snaps in the model, edit the model's json
file. In addition, remember to make the following changes:

1. update the `timestamp` property to the current time. The command
   `date -u --iso=seconds` will output it in the required format.
2. increment the `revision` property. The default value for `revision`
   is `0`, so if the property doesn't currently exist set it to `1`.

Then make the equivalent changes to the dangerous model.

Next, it is necessary to get the model signed. The Canonical brand
account key is controlled by IS, so this is done by filing an RT
request with the new json files attached.

When the new models are signed, they can be committed back to this
repository.

In addition to this, Foundations has asked us to also add a copy of
the model to the
[`snapcore/models`](https://github.com/snapcore/models) repository.
