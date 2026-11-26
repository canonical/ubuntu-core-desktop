# speech-dispatcher wedges forever on a blocking audio open; SIGTERM ineffective

## Impact / Priority

A screen-reader user gets ONE announcement (orca's startup speech) and
then permanent silence from the reader — with every symptom looking
healthy (the reader process runs, speechd accepts connections).
Recovery requires a manual kill -9. Any transient audio-stack hiccup
at boot (a misbehaving sink, a slow daemon, a half-created socket)
bricks the reader for the session.

## The defect

Written 2026-11-16. Found live during the gate-8 human-testing session
on the thin-line a11y stack (the full narrative and evidence are in
`20261110-thin-line-a11y-snapped-provider-spike.md`, the [2026-11-16]
gate-8 live session entries). Task: reproduce, root-cause, and land a
fix upstream.

speech-dispatcher (the a11y snap's instance, but the defect is in
upstream speechd's design) permanently wedges when its output module's
audio open blocks. Observed live, 2026-11-16, on the gate-8 VM (guest
bootid 3508d51f, the server boot-spawned 13:53):

- The server (pid 5388, /snap/ubuntu-desktop-a11y/x2/usr/bin/
  speech-dispatcher -s -t 0) accepted client connections and
  negotiated protocol normally — orca's 13:58:05 handshake wrote
  2.8 MB of voice-list chatter to speech-dispatcher.log, ending
  "200 OK VOICE LIST SENT".
- The FIRST actual speech dispatch never completed. Every
  subsequent message queued behind it forever: spd-say -w hung
  indefinitely (a hung runuser/spd-say was still parked on the
  guest 40+ minutes later); ZERO further log writes; zero audio
  streams ever created in pipewire; the HDA pcm never opened.
- The boot-spawned espeak module processes existed with 0-BYTE
  logs their whole life (born-hung candidates: the module's audio
  open at init targeted the then-default sink — the T31-tainted
  "VM audio RTP" sink that had won the boot's default-sink race —
  and blocked; OR a boot-order race vs the not-yet-ready audio
  daemons; NOT YET DISCRIMINATED — see the reproduction plan).
- SIGTERM was SWALLOWED: kill 5388 did nothing (speechd installs
  handlers; the blocked main thread never reaches them).
  systemctl --user restart of the socket unit FAILED ("Job
  failed" — stopping the wedged service hangs). Only SIGKILL
  freed it; the socket unit then spawned a fresh server whose
  first probe synthesized and rendered instantly (pcm
  state:RUNNING x6, audible through the headset).
- A zombie child ([speech-dispatch] <defunct>, pid 5427) sat
  unreaped from boot until the SIGKILL.

## Why it is upstream-class (not just our config)

Even with a perfectly clean configuration, ANY blocking audio open
(module init or first dispatch) bricks speechd permanently: no
timeout on the module round-trip, no module restart/retry, no
health monitoring, and a signal-handling design that cannot
terminate while a thread is blocked. The trigger may be ours (see
below) — the failure MODE is speechd's.

## Trigger analysis (two hypotheses, not yet discriminated)

H-A (our taint as trigger): the T31 RTP drop-in
  (~/snap/pipewire/x1/.config/pipewire/pipewire.conf.d/10-rtp.conf
  in the TAINTED-T31-rtp tester image) wins the boot default-sink
  race on some boots; the module's audio open targets the RTP sink
  and hangs there. Contrast datapoint: T35's boot 3 the same day
  had the HDA sink win the race and audio worked; this boot the
  RTP sink won and the server wedged. Pattern: RTP-default boots
  wedge, HDA-default boots work.
H-B (boot-order race, taint-independent): the speechd modules
  spawned at boot (13:53:29) raced the audio daemons (pipewire,
  pipewire-pulse also starting at 13:53) and hung connecting to a
  socket that existed but was not yet accepting.
DISCRIMINATOR: disable the taint (rename the 10-rtp.conf drop-in)
and reboot twice — no wedge = H-A; still wedges = H-B.
[2026-11-17 UPDATE: H-B AS WRITTEN IS INVALID. In 0.12.1 espeak-ng
uses server audio and never opens audio itself; a module hung at INIT
would have prevented the server from accepting clients at all. The
server's PulseAudio open is the hang point. See the ROOT-CAUSED
section below.]

## Tasks

1. UPSTREAM-FIRST CHECK: search brailcom/speechd (the upstream
   repo) for existing issues/PRs about hung audio opens, module
   timeouts, or SIGTERM handling; check the version deltas between
   the snap's speechd and upstream master. Record findings here
   before writing anything.
2. DETERMINISTIC REPRODUCTION:
   a. The on-image discriminator (rename the taint + reboot x2;
      needs a VM reboot — run AFTER the gate-8 session).
   b. A synthetic, upstream-friendly repro independent of our
      stack: point speechd's audio at a sink whose open blocks
      indefinitely (candidate: a stub pulse/pipewire server that
      accepts connections but never completes the handshake; or a
      suspended ALSA device as default) — the goal is a minimal
      "speechd + blocking audio open = permanent wedge, SIGTERM
      ineffective" recipe any maintainer can run.
   c. CAPTURE THE HANG POINT during a live wedge: gdb -p the
      server + thread apply all bt (and/or /proc/<pid>/task/*/wchan
      + stack) — name the exact syscall/frame the dispatch thread
      blocks in. This evidence goes in the upstream report.
3. ROOT-CAUSE IN CODE: speechd's module dispatch path (the server
   waits on the module with no bounded time) + the module's
   spd_audio_open (no timeout) + the signal design (handlers that
   a blocked thread starve). Identify the minimal patch surface.
4. FIX PR UPSTREAM: bounded audio-open/dispatch (timeout +
   module restart and/or a watchdog thread), and safe termination
   (self-pipe/signalfd or handler-thread design so SIGTERM works
   while any thread is blocked). Repo: brailcom/speechd; check how
   Ubuntu's src:speech-dispatcher tracks it. The a11y snap vendors
   speechd — the fix lands upstream first, then re-vendored.
5. LOCAL HARDENING (independent of upstream acceptance): add
   WatchdogSec (or a liveness probe) to the a11y snap's speechd
   socket unit so a wedged server self-heals instead of requiring
   a manual kill -9. Joins the C8/C9 lifecycle items from the a11y
   lifecycle review.
6. VERIFICATION: with the fix, the synthetic repro DEGRADES
   GRACEFULLY (speech fails for the hung sink but the server stays
   responsive and recovers when the sink returns; SIGTERM
   terminates); orca survives a hung sink with announcements
   resuming after recovery.

## Root-caused (2026-11-17)

A fix prototype was built (the old 0.12.1 patch was removed;
re-vendor after upstream acceptance).

## Independent review correction (2026-11-18)

The live gate-8 incident was NOT the one-time PulseAudio open. The
live log has "Audio interrupted" at 13:57:53 (705 server-audio path,
valid audio handle), stale-fd index-mark errors at 13:57:54, then the
13:58:05 voice list; the one-time open had already completed. The
live stall is in the playback/stop path's unbounded libpulse waits
(write/flush/drain timing), triggered by a stop/flush when the peer
stopped servicing the connection. The silent-open synthetic repro is
a separate real defect. Both are covered by Revision 2 (all mainloop
waits bounded, connection reset/refcount, per-message audio failure,
CANCEL instead of END, and a lock-free 10 s shutdown watchdog). The
branch was rewritten; full verification and remaining follow-ups (B4
main-loop lock hold, dedicated signal thread, dlopen leak, fd
TOCTOU, module-close lifetime) tracked with the fix work.

## Verdict (initial-open defect, still valid)

The hang is in the SERVER's PulseAudio open, not the espeak module.
In 0.12.1 espeak-ng uses server audio (module_audio_set_server) and
never calls spd_audio_open. The speak thread runs
speak -> output_speak -> output_set_speaking_monitor ->
output_open_audio -> spd_audio_open("pulse") -> pulse_open ->
spd_pa_simple_new -> pa_threaded_mainloop_wait (pulse.c:231/268) with
NO deadline. A peer that accepts but never completes the handshake
wedges it forever. The thread holds output_layer_mutex and has
cancellation disabled (output_lock, deliberately per upstream #471);
SIGTERM quits the glib loop but pthread_join(speak_thread)
(speechd.c:1453) then blocks forever. The signal handler is NOT
starved: the live log reaches "Terminating..." + "Closing open
connections..." at 14:18:03 and then stops until SIGKILL at
14:31:59. In the initial-open case the modules are bystanders (they
never receive the speech SET/SPEAK; the live incident had already
delivered audio).

## Live evidence

(Read-only; the gate-8 test VM, same boot 3508d51f..., no changes.)
The append-only server log (7.9 MB) shows the 13:58:05 voice list,
then 14:18:03 shutdown start, then silence until the 14:31:59 SIGKILL
(38m29s wall) and the 14:32:00 fresh server. The fresh server still
has an unreaped module zombie (pid 65832, ppid 65806, Z, 1d+ old) — a
separate 0.12.1 defect that master's 38bd2def/#1133 only partially
covers. The previous boot's stops also show two status=11/SEGV
events.

## Synthetic repro (deterministic, no VM reboot)

A stub PulseAudio Unix socket that accepts/reads but never replies; a
private 0.12.1 with PULSE_SERVER pointing at it; spd-say -w hangs.
gdb shows the speak thread in pa_threaded_mainloop_wait under
spd_audio_open, the libpulse thread polling the silent socket, and
after SIGTERM main in pthread_join with the speak thread still
stuck. This matches the live signature exactly.

H-A/H-B STATUS: H-B as written is invalid for 0.12.1 — the modules do
not open audio; a module hung at INIT would have prevented the server
from ever accepting clients. H-A remains possible but the real
trigger is still undetermined (no pulse/pipewire error in the
journal; the current 434-byte queue is on pipewire-pulse's D-Bus
connection, not proof). The defect is trigger-independent; the
disposable-VM discriminator (pactl info during a wedge) is covered by
the root-cause work.

## Fix prototype (5 commits, 131 insertions, builds and passes the repro)

1. pulse.c: pa_context_rttime_new() deadline on the context/stream
   readiness waits + NULL-connection guards in feed/end/stop.
2. speak_queue.c: honour spd_audio_begin() failure (a captured core
   showed pulse_feed dereferencing pa_simple == NULL after a failed
   reopen).
3. output.c/h + module.h: return an error from
   output_set_speaking_monitor(), retry a failed open with a 5 s
   backoff instead of disabling audio for the session.
4. speaking.c: on output failure, report END (if requested), free
   the message (it was leaked), clear speaking_module — spd-say -w
   hung even after the server failed the message.
5. speechd.c: 5 s shutdown watchdog; if cleanup hangs, log and
   _exit(EXIT_FAILURE) so systemd can restart.
VERIFIED: silent peer -> 3 s timeout -> "Opening audio failed" ->
702 END -> spd-say -w rc=0 -> SIGTERM clean; first-fail then
real-sink retry -> speech resumes, 3/3; 60 s open + SIGTERM ->
watchdog exit rc=1 after 5005 ms; normal real-pulse path still
speaks.
Caveats: 3 s is a test value (upstream should use ~10 s and make it
configurable); END on failure is not a true error event; the
watchdog only makes stop/restart reliable, it does not self-heal a
running server (still needs a speech-progress systemd heartbeat).

## Upstream

#977 "Cope with hanging modules" is still open and is the right
umbrella for module timeouts; #1138 "Segfault when cancelling
speech" (open, 2026-11-09, Fedora 0.12.1, spd_pa_simple_flush(p=0x0))
is the direct match for the stop/NULL close race fixed here; #1022
(spd-say speaks then hangs, Alpine) was closed stale; #235 is an old
interrupt hang; #471 is the cancellation-disabled rationale; #1026 is
a different condvar stall; #1137 is the Python client; #1133/38bd2def
only reaps load-failure zombies. Master as of 2026-11-16 still has
both unbounded waits. Ubuntu 0.12.1-2ubuntu1 = upstream 0.12.1 +
doc-figures/systemd-debian/mbrola-paths (none touch src/). The 5
commits are rebased to master af73916, built, and pass the same
repro; next post the repro/stacks, then re-vendor into the a11y snap
after acceptance. The systemd WatchdogSec idea needs sd_notify()
plus a speech-progress heartbeat (a main-loop ping would keep
pinging while the speak thread is wedged); snapd supports
watchdog-timeout.

## Status

- [2026-11-16] Issue created. NOT STARTED. The wedge was fixed live
  on the gate-8 VM (SIGKILL + fresh server) — the VM is healthy and
  the human gate-8 session continues on it; ALL reproduction
  experiments here need reboots or a second VM, so they queue until
  after gate 8 (or run in a separate disposable VM). The pointer
  from the spike issue's [2026-11-16] gate-8 live session entries
  leads here for the follow-up work.
- [2026-11-17] ROOT-CAUSED, deterministic repro captured, fix
  prototype built and verified on the host (no VM changes; the
  in-use VM was introspected read-only). Master rebase also built
  and repro-tested. [2026-11-18] committed to a local clone of the
  upstream speechd repo on branch fix/hung-pulse-open (5 commits on
  af73916, local only, not pushed). OPEN: push/post upstream,
  decide timeout default + failed-message semantics, re-vendor, and
  the separate zombie + systemd speech-progress watchdog items.
- [2026-11-18] INDEPENDENT REVIEW + REVISION: the first patch was
  reviewed, then revised through several review cycles. Final
  branch commits are 14e9aa07 (pulse: all waits bounded,
  no-progress drain, connection reset/refcount), 6d2be898
  (speak_queue: fail current message, cancel END, drop unspoken
  marks), b6d0c003 (output retry), 6a0dcf4a (CANCEL + semaphore),
  70dfb2ac (lock-free 10 s watchdog). Tests: healthy direct/
  slow-proxy playback, silent open -> 703, mid-playback freeze ->
  703, freeze then second message -> new connection/702, two
  queued messages both 703, freeze+stop 3/3 no crash, 60 s open +
  SIGTERM -> watchdog rc=1 after 10 s. Remaining follow-ups: B4
  open under element_free_mutex/output_layer_mutex (main-loop
  block up to the timeout), no dedicated signal thread, dlopen ref
  leak, fd dup TOCTOU, module-close lock lifetime, timeout
  config/NEWS, responsive non-consuming sink test.
- [2026-11-18] PR OPENED upstream:
  https://github.com/brailcom/speechd/pull/1141 (Refs #1138, #977;
  base master af73916a; head chris-bainbridge:fix/hung-pulse-open;
  mergeable and clean at open; no CI checks configured). It states
  the issue was found in real-world screen-reader testing.
