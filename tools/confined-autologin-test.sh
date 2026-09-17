#!/bin/sh
# confined-autologin-test.sh
#
# The ONLY supported way to enable GDM autologin for scripted/no-GUI
# testing on Ubuntu Core Desktop test VMs (see
# notes/library/gdm-graphical-session.txt for the background).
#
# GDM's autologin path (gdm-autologin) unconditionally execs the
# literal `gnome-session` binary found on PATH. Unlike a real
# password-prompt login, it does NOT consult AccountsService's
# Session= key or any /usr/share/wayland-sessions/*.desktop entry — so
# autologin alone always launches the plain, UNCONFINED upstream
# gnome-session, never the confined snap-wrapped session real users
# get. Enabling autologin without also shimming /usr/bin/gnome-session
# therefore silently tests the wrong thing, with no error or warning.
#
# This script always applies the shim and autologin together, verifies
# the shim actually landed before it will leave autologin enabled, and
# provides a single 'verify'/'disable' path to check/revert cleanly.
# Never enable GDM autologin by hand on this project's test VMs —
# always use this script.
#
# Usage (run as root, i.e. via sudo, on the VM):
#   confined-autologin-test.sh enable <user> [<wrapper-snap> [<wrapper-session>]]
#   confined-autologin-test.sh verify
#   confined-autologin-test.sh disable
#
# Defaults: wrapper-snap=ubuntu-desktop-session, wrapper-session=ubuntu:GNOME

set -eu

CUSTOM_CONF=/etc/writable/gdm3/custom.conf
SHIM_REAL_BACKUP=/tmp/gnome-session.real
SHIM_SCRIPT=/tmp/gnome-session-shim
WRAPPER_DEFAULT=/usr/bin/core-desktop-session-wrapper.sh
STATE_FILE=/tmp/confined-autologin-test.state

usage() {
  cat <<'EOF'
Usage: confined-autologin-test.sh enable <user> [<wrapper-snap> [<wrapper-session>]]
       confined-autologin-test.sh verify
       confined-autologin-test.sh disable

  enable   Install the gnome-session shim for <user>, enable GDM
           autologin for <user>, restart gdm, and verify the shim
           landed. Defaults: wrapper-snap=ubuntu-desktop-session,
           wrapper-session=ubuntu:GNOME.
  verify   Check current state: is the shim mounted, is autologin
           enabled, and (if a session has started) is the resulting
           wayland-0 socket a confined snap session. Prints PASS/FAIL
           per check, exits non-zero if anything fails.
  disable  Unmount the shim, disable autologin, restart gdm, and
           verify a clean revert.
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root (sudo)." >&2
    exit 1
  fi
}

find_wrapper() {
  if [ -x "$WRAPPER_DEFAULT" ]; then
    echo "$WRAPPER_DEFAULT"
    return
  fi
  found=$(command -v core-desktop-session-wrapper.sh 2>/dev/null || true)
  if [ -z "$found" ]; then
    found=$(find /usr -iname 'core-desktop-session-wrapper.sh' 2>/dev/null | head -1 || true)
  fi
  if [ -z "$found" ]; then
    echo "Cannot find core-desktop-session-wrapper.sh anywhere under /usr" >&2
    exit 1
  fi
  echo "$found"
}

shim_mounted() {
  mount | grep -q ' /usr/bin/gnome-session type'
}

autologin_enabled_for() {
  # $1 = expected user
  grep -qE '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true' "$CUSTOM_CONF" \
    && grep -qE "^[[:space:]]*AutomaticLogin[[:space:]]*=[[:space:]]*$1\$" "$CUSTOM_CONF"
}

