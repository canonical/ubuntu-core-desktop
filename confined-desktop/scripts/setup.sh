#!/bin/sh

for plug in hardware-observe home login-session-observe login-session-control \
            mount-observe network-control network-observe system-observe \
            shutdown shell-config-files; do
    snap connect "confined-desktop:$plug"
done

cp /snap/confined-desktop/current/confined-desktop.desktop /usr/share/wayland-sessions/
