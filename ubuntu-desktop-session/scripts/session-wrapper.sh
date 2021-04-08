#!/bin/bash

# This script runs outside of snap confinement as a wrapper around the
# confined desktop session.

# Set up PATH and XDG_DATA_DIRS to allow calling snaps
if [ -f /snap/snapd/current/etc/profile.d/apps-bin-path.sh ]; then
    source /snap/snapd/current/etc/profile.d/apps-bin-path.sh
fi

# The confined desktop environment will probably be on :0, so this is
# one less thing to fix up after login.
export DISPLAY=:0

dbus-update-activation-environment  --systemd --all

exec /snap/bin/ubuntu-desktop-session
