#!/bin/sh

# Ensure socket directory exists and has the right permissions
mkdir -p /tmp/.X11-unix
chmod 01777 /tmp/.X11-unix

export GNOME_SHELL_SESSION_MODE=ubuntu
exec /usr/bin/gnome-session --session=ubuntu
