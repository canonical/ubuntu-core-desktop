#!/usr/bin/env bash
set -euo pipefail
profile_dir="${BASE_ROOT}/etc/profile.d"
mkdir -p "${profile_dir}"
cat >"${profile_dir}/serial-terminal.sh" <<'EOF'
# Terminal dimensions for the QEMU serial console.
if [ "$(tty 2>/dev/null)" = "/dev/ttyS0" ]; then
    stty rows 55 cols 86 2>/dev/null || :
fi
EOF
chmod 0644 "${profile_dir}/serial-terminal.sh"
