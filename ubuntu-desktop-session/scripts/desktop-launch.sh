#!/bin/sh

exec gdbus call \
     --session \
     --dest io.snapcraft.Launcher \
     --object-path /io/snapcraft/PrivilegedDesktopLauncher \
     --method io.snapcraft.PrivilegedDesktopLauncher.OpenDesktopEntry \
     "$1"
