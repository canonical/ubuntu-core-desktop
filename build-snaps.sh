#!/usr/bin/env bash
#
# build-snaps.sh - make sure every snap the image needs is available in the
# snaps/ cache.
#
#   ./build-snaps.sh [--desktop gnome|kde] [--snaps-dir DIR] [--force]
#   ./build-snaps.sh sync [--desktop gnome|kde] [--snaps-dir DIR] [--force]
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
# `sync` refreshes the cache. It does not simply re-download: for each
# component it asks the GitHub API for the asset's sha256 digest and only
# fetches the ones that actually moved (falling back to a download when
# the API offers no digest). --force downloads everything regardless.
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
mkdir -p "${snaps_dir}/.build-state"

rel="${snaps_dir#"${here}/"}"
state_file="${snaps_dir}/.build-state/releases"

# --- Download bookkeeping ---------------------------------------------
#
# One line per component: <component>\t<fingerprint>, where the
# fingerprint is the sha256 of the asset bytes ("sha256:<hex>"). It is
# recorded when the asset is downloaded - by hashing the file we just
# wrote, so it never depends on what the API claims - and compared with
# the API's own digest at sync time.

fingerprint_of() {
    [[ -f ${state_file} ]] || return 0
    awk -F'\t' -v c="$1" '$1 == c { print $2; exit }' "${state_file}"
}

record_fingerprint() {
    local tmp="${state_file}.new"
    {
        if [[ -f ${state_file} ]]; then
            awk -F'\t' -v c="$1" '$1 != c' "${state_file}"
        fi
        printf '%s\t%s\n' "$1" "$2"
    } | sort > "${tmp}"
    mv "${tmp}" "${state_file}"
}

# The digest GitHub reports for an asset in a release, e.g.
# "sha256:<hex>". Empty when the API has none (older GitHub Enterprise,
# or an API change) - callers then fall back to downloading.
remote_digest() {
    local repo=$1 tag=$2 asset=$3 digest
    digest="$(gh api "repos/${repo}/releases/tags/${tag}" \
        --jq ".assets[] | select(.name == \"${asset}\") | .digest" 2>/dev/null |
        head -1)" || return 0
    [[ -n ${digest} && ${digest} != null ]] && printf '%s\n' "${digest}"
}

download() {
    local name=$1 repo=$2 tag=$3 asset=$4 target=$5
    echo "==> ${name}: downloading ${tag}/${asset} from ${repo}"
    gh release download "${tag}" -R "${repo}" -p "${asset}" \
        -O "${target}" --clobber
    record_fingerprint "${name}" "sha256:$(sha256sum "${target}" | cut -d' ' -f1)"
}

# --- Main -------------------------------------------------------------

built=0
downloaded=0
cached=0
current=0

while IFS='|' read -r name repo tag asset local desktops; do
    [[ -n ${name} ]] || continue
    if [[ -n ${desktop} && ${desktops} != both && ${desktops} != "${desktop}" ]]; then
        continue
    fi

    if [[ -d ${here}/local-sources/${name} ]]; then
        force_args=()
        [[ ${force} == 1 ]] && force_args=(--force)
        "${here}/build-snap.sh" "${name}" --snaps-dir "${snaps_dir}" "${force_args[@]}"
        built=$((built + 1))
        continue
    fi

    target="${snaps_dir}/${local}"

    if [[ ${sync} == 0 ]]; then
        if [[ -f ${target} ]]; then
            cached=$((cached + 1))
            continue
        fi
        download "${name}" "${repo}" "${tag}" "${asset}" "${target}"
        downloaded=$((downloaded + 1))
        continue
    fi

    # sync: revalidate, download only what changed.
    if [[ ${force} == 0 && -f ${target} ]]; then
        # A cache filled before this bookkeeping existed has no recorded
        # fingerprint: hash it once rather than throwing the file away.
        have="$(fingerprint_of "${name}")"
        if [[ -z ${have} ]]; then
            have="sha256:$(sha256sum "${target}" | cut -d' ' -f1)"
            record_fingerprint "${name}" "${have}"
        fi
        want="$(remote_digest "${repo}" "${tag}" "${asset}")"
        if [[ -n ${want} && ${want} == "${have}" ]]; then
            current=$((current + 1))
            continue
        fi
    fi
    download "${name}" "${repo}" "${tag}" "${asset}" "${target}"
    downloaded=$((downloaded + 1))
done < <("${here}/build-snap.sh" --table)

if [[ ${sync} == 1 ]]; then
    echo "==> ${rel}/: ${built} from local sources, ${downloaded} downloaded, ${current} already current"
else
    echo "==> ${rel}/: ${built} from local sources, ${downloaded} downloaded, ${cached} already cached"
fi
if [[ ${cached} -gt 0 ]]; then
    echo "    (run './build-snaps.sh sync' to refresh the cached snaps)"
fi
