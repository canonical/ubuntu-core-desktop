# Investigate a single snaps monorepo (gentoo model), not one repo per snap

## Impact / Priority

The task to update all desktop snaps to core26 exposed that every
snap lives in its own repository: there is no single authoritative
list of all the different snaps and repositories, and the model
does not scale (what happens with 200 or 1000 snaps — a thousand
repositories?). Since most of these snaps are just repackaging of
upstream software plus a snapcraft.yaml, a gentoo/nixpkgs-style
monorepo (one directory per package, build instructions and
hashes inside) is proposed as the better model.

Impact derived from the original note's described symptoms.

## Context

The task to update all desktop snaps to core26 (see
`20261104-update-all-desktop-snaps-to-core26.md`) exposed an issue
with the current setup.

Each step was in a different repository. There's no single
authoritative list of all the different snaps and repositories. It
also highlights the issue of scaling. What happens when there's
200 snaps or a thousand snaps? Do we need a thousand different
repositories? And in many cases, these snaps are just repackaging
upstream software, but adding a snapcraft.yaml file. The
traditional way to do this in a Debian package was to have a
debian directory in the root of a package, and Put build commands
and patches in there.

But distributions like gentoo do it differently. They have a
single repo with multiple packages, where each package has a
unique directory, And in that directory there are the
instructions to fetch the latest source, And build it and publish
it. I suspect that this model would work better for our snaps than
the model we have now. Scaling it to a thousand packages would
just require having a thousand directories (Although at that point
we might want to have some way of separating those out)

I like the gentoo model. It makes it easy for everyone to
contribute. Updates are atomic across multiple packages. Everyone
knows where the build scripts are and how to use them. There's no
need to search for dozens of different packages and repositories
in GitHub or launchpad. The evidence for this is the Gentoo
repository itself: https://github.com/gentoo/gentoo has 1.1
million commits by 1669 individual authors.

So I think we should have a single repository. Each build package
should have a subdirectory that contains all of the build
instructions required to build it and a separate manifest file for
any files that are downloaded along with their hashes.

The structure of the directory should be that there is a prefix
sharding scheme e.g.

    snaps/
    ├── gn/
    │   ├── gnome-calculator/
    │   └── gnome-contacts/
    ├── gu/
    │   └── gufw/
    └── py/
        ├── python-certifi/
        └── python-urllib3/

Let's use the two-letter prefix. It seems to work well for nixOS.

## Investigation task

Take all of the snaps the desktop team currently maintain (i.e.
those we updated for core26) - Except the ones that are not
published by canonical (like firefox). make a monorepo in
~/git/snaps. Use the subdir layout described above.

write a top-level build script that implements a command like:

    ./build gnucash

that builds a snap based on content in subdir gn/gnucash

## Architecture Design: Snap Package Monorepo

### 1. Repository Layout: Two-Character Lexicographical Sharding

To easily scale to thousands of packages without hitting UI limits
or requiring complex categorization debates, the repository uses a
deterministic two-character sharding structure based on the
package name (the Nixpkgs model).

    snaps/
    ├── gn/
    │   ├── gnucash/
    │   └── gnome-calculator/
    ├── gu/
    │   └── gufw/
    └── vl/
        └── vlc/

### 2. Package-Level Directory Structure

Each package utilizes standard Snapcraft conventions while
maintaining a clean root directory. The root contains a
`metadata.yaml` for CI orchestration, and a `snap/` subdirectory
for Snapcraft-specific files and local overrides.

    gn/gnucash/
    ├── README.md               # Package-specific maintainer notes (optional)
    ├── metadata.yaml           # CI config, tracks, upstream URLs, and hashes
    └── snap/                   # Idiomatic Snapcraft directory
        ├── snapcraft.yaml      # The build definition (if maintained downstream)
        ├── gui/
        │   └── gnucash.desktop # App launchers and icons
        └── local/
            └── core26.patch    # Build scripts, patches, and overrides

### 3. CI Orchestration & Tracks (`metadata.yaml`)

Because a monorepo cannot use Git branches to manage Snap Store
tracks (like `latest` vs `3.0`), track definitions and CI
infrastructure routing are centralized in `metadata.yaml`.

    # vl/vlc/metadata.yaml
    infrastructure:
      maintainer: "@yourusername"
      runner-size: "large-16-core"
      architectures: ["amd64", "arm64"]

    tracks:
      latest:
        source-url: "https://github.com/videolan/vlc.git"
        source-commit: "a1b2c3d4e5f6..."
        store-channels: ["latest/edge", "latest/beta"]
        assets:
          - url: "https://example.com/extra-plugin.tar.gz"
            sha512: "b66fecb47168ae269a0ef03c22d0ebd048b0..."

      3.0:
        source-url: "https://github.com/videolan/vlc.git"
        source-commit: "v3.0.20"
        store-channels: ["3.0/stable"]
        local-overrides: "snap/local/legacy-fixes/"

### 4. The Two Build Workflows

The CI pipeline uses path-filtering (`git diff`) to detect modified
`snaps/*/*/` directories, generating a dynamic build matrix. For
each targeted package, it executes one of two workflows based on
the directory contents:

#### Workflow A: Downstream-Maintained (Native Snapcraft)

Condition: A `snap/snapcraft.yaml` exists in our monorepo
directory.

Execution:
* The CI pipeline reads `metadata.yaml` to provision the correct
  runner size and architecture.
* CI executes `snapcraft` directly inside our monorepo directory
  (e.g., `gn/gnucash/`).
* The local `snapcraft.yaml` natively handles fetching the
  upstream source code, applying patches from `snap/local/`, and
  building the final snap.
* CI uploads the result to the Snap Store channels defined in
  `metadata.yaml`.

#### Workflow B: Upstream-Maintained (CI Staging Workspace)

Condition: No `snapcraft.yaml` exists in our monorepo directory.
Upstream maintains it, and we are only providing overrides (e.g.,
`core26` migration patches).

Execution:
* The CI pipeline reads `metadata.yaml` to provision the correct
  runner, find the upstream Git URL, target commit hash, and
  verify any asset SHA512 hashes.
* CI clones the upstream repository into an isolated, temporary
  build workspace (e.g., `/tmp/build-vlc/`).
* CI copies our monorepo overrides *over* the cloned repository
  (`cp -a vl/vlc/snap/ /tmp/build-vlc/`), safely applying our
  custom patches or wrapper scripts without file collisions.
* CI executes `snapcraft` inside the temporary
  `/tmp/build-vlc/` workspace.
* CI uploads the result to the Snap Store channels defined in
  `metadata.yaml`.
