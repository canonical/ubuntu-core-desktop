# GNOME Core Desktop: accessibility (AT-SPI/screen reader) status

STATUS (2026-11-23): the screen-reader chain works end-to-end on the
GNOME image and was live-verified over 2026-11-16..20. Boot ->
~10-20s -> the greeter ANNOUNCES itself automatically (a boot-time
mirror writes screen-reader-enabled into the greeter session's
settings, so the greeter's gsd starts orca with no input) -> the
password typed blind is spoken -> login -> the desktop starts the
reader per the user's own setting (the wizard's choice was handed
over at user creation) -> on first-boot devices the wizard speaks via
the Super+Alt+S chord + the orca shim. Settings state rides the single
dconf store (gdm-graphical-session.md's GSettings section), NOT a
keyfile; the older keyfile-mechanism designs are superseded.

Original root cause, kept as a staging lesson: stock Ubuntu desktop
gets at-spi2-core and orca/speech-dispatcher via the `ubuntu-desktop`
metapackage's DEPENDS/RECOMMENDS; this project stages by an explicit
package list + transitive deps, and nothing in that set DEPENDed on
any of them, so they were silently absent (no AT-SPI bus, no reader:
the Screen Reader toggle flipped a key with no observable effect).
Whenever a new desktop variant or wizard is staged, re-check this
class — RECOMMENDS-only components don't arrive by themselves. The
fix landed as a snapped orca/speech stack (a11y snap) rather than base
staging.

Pieces of the chain and their durable gotchas:

- The wizard's gnome-shell (--mode=initial-setup) does NOT bind
  Super+Alt+S itself — the keystroke leaks into page navigation (it
  once moved the language selection to Shqip). The chord is seeded as
  a gsd media-keys CUSTOM KEYBINDING for the initial-setup session.
- Launching orca inside the wizard session needs DISPLAY and
  XAUTHORITY of the wizard session's own Xwayland (transient
  Xwaylands; mutter writes per-spawn auth files at
  /run/user/<uid>/.mutter-Xwaylandauth.*) — discover them from the
  live gnome-shell's env or the sockets. Without them, orca's at-spi
  X11 device layer dies on an atspi_device_x11_init assertion.
- The handover of the wizard's reader choice to the created user is a
  path-triggered ROOT capture reading the wizard session's live key AT
  CreateUser — the only moment the wizard db exists (an apply-time
  read is impossible: the apply runs as the target user and the wizard
  home is wiped before first login). provd's SetAccessibility API cache
  stays STALE (screen-reader-enabled=false despite the reader running)
  — do not read that API as ground truth.
- The greeter's settings home is per-boot tmpfs: nothing persists, so
  the mirror re-delivers the recorded reader state EVERY boot (by
  design). GDM dynamic users have incrementing/reused uids and nologin
  shells — see gdm-graphical-session.md's dynamic-users section.
- `gsettings set` exits 0 even when the commit fails — every a11y
  write is read back before it is acted on (see the GSettings rules in
  gdm-graphical-session.md).

Speech-dispatcher supervisor rules (the speech backend runs under a
supervisor; these cost days to discover):

- This systemd generation passes LISTEN_PIDFDID (a pidfd of the unit
  main pid) with socket activation. A supervisor that spawns the
  speechd server as a child and rewrites LISTEN_PID cannot satisfy
  libsystemd's pidfd identity check -> the child's fd claim fails ->
  speechd UNLINKS the activation socket and self-binds silently,
  orphaning queued connections forever with no error logged anywhere
  (every process healthy-looking, rc=0 probes, nothing speaks). The fd
  must be handed over via speechd's own SPEECHD_SOCK_FD hook, never a
  LISTEN_PID rewrite. The sd_listen_fds identity check is by design —
  the supervisor was the mistake; the only upstream ask (recorded, not
  filed) is that speechd LOG the failed claim instead of silently
  self-binding (20261118-speechd-silent-fdclaim-logging-upstream.md).
- A DEAD speechd self-heals via socket activation (the next probe
  returns rc=0); a WEDGED one (alive, unresponsive, swallows SIGTERM)
  needs SIGKILL — Restart=on-failure cannot catch a hang. Probe with a
  reply-based SSIP handshake (SET SELF CLIENT_NAME — <1ms, never a
  speech round-trip), SIGKILL on a ~10s threshold, respawn in-process.
- libspeechd 2.6.0 requires SPEECHD_ADDRESS=unix_socket:<path> — the
  bare-path form does not parse; every probe recipe must carry it.
- spd-say's rc=0 proves message acceptance only, never audio, and the
  speechd log records no payloads. For audio truth, sample
  /proc/asound/card0/pcm0p/sub0/status at 0.1-0.2s cadence DURING
  speech (RUNNING = rendering; a "closed" reading taken after
  playback is normal) — see diagnostics-methodology.md's QEMU audio
  section for getting guest speech to a human listener over VNC.

Shell/mutter-internal a11y features (magnifier, high-contrast/
large-text, on-screen keyboard, sticky/slow/bounce/toggle/mouse keys,
cursor size, visual alerts) were never affected by the snap packaging
and need no wiring.
