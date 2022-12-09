#!/bin/sh

# Ensure socket directory exists and has the right permissions
mkdir -p /tmp/.X11-unix
chmod 01777 /tmp/.X11-unix

# Create the runtime directory
mkdir -p --mode=700 $XDG_RUNTIME_DIR

export GNOME_SHELL_SESSION_MODE=ubuntu
exec /usr/bin/gnome-session --session=ubuntu
