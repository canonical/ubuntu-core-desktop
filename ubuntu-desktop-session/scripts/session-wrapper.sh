#!/bin/bash

# This script runs outside of snap confinement as a wrapper around the
# confined desktop session.

# Set up PATH and XDG_DATA_DIRS to allow calling snaps
if [ -f /snap/snapd/current/etc/profile.d/apps-bin-path.sh ]; then
    source /snap/snapd/current/etc/profile.d/apps-bin-path.sh
fi

export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export GSETTINGS_BACKEND=keyfile

dbus-update-activation-environment --systemd --all

# Don't set this in our own environment, since it will make
# gnome-session believe it is running in X mode
dbus-update-activation-environment --systemd WAYLAND_DISPLAY=wayland-0

# Set up a background task to wait for gnome-session to create its
# Xauthority file, and copy it to a location snaps will be able to
# see.
function fixup_xauthority() {
    while :; do
        sleep 1s
        xauth_file="$(ls -1t /run/user/$(id -u)/snap.ubuntu-desktop-session/.mutter-Xwaylandauth.* | head -n1)"
        if [ -f "$xauth_file" ]; then
            cp "$xauth_file" /run/user/$(id -u)/.Xauthority
            return
        fi
    done
}
#fixup_xauthority &

# Wait in background to link Wayland socket to location where other
# snaps will look for it.
function link_wayland_socket() {
    private_socket=/run/user/$(id -u)/snap.ubuntu-desktop-session/wayland-0
    public_socket=/run/user/$(id -u)/wayland-0
    while :; do
        sleep 1s
        if [ -S "$private_socket" ]; then
            ln -f "$private_socket" "$public_socket"
            return
        fi
    done
}
link_wayland_socket &

exec /snap/bin/ubuntu-desktop-session
