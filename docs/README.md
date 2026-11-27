# Agent-facing documentation for Ubuntu Core Desktop

This directory holds the project's documentation. It mixes two kinds
of documents: user-facing guides (how to build and run images) and
agent-facing internals (confinement architecture, debugging
methodology, build tooling facts). Read this file first.

How much to read depends on the job:

- **Implementation/execution agents: read selectively.** Only the
  documents your task needs — do NOT load every document into
  context; the internals are large and most tasks touch only one or
  two.
- **Planning agents: read all of it.** A plan made without the full
  picture repeats solved problems and proposes things the project has
  already ruled out (see project-principles.md). If you are planning
  work — an approach, an architecture decision, a multi-step task
  breakdown — read every document in this directory, including the
  ones that look irrelevant to the specific task: the point is to
  have the constraints and prior findings in context before
  committing to a design.

## User-facing guides

- welcome-to-core-desktop.md — the quick start (kept in the repo so it
  stays accurate; copied into Mattermost when needed). Start here.
- building.md — build an Ubuntu Core Desktop image from cached snaps
  (default, fast) or from source; test it in QEMU.
- building-kde.md — the KDE image: prebuilt releases and KDE-specific
  build notes. GNOME builders can skip it.
- models.md — model assertions and signing keys used by the builds.

## Agent-facing internals (read on demand)

Each entry says what it covers and when to read it. Most tasks need
at most one or two of these.

- architecture/ — the 28.04 MVP target architecture as a diagram
  (composition matrix of layers × platforms/personas, and an
  interface map of who exposes and who plugs each snap interface).
  This describes the 28.04 target, not the current 26 system:
  red/"(new)" interfaces do not exist yet. Read when reasoning
  about where a component or interface belongs. See
  architecture/README.md before editing or re-exporting it.
- issue-tracking-system.md — how issues/ works: states, naming,
  Impact/Priority and resolution-note requirements, and the survey
  rule (check existing issues before assuming a bug is new). Read
  before creating, investigating, or moving any issue file;
  issues/README.md is the short version.
- build-tools.md — the image build and component-snap build
  machinery (build tiers, VM run/test tooling and networking, image
  sizing, fakeroot, snapcraft caching, CI housekeeping). Read when
  building images or snaps, running test VMs, or touching CI.
- gdm-graphical-session.md — GDM and the confined GNOME session:
  session snap architecture, confinement mechanism, the first-boot
  wizard chain, GSettings/dconf, library layout binds, snap-private
  /tmp, D-Bus name binds, dynamic session users. Read when working
  on GDM, session startup, confinement, the wizard, or settings.
- kde-internals.md — KDE Neon Core (Plasma): model facts, repos,
  build pipelines (from-source and deb-repack), confinement model,
  plasma-setup wizard. Read when working on KDE.
- core-base-desktop.md — the core26-desktop base snap: thin/desktop
  variants, chisel-vs-apt stage conflicts, /etc/gdm3 writable
  handling. Read when working on core-base-desktop.
- provider-snaps.md — system-service provider snaps (udisks2,
  upower, pipewire): D-Bus activation chains, user-scope daemons,
  audio permission delegation, snap-seccomp gotchas. Read when
  working on provider snaps or audio/storage features.
- accessibility.md — the AT-SPI/orca/speech-dispatcher chain and its
  durable gotchas. Read when working on accessibility.
- session-brokers.md — the privileged helper brokers (FUSE mount
  broker, session environment broker). Read when working on portals,
  document mounts, or session environment propagation.
- boot-diagnostics.md — diagnosing boot loops and failed run-mode
  transitions; partition layout and image sizing. Read when a VM
  will not boot, boot-loops, or when touching image partitioning.
- diagnostics-methodology.md — general debugging techniques for the
  images (live-patching a read-only rootfs, journal access, the two
  D-Bus denial mechanisms, strace in confinement, extrausers
  accounts, /proc/<pid>/root views, QEMU audio, misc VM recipes).
  Read when debugging anything on a running image.
- snap-signing.md — how model assertions are signed, and signing
  gotchas.
- upstream-contributions.md — how to send a fix from this project's
  forks upstream.
- project-principles.md — standing architecture principles used to
  evaluate design choices.
- dev-branch-conventions.md — which branch to base work on and how
  to keep shared branches clean.
- git-commit-conventions.md — the commit message format.
- subagent-management.md — how to dispatch and manage sub-agents
  reliably.

## Build downloads: use a caching proxy

Any build that runs snapcraft (component source builds) downloads
hundreds of megabytes of build packages and snaps, and repeats that
on every rebuild. Install and run pkgproxy first:

    sudo snap install pkgproxy
    pkgproxyctl setup snapcraft | sh    # what snapcraft builds download
    pkgproxyctl setup lxd-remote | sh   # its build images

The same applies to apt and Go module fetches. A slow build without
a cache is expected — set the proxy up rather than blaming the build
system. The default "assemble from cached snaps" path in building.md
does not need this; it downloads prebuilt snaps once into a local
cache.

## Running a built image

`./run-qemu.sh` boots `build/pc.img` under QEMU/KVM (see "Test the
Image in QEMU" in building.md / building-kde.md). Diagnostics hooks:

- `--vnc` serves the display over VNC — watch a boot or the wizard
  graphically, take QEMU monitor screendumps (PNG form).
- The serial console comes up on a unix socket (`--serial-socket`);
  connect with `nc -U` and log in as root with the
  `--root-password` password — works even when sshd never comes up,
  which is what makes it the tool for boot diagnosis.

## Keeping these documents current

Agents should keep these docs up to date:

- If you find a document that is inaccurate or out of date (a command
  changed, a mechanism was replaced, a note describes something that
  no longer exists), fix it.
- If you produce findings that would be genuinely useful to future
  agents — a reusable gotcha, a debugging technique, an architectural
  fact — add them to the relevant document, briefly.

Limits (these matter):

- This is not a dumping ground. Additions must be useful to agents
  run by other people on other machines — not local-only facts (user
  names, this machine's setup), and not a history of what work was
  done. Specific issue resolutions belong in the relevant issue file
  under issues/, not here.
- Be brief and to the point. Drop content if it is obsolete and has
  been superseded by later content. We are writing an instruction
  manual for future agents, not a history book.
