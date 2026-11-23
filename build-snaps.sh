#!/usr/bin/env bash
#
# build-snaps.sh - make sure every snap the image needs is available in the
# snaps/ cache.
#
#   ./build-snaps.sh [--desktop gnome|kde] [--snaps-dir DIR] [--force]
#   ./build-snaps.sh sync [--desktop gnome|kde] [--snaps-dir DIR]
#
# For each component (the table lives in build-snap.sh, which also owns the
# build recipes):
#
#   - if local-sources/<component> exists, build it with
#     ./build-snap.sh <component>. That is a no-op when the tree has not
#     changed since the last build, so this is cheap to call every time.
#
#   - otherwise, use the cached snap in snaps/. A missing one is
#     downloaded from the component's desktop-26-latest GitHub release.
#     An existing one is left alone - these are rolling releases that
#     change on every green CI run, so silently picking up new ones would
#     make local builds slow and non-reproducible.
#
# `sync` is the only thing that refreshes the cache: it re-downloads every
# component that is not overridden by a local source. Run it when you want
# the latest CI snaps.
#
# Nothing here knows how to build a snap; that is build-snap.sh's job.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

snaps_dir="snaps"
desktop=""
force=0
sync=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) sed -n '3,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        sync) sync=1; shift ;;
        --desktop) desktop="$2"; shift 2 ;;
        --snaps-dir) snaps_dir="$2"; shift 2 ;;
        --force) force=1; shift ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

case "${desktop}" in
    ""|gnome|kde) ;;
    *) echo "Invalid --desktop '${desktop}' (must be gnome or kde)." >&2; exit 1 ;;
esac

[[ ${snaps_dir} = /* ]] || snaps_dir="${here}/${snaps_dir}"
mkdir -p "${snaps_dir}"

rel="${snaps_dir#"${here}/"}"

built=0
downloaded=0
cached=0

while IFS='|' read -r name repo tag asset local desktops; do
    [[ -n ${name} ]] || continue
    if [[ -n ${desktop} && ${desktops} != both && ${desktops} != "${desktop}" ]]; then
        continue
    fi

    source="local-sources/${name}"
    if [[ -d ${here}/${source} ]]; then
        force_args=()
        [[ ${force} == 1 ]] && force_args=(--force)
        "${here}/build-snap.sh" "${name}" --snaps-dir "${snaps_dir}" "${force_args[@]}"
        built=$((built + 1))
        continue
    fi

    target="${snaps_dir}/${local}"
    if [[ ${sync} == 0 && -f ${target} ]]; then
        cached=$((cached + 1))
        continue
    fi

    echo "==> ${name}: downloading ${tag}/${asset} from ${repo}"
    gh release download "${tag}" -R "${repo}" -p "${asset}" \
        -O "${target}" --clobber
    downloaded=$((downloaded + 1))
done < <("${here}/build-snap.sh" --table)

echo "==> ${rel}/: ${built} from local sources, ${downloaded} downloaded, ${cached} already cached"
if [[ ${cached} -gt 0 && ${sync} == 0 ]]; then
    echo "    (run './build-snaps.sh sync' to refresh the cached snaps)"
fi
