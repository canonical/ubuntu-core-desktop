#!/bin/bash
# Builds a NoCloud cloud-init seed ISO (cidata) for an Ubuntu Core (Desktop) VM:
#  - creates a user (see --user) with password "x" (modern non-deprecated
#    chpasswd syntax)
#  - tells cloud-init not to delete/regenerate SSH host keys, since
#    build-gnome.sh --ssh-host-key already bakes a persistent one into
#    the image itself (this script is not the source of truth for that
#    key -- see build-gnome.sh --help)
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: build-cloud-init.sh --user <name> [options]

Builds a NoCloud cloud-init seed ISO for an Ubuntu Core (Desktop) VM:
creates a sudo-enabled user account, and preserves the persistent SSH
host key build-gnome.sh already baked into the image (instead of
letting cloud-init delete + regenerate one on every fresh instance-id).

Required:
  --user <name>                Name of the sudo-enabled user account to
                                create via cloud-init.

Optional:
  --output <path>               Path to write the seed ISO to (default:
                                seed.iso).
  --ssh-authorized-keys <path>  File of SSH public keys (one per line)
                                to authorize for --user (default:
                                authorized_keys). Skipped if the file
                                doesn't exist or is empty (password
                                login only).
  -h, --help                    Show this help and exit.
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

build_user=""
OUT="seed.iso"
AUTHKEYS_FILE="authorized_keys"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --user) build_user="$2"; shift 2 ;;
        --output) OUT="$2"; shift 2 ;;
        --ssh-authorized-keys) AUTHKEYS_FILE="$2"; shift 2 ;;
        *)
            echo "Unknown flag: ${1}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z ${build_user} ]]; then
    echo "Missing required --user <name>." >&2
    exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Indent every line of a file by N spaces (for embedding under a YAML block).
indent() { sed 's/^/'"$(printf '%*s' "$1" '')"'/' "$2"; }

{
cat <<EOF
#cloud-config
# NOTE: on Ubuntu Core, cloud-init writes users to /var/lib/extrausers/*
# (via --extrausers), not /etc/passwd, since the base OS is read-only.
users:
  - name: ${build_user}
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: false
EOF

if [ -s "$AUTHKEYS_FILE" ]; then
    echo "    ssh_authorized_keys:"
    # one YAML list item per non-blank/non-comment line of the keys file
    grep -v '^[[:space:]]*#' "$AUTHKEYS_FILE" | grep -v '^[[:space:]]*$' \
        | sed 's/^/      - /'
    echo "Embedding $(grep -vc '^[[:space:]]*#\|^[[:space:]]*$' "$AUTHKEYS_FILE") authorized key(s) from $AUTHKEYS_FILE" >&2
else
    echo "No $AUTHKEYS_FILE found (or empty) -- skipping ssh_authorized_keys, password login only" >&2
fi

cat <<EOF

chpasswd:
  users:
    - name: ${build_user}
      password: x
      type: text
  expire: false

ssh_pwauth: true

# Don't wipe /etc/ssh/ssh_host_*key* on first boot -- build-gnome.sh
# --ssh-host-key already baked a persistent keypair into the image
# itself, so there is no ssh_keys: section here supplying key material;
# this just stops cloud-init from deleting/replacing it.
ssh_deletekeys: false
EOF
} > "$WORKDIR/user-data"

cat > "$WORKDIR/meta-data" <<'EOF'
instance-id: core-desktop-seed
local-hostname: core-desktop
EOF

if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "$OUT" "$WORKDIR/user-data" "$WORKDIR/meta-data"
elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -output "$OUT" -volid cidata -joliet -rock \
        "$WORKDIR/user-data" "$WORKDIR/meta-data"
elif command -v mkisofs >/dev/null 2>&1; then
    mkisofs -output "$OUT" -volid cidata -joliet -rock \
        "$WORKDIR/user-data" "$WORKDIR/meta-data"
elif command -v xorriso >/dev/null 2>&1; then
    xorriso -as genisoimage -output "$OUT" -volid cidata -joliet -rock \
        "$WORKDIR/user-data" "$WORKDIR/meta-data"
else
    echo "ERROR: need one of cloud-localds, genisoimage, mkisofs, xorriso installed." >&2
    echo "  sudo apt install cloud-image-utils   # provides cloud-localds (preferred)" >&2
    echo "  or: sudo apt install genisoimage" >&2
    exit 1
fi

echo "Wrote NoCloud seed ISO: $OUT"
