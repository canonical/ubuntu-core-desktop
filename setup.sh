#!/bin/sh

if [ -d /var/snap/network-manager/current/ ]; then
    mkdir -p /var/snap/network-manager/current/conf.d
    cat > /var/snap/network-manager/current/conf.d/disable-polkit.conf <<EOF
[main]
auth-polkit=false
EOF
fi

cp /snap/ubuntu-desktop-session/current/ubuntu-desktop-session.desktop /usr/share/wayland-sessions/

for plug in hardware-observe home login-session-observe login-session-control \
            mount-observe network-control network-observe polkit-agent \
            process-control system-observe shutdown shell-config-files \
            snapd-control upower-observe; do
    snap connect "ubuntu-desktop-session:$plug"
done
snap connect ubuntu-desktop-session:network-manager network-manager:service

snap connect ubuntu-desktop-session:desktop-launch || true

for snap in evince gnome-calculator gnome-characters gnome-clocks gnome-font-viewer gnome-text-editor gnome-weather snap-store workshops; do
    snap connect "$snap:x11" ubuntu-desktop-session:x11
    snap connect "$snap:wayland" ubuntu-desktop-session:wayland
    snap connect "$snap:desktop" ubuntu-desktop-session:desktop
done

/snap/bin/lxd init --auto
