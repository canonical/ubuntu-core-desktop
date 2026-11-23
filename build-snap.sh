#!/usr/bin/env bash
#
# build-snap.sh - build one component snap of the Ubuntu Core Desktop image
# from its source tree.
#
#   ./build-snap.sh <component> [--force] [--snaps-dir DIR] [--source-dir DIR]
#   ./build-snap.sh --list          # component names, one per line
#   ./build-snap.sh --table         # the raw component table
#
# A component's source tree is local-sources/<component> by default (clone
# it there to work on it); --source-dir points somewhere else.
#
# The table in component_table() describes what each component is and where
# its prebuilt snap comes from; the recipe for building it lives in its
# build_<component>() function. A component with no function of its own is
# a plain `snapcraft pack` - that is the rule, and every exception is an
# explicitly named function below, so "why is this one different?" has
# exactly one place to look.
#
# The packed snap is copied to <snaps-dir>/<local-name>, which is the name
# build.sh and the CI image workflows expect. A stamp under
# <snaps-dir>/.build-state/ records the git state that produced it, so a
# rerun with an unchanged tree does nothing at all; --force rebuilds
# regardless. Deleting the stamp (or the cached snap) forces a rebuild too.
#
# Every build ends with `snapcraft clean`, whether it succeeded or failed:
# a half-built LXD instance left behind silently poisons the next build,
# and these builds are not cheap to debug.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# name|repo|release tag|release asset|local snap name|desktops
#
# Every component publishes the desktop-variant rolling release
# desktop-26-latest from its desktop/26 branch (the base included - it used
# desktop-26-thin-latest until 2026-11-23, a name left over from the
# 2026-11-09 branch rename). "desktops" is gnome, kde or both; the base,
# gadget, snapd and the first-boot wizard are shared.
component_table() {
    cat <<'EOF'
core-base-desktop|canonical/core-base-desktop|desktop-26-latest|core26-desktop.snap|core26-desktop-variant.snap|both
pc-amd64-gadget-desktop|canonical/pc-amd64-gadget-desktop|desktop-26-latest|pc-desktop.snap|pc-desktop.snap|both
ubuntu-core-desktop-snapd|canonical/ubuntu-core-desktop-snapd|desktop-26-latest|snapd.snap|snapd.snap|both
accountsservice-snap|canonical/accountsservice-snap|desktop-26-latest|accountsservice.snap|accountsservice.snap|gnome
provd-snap|canonical/provd-snap|desktop-26-latest|provd.snap|provd.snap|gnome
fprintd-snap|canonical/fprintd-snap|desktop-26-latest|fprintd.snap|fprintd.snap|gnome
boltd-snap|canonical/boltd-snap|desktop-26-latest|bolt.snap|bolt.snap|gnome
geoclue-snap|canonical/geoclue-snap|desktop-26-latest|geoclue.snap|geoclue.snap|gnome
ubuntu-desktop-a11y|canonical/ubuntu-desktop-a11y|desktop-26-latest|ubuntu-desktop-a11y.snap|ubuntu-desktop-a11y.snap|gnome
ubuntu-desktop-session-snap|canonical/ubuntu-desktop-session-snap|desktop-26-latest|ubuntu-desktop-session.snap|ubuntu-desktop-session.snap|gnome
gnome-desktop-runtime|canonical/gnome-desktop-runtime|desktop-26-latest|gnome-desktop-runtime.snap|gnome-desktop-runtime.snap|gnome
pipewire-snap|canonical/pipewire-snap|desktop-26-latest|pipewire.snap|pipewire.snap|gnome
ubuntu-desktop-provision|chris-bainbridge/ubuntu-desktop-provision|desktop-26-latest|ubuntu-desktop-init.snap|ubuntu-desktop-init.snap|both
kf6-core26|chris-bainbridge/kf6-core26|desktop-26-latest|kf6-core26.snap|kf6-core26.snap|kde
plasma-core-desktop|chris-bainbridge/plasma-core-desktop|desktop-26-latest|plasma-core-desktop.snap|plasma-core-desktop.snap|kde
plasma-desktop-session|chris-bainbridge/plasma-desktop-session|desktop-26-latest|plasma-desktop-session.snap|plasma-desktop-session.snap|kde
EOF
}