cmd_enable() {
  require_root
  user="${1:?enable requires a <user> argument}"
  wrapper_snap="${2:-ubuntu-desktop-session}"
  wrapper_session="${3:-ubuntu:GNOME}"
  wrapper_bin="$(find_wrapper)"

  if shim_mounted; then
    echo "A gnome-session shim is already mounted -- run 'disable' first." >&2
    exit 1
  fi

  cp /usr/bin/gnome-session "$SHIM_REAL_BACKUP"
  cat > "$SHIM_SCRIPT" <<SHIM
#!/bin/sh
if [ "\$(id -un)" = "$user" ]; then
  exec "$wrapper_bin" "$wrapper_snap" "$wrapper_session"
else
  exec "$SHIM_REAL_BACKUP" "\$@"
fi
SHIM
  chmod +x "$SHIM_SCRIPT"
  mount --bind "$SHIM_SCRIPT" /usr/bin/gnome-session

  if ! shim_mounted; then
    echo "Shim bind-mount did not take effect -- aborting, not enabling autologin." >&2
    exit 1
  fi

  if grep -q '^\[daemon\]' "$CUSTOM_CONF"; then
    sed -i \
      -e "/^\[daemon\]/,/^\[/{s/^#*[[:space:]]*AutomaticLoginEnable[[:space:]]*=.*/AutomaticLoginEnable = true/}" \
      -e "/^\[daemon\]/,/^\[/{s/^#*[[:space:]]*AutomaticLogin[[:space:]]*=.*/AutomaticLogin = $user/}" \
      "$CUSTOM_CONF"
  fi
  if ! autologin_enabled_for "$user"; then
    # Keys weren't already present (commented or otherwise) to rewrite
    # in place -- append them explicitly under [daemon] rather than
    # trusting a naive append to land in the right section.
    awk -v u="$user" '
      /^\[daemon\]/ && !done {
        print; print "AutomaticLoginEnable = true"; print "AutomaticLogin = " u; done=1; next
      }
      { print }
    ' "$CUSTOM_CONF" > "$CUSTOM_CONF.new"
    mv "$CUSTOM_CONF.new" "$CUSTOM_CONF"
  fi

  if ! autologin_enabled_for "$user"; then
    echo "Failed to set AutomaticLoginEnable/AutomaticLogin under [daemon] -- aborting." >&2
    umount /usr/bin/gnome-session
    exit 1
  fi

  systemctl restart gdm

  echo "$user" > "$STATE_FILE"
  echo "Enabled shim+autologin for '$user'. Run 'confined-autologin-test.sh verify' after login completes to confirm confinement before trusting any test result."
}

cmd_verify() {
  ok=1

  if shim_mounted; then
    echo "PASS: gnome-session shim is mounted."
  else
    echo "FAIL: gnome-session shim is NOT mounted -- any session started now is UNCONFINED."
    ok=0
  fi

  if grep -qE '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true' "$CUSTOM_CONF"; then
    echo "PASS: AutomaticLoginEnable = true"
  else
    echo "FAIL: AutomaticLoginEnable is not true"
    ok=0
  fi

  user="$(awk -F= '/^[[:space:]]*AutomaticLogin[[:space:]]*=/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$CUSTOM_CONF" | tail -1)"
  if [ -n "$user" ]; then
    uid="$(id -u "$user" 2>/dev/null || true)"
    if [ -n "$uid" ] && [ -L "/run/user/$uid/wayland-0" ]; then
      target="$(readlink "/run/user/$uid/wayland-0")"
      case "$target" in
        snap.*/wayland-0)
          echo "PASS: /run/user/$uid/wayland-0 -> $target (confined snap session)" ;;
        *)
          echo "FAIL: /run/user/$uid/wayland-0 -> $target (NOT a confined snap session)"
          ok=0 ;;
      esac
    else
      echo "INFO: no wayland-0 socket yet for user '$user' (uid ${uid:-?}) -- session may not have started yet, re-run verify shortly."
    fi
  fi

  [ "$ok" -eq 1 ]
}

cmd_disable() {
  require_root
  if shim_mounted; then
    umount /usr/bin/gnome-session
  fi
  rm -f "$SHIM_SCRIPT" "$SHIM_REAL_BACKUP" "$STATE_FILE"

  sed -i \
    -e "s/^AutomaticLoginEnable[[:space:]]*=[[:space:]]*true/#  AutomaticLoginEnable = true/" \
    -e "s/^AutomaticLogin[[:space:]]*=\(.*\)/#  AutomaticLogin =\1/" \
    "$CUSTOM_CONF"

  systemctl restart gdm

  if shim_mounted; then
    echo "WARNING: shim still mounted after disable -- investigate." >&2
    exit 1
  fi
  if grep -qE '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true' "$CUSTOM_CONF"; then
    echo "WARNING: autologin still enabled in custom.conf after disable -- investigate." >&2
    exit 1
  fi
  echo "Disabled. GDM restarted with a normal password-prompt greeter."
}

case "${1:-}" in
  enable) shift; cmd_enable "$@" ;;
  verify) cmd_verify ;;
  disable) cmd_disable ;;
  *) usage; exit 1 ;;
esac
