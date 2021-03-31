#!/bin/sh

if [ -d /var/snap/network-manager/current/ ]; then
    mkdir -p /var/snap/network-manager/current/conf.d
    cat > /var/snap/network-manager/current/conf.d/disable-polkit.conf <<EOF
[main]
auth-polkit=false
EOF
fi

for plug in hardware-observe home login-session-observe login-session-control \
            mount-observe network-control network-observe system-observe \
            shutdown shell-config-files snapd-control; do
    snap connect "ubuntu-desktop-session:$plug"
done
snap connect ubuntu-desktop-session:network-manager network-manager:service

cp /snap/ubuntu-desktop-session/current/ubuntu-desktop-session.desktop /usr/share/wayland-sessions/