usage() {
    sed -n '3,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

meta_field() {
    # meta_field <component> <field number, 1-based>
    component_table | awk -F'|' -v n="$1" -v f="$2" '$1 == n { print $f; found = 1 } END { exit found ? 0 : 1 }'
}

# --- Per-component build recipes --------------------------------------
#
# Each runs with the working directory already set to the source tree, and
# SNAP_PROJECT_DIR set to the directory `snapcraft clean` must run in (a
# recipe in a subdirectory overrides it). Anything not listed here is a
# plain `snapcraft pack`.

# A plain `snapcraft pack` here produces a variant-less base with no
# desktop payload: it boots to a system with no display manager.
build_core_base_desktop() {
    ./tools/build-variant.sh desktop
}

# These declare `base: core26-desktop`, which snapcraft's schema rejects;
# build-github.sh packs against a core26 placeholder and patches the real
# base back into the packed snap.
build_accountsservice_snap() { ./build-github.sh; }
build_provd_snap()           { ./build-github.sh; }
build_plasma_core_desktop()  { ./build-github.sh; }
build_plasma_desktop_session() { ./build-github.sh; }

# KDE runtime built from prebuilt KDE Neon apt packages.
build_kf6_core26() {
    ./build.sh
}

# The recipe lives one level down, so the build - and the clean - happen
# in snap/.
build_ubuntu_desktop_a11y() {
    SNAP_PROJECT_DIR="${PWD}/snap"
    cd snap
    snapcraft pack
}

# --- State tracking ---------------------------------------------------

# A hash of everything that should force a rebuild: the build script
# itself (a fix to a recipe must not be masked by a cached snap), HEAD,
# the diff against HEAD, and the contents of untracked files.
snapshot() {
    local dir=$1
    if ! git -C "${dir}" rev-parse HEAD >/dev/null 2>&1; then
        # Not a git checkout: no reliable state, so always rebuild.
        printf 'nogit-%s\n' "$(date +%s%N)"
        return 0
    fi
    {
        printf 'script %s\n' "$(sha256sum "${BASH_SOURCE[0]}" | cut -d' ' -f1)"
        git -C "${dir}" rev-parse HEAD
        git -C "${dir}" diff HEAD
        git -C "${dir}" ls-files -o --exclude-standard -z |
            while IFS= read -r -d '' f; do
                printf '%s ' "${f}"
                sha256sum < "${dir}/${f}" 2>/dev/null || printf 'unreadable\n'
            done
    } | sha256sum | cut -d' ' -f1
}

# --- Cleanup ----------------------------------------------------------

# Four components declare `base: core26-desktop`, a base name snapcraft's
# schema rejects - which is exactly why build-github.sh packs them against
# a core26 placeholder. `snapcraft clean` parses the same recipe, so it
# fails the same way unless the placeholder is in place for it too.
snapcraft_clean() {
    local dir=$1
    local yaml="" backup="" rc=0

    if ( cd "${dir}" && snapcraft clean ); then
        return 0
    fi

    for candidate in "${dir}/snapcraft.yaml" "${dir}/snap/snapcraft.yaml"; do
        if [[ -f ${candidate} ]]; then
            yaml=${candidate}
            break
        fi
    done
    backup="${yaml}.build-snap-orig"
    if [[ -z ${yaml} ]] || ! grep -q '^base: core26-desktop$' "${yaml}"; then
        return 1
    fi

    echo "==> snapcraft clean: retrying with the core26 base placeholder"
    cp -f "${yaml}" "${backup}"
    sed -i 's/^base: core26-desktop$/base: core26/' "${yaml}"
    ( cd "${dir}" && snapcraft clean ) || rc=$?
    mv -f "${backup}" "${yaml}"
    return "${rc}"
}

cleanup() {
    local rc=$?
    trap - EXIT
    if [[ -n ${SNAP_BUILD_STARTED:-} && -n ${SNAP_PROJECT_DIR:-} ]]; then
        echo "==> snapcraft clean (${SNAP_PROJECT_DIR#"${here}/"})"
        snapcraft_clean "${SNAP_PROJECT_DIR}" ||
            echo "warning: snapcraft clean failed; the LXD build instance may still exist" >&2
    fi
    exit "${rc}"
}
trap cleanup EXIT

# --- Main -------------------------------------------------------------

component=""
force=0
snaps_dir="snaps"
source_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list) component_table | cut -d'|' -f1; exit 0 ;;
        --table) component_table; exit 0 ;;
        --force) force=1; shift ;;
        --snaps-dir) snaps_dir="$2"; shift 2 ;;
        --source-dir) source_dir="$2"; shift 2 ;;
        -*) echo "Unknown flag: $1" >&2; exit 1 ;;
        *)
            if [[ -n ${component} ]]; then
                echo "Only one component can be built per invocation." >&2
                exit 1
            fi
            component="$1"; shift
            ;;
    esac
