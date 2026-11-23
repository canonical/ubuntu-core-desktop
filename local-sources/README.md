# Local source overrides

Everything in this directory is gitignored. Clone a component's source
here to build that snap from source instead of using the prebuilt snap
cached in `../snaps/`:

    cd local-sources
    git clone https://github.com/canonical/accountsservice-snap

Then run `./build.sh` as usual. `./build-snaps.sh` (called by `build.sh`)
notices the clone, builds it with `./build-snap.sh accountsservice-snap`,
and copies the result into `../snaps/`. Components without a clone here
keep using their cached snap, so you only pay for what you change.

A component is only rebuilt when its tree changes (HEAD, the diff against
HEAD, or untracked files). To force a rebuild anyway, delete the stamp in
`../snaps/.build-state/<component>` or run
`./build-snap.sh <component> --force`.

`./build-snap.sh --list` lists the components.
