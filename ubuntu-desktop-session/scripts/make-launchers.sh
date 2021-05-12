#!/bin/sh

desktop_launch=$(realpath $(dirname "$0"))/desktop-launch.sh

desktopdir=$HOME/snap/ubuntu-desktop-session/current/.local/share/applications
icondir=$HOME/snap/ubuntu-desktop-session/current/.cache/launcher-icons

mkdir -p $desktopdir $icondir

for file in /var/lib/snapd/desktop/applications/*.desktop; do
    desktop_id=$(basename $file)
    icon_file=$(grep '^Icon=' $file | head -n1 | cut -d= -f 2)
    icon_copy=$icondir/$(basename $icon_file)
    if [ -f $icon_file ]; then
        cp $icon_file $icon_copy
    else
        icon_copy=$icon_file
    fi
    cat <<EOF > $desktopdir/launch-$desktop_id
[Desktop Entry]
Version=1.0
Type=Application
Name=Launch $(grep '^Name=' $file | head -n1 | cut -d= -f 2)
Icon=$icon_copy
Exec=$desktop_launch $desktop_id
EOF
done
