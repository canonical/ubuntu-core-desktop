#!/bin/sh

mkdir -p /tmp/.X11-unix

export GNOME_SHELL_SESSION_MODE=ubuntu
exec /usr/bin/gnome-session --session=ubuntu
