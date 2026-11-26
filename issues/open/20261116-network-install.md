# Investigate Ubuntu Core Desktop minimal network build

## Impact / Priority

The existing install flow seeds hundreds of megabytes (in the KDE
case more than a gigabyte) of pre-installed snaps into the image
and the seed partition which are immediately redundant — the
store check right after install replaces them with updated
versions. Users who download and install from the network anyway
pay that wasted download, image, and seed-partition space.

Impact derived from the original note's described symptoms.

## Context

The existing install flow for Ubuntu Core Desktop is

- User installs using the installer
- Ubuntu Core Desktop has preceded snaps which get seeded
- On checking the store if there are updated snaps, the updated
  snaps will immediately get installed

This means that the original installer may contain hundreds of
megabytes or in the case of KDE more than a gigabyte of snaps
which are immediately redundant, but which also take up space in
the downloaded image and take up space in the seed partition of
the installed drive.

This is obviously very inefficient for users who are downloading
and installing from the network anyway. We should investigate
more efficient ways of installing - For example a network
installer that pulls the snaps directly from the store at install
time. This would mean having a minimal model as well, which
contains few snaps (Could we get away with just Snapd? Do we even
need that, Or is it possible to somehow bootstrap it?).
