#!/bin/sh

for plug in hardware-observe home login-session-observe login-session-control \
            mount-observe network-control network-observe system-observe \
            shutdown shell-config-files snapd-control; do
    snap connect "ubuntu-desktop-session:$plug"
done

cp /snap/ubuntu-desktop-session/current/ubuntu-desktop-session.desktop /usr/share/wayland-sessions/