done

if [[ -z ${component} ]]; then
    echo "Missing component. Try './build-snap.sh --list'." >&2
    exit 1
fi

local_name="$(meta_field "${component}" 5)" || {
    echo "Unknown component '${component}'. Try './build-snap.sh --list'." >&2
    exit 1
}

[[ ${snaps_dir} = /* ]] || snaps_dir="${here}/${snaps_dir}"
[[ -n ${source_dir} ]] || source_dir="local-sources/${component}"
[[ ${source_dir} = /* ]] || source_dir="${here}/${source_dir}"

if [[ ! -d ${source_dir} ]]; then
    echo "No source tree for '${component}' at ${source_dir}" >&2
    echo "Clone it there first, e.g.:" >&2
    echo "  git clone https://github.com/$(meta_field "${component}" 2) ${source_dir#"${here}/"}" >&2
    exit 1
fi

mkdir -p "${snaps_dir}/.build-state"
stamp="${snaps_dir}/.build-state/${component}"
target="${snaps_dir}/${local_name}"

current="$(snapshot "${source_dir}")"
if [[ ${force} == 0 && -f ${target} && -f ${stamp} ]] &&
   [[ "$(cat "${stamp}")" == "${current}" ]]; then
    echo "==> ${component}: unchanged, using ${snaps_dir#"${here}/"}/${local_name}"
    exit 0
fi

echo "==> ${component}: building from ${source_dir#"${here}/"}"

# Marker for "which .snap files did this build produce": anything older
# than this is a leftover from an earlier run.
marker="${snaps_dir}/.build-state/.marker-${component}"
: > "${marker}"
sleep 1   # make sure a same-second write is still newer than the marker

SNAP_PROJECT_DIR="${source_dir}"
SNAP_BUILD_STARTED=1

recipe="build_${component//-/_}"
cd "${source_dir}"
if declare -F "${recipe}" >/dev/null; then
    "${recipe}"
else
    snapcraft pack
fi

# Pick the snap this build produced (recipes may emit more than one, and
# stale ones may still be lying around).
built="$(find "${SNAP_PROJECT_DIR}" -maxdepth 1 -name '*.snap' -newer "${marker}" \
         -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)"
if [[ -z ${built} ]]; then
    echo "error: ${component} built without producing a .snap in ${SNAP_PROJECT_DIR}" >&2
    exit 1
fi

cp -f "${built}" "${target}"
printf '%s\n' "${current}" > "${stamp}"
rm -f "${marker}"

echo "==> ${component}: ${snaps_dir#"${here}/"}/${local_name} (from $(basename "${built}"))"
