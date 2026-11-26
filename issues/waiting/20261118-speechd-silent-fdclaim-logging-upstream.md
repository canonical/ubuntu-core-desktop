---
upstream: https://github.com/brailcom/speechd/pull/1142
waiting_since: 2026-11-18
---
# speechd: failed socket-activation fd claim falls back silently — should log

## Impact / Priority

A screen-reader user gets NO speech at all while every process
looks alive and healthy: when speechd's socket-activation fd
claim fails, it unlinks the activation socket and self-binds a
fresh anonymous socket with NO error logged anywhere; the
socket-activation unit keeps looking healthy and queued client
connections strand. That silence turned a config mistake into a
multi-day screen-reader outage (it took a multi-day
investigation to find the one unlinked socket).

## Context

Written 2026-11-18. Owner ruling on T50's root-cause: the
sd_listen_fds identity check behaves AS DESIGNED (systemd's
pidfd verification correctly refused a mismatched handoff — "it
was our own tooling that made a mistake": the T47 supervisor
rewrote LISTEN_PID for its child while this systemd generation
passes LISTEN_PIDFDID, which cannot be rewritten). Our fix is in
our code (T50: the supervisor now hands the fd via speechd's own
SPEECHD_SOCK_FD hook). The ONLY upstream issue: speechd's
fallback when the fd claim fails is completely SILENT, and that
silence is what turned a config mistake into a multi-day
screen-reader outage.

## The incident (the evidence chain)

1. The a11y snap's speech-dispatcher runs socket-activated under
   a supervisor (T47's watchdog design: bin/run-speech-dispatcher
   execs bin/speechd-supervisor.py, which spawns the server as a
   child and passes the listening fd down).
2. This systemd generation passes LISTEN_PIDFDID (a pidfd of the
   unit main pid = the supervisor) alongside LISTEN_PID. The
   supervisor's LISTEN_PID rewrite made the child's environment
   claim the child's pid, but the pidfd still referenced the
   supervisor -> the child's sd_listen_fds() identity check
   failed -> zero fds returned.
3. speechd's reaction: it UNLINKED the unit's socket and
   self-bound a fresh anonymous socket — with NO error logged
   anywhere. The socket-activation unit kept looking healthy;
   the queued client connections (orca's login-time connect,
   the watchdog's probes) sat stranded in the orphaned socket
   (Recv-Q=2, verified live) for the entire session.
4. User impact: a screen-reader user gets NO speech at all while
   every process looks alive and healthy; it took a multi-day
   investigation (the T44/T45/T49 rc=0 probes masked it further
   — message acceptance is independent of the audio path) to
   find the one unlinked socket.
5. Full mechanism + verbatim evidence: the "RACE LAYER VERDICT"
   section of the T50 startup-race report and the 2026-11-18 T50
   entry in
   `20261110-thin-line-a11y-snapped-provider-spike.md`. Our own
   fix (the SPEECHD_SOCK_FD handoff) is commit-lineage d9229a8
   in the a11y snap.

## The upstream ask (minimal and precise)

When speechd is socket-activated (LISTEN_FDS > 0 in the
environment) but the fd claim via sd_listen_fds() returns 0 fds
(identity check failed / fds not passed through), speechd
currently unlinks the activation socket and self-binds WITHOUT
ANY LOG OUTPUT. Ask: log a clear ERROR before the fallback,
e.g.

    ERROR: socket-activation claimed 0 of LISTEN_FDS=%d fds
    (identity check failed — was the fd passed to a different
    process?); falling back to self-binding <path>. Queued
    connections on the activation socket will not be served.

Optionally present a stricter option to maintainers: refuse to
start (exit non-zero) when LISTEN_FDS > 0 but the claim fails,
since serving the activation socket is the unit's whole purpose
— but the LOG-ONLY ask is the minimal non-breaking improvement.

## Tasks

1. UPSTREAM-FIRST: search brailcom/speechd for the
   socket-activation handling (where LISTEN_FDS / sd_listen_fds
   is consumed — the server socket setup path) and for any
   existing error logging or prior discussion of the fallback
   behavior. Record findings.
2. DRAFT THE PATCH: add the ERROR log line (the exact text
   above, adjusted to the real code shape) at the fallback
   point. Keep it log-only (the strict-refusal variant is a
   discussion point, not a unilateral change).
3. A TWO-LINE REPRO for the report: a socket-activated speechd
   unit whose service wraps the server in a supervisor that
   rewrites LISTEN_PID (our T47 design, verbatim) under a
   systemd that also passes LISTEN_PIDFDID -> observe: silent
   self-bind, stranded queued connections, no log line. T50's
   disposable-VM recipe is the harness.
4. SUBMIT to brailcom/speechd (the same channel as the
   speechd-hang-wedge todo
   `20261116-speechd-hang-wedge-upstream.md` — that todo covers
   the hung-server watchdog ask, this one the
   silent-fd-claim-failure logging; file separately or together
   at the owner's preference).
5. VERIFY acceptance; re-visit our supervisor's reliance on the
   fallback if upstream changes the behavior.

## Work log (2026-11-18)

1. UPSTREAM SEARCH. brailcom/speechd master af73916a. The only
   socket-activation code is src/server/speechd.c main(): the
   SPEECHD_SOCK_FD override, then

         #ifdef USE_LIBSYSTEMD
           else if (sd_listen_fds(0) >= 1) { server_socket = SD_LISTEN_FDS_START; }
         #endif
           else if (inet_socket / unix_socket) -> make_*_socket()

   There is no logging in the failure path; the only message is
   the level-4 "Daemon launched via Systemd socket activation"
   on success. Issue/PR search (GitHub API search) for
   LISTEN_FDS, sd_listen_fds, LISTEN_PID, pidfd and "socket
   activation": no prior report of the silent fallback.
   Relevant history: #336/#448/#763 (add activation), #776/#777,
   #809 + #817 (activation looked broken because of
   daemonizing; fixed by #817), #1088 (client race). Upstream
   master as of 2026-11-18 has no diagnostic at the fallback
   point.

2. WHY IT IS SILENT (systemd v259 sd-daemon.c). sd_listen_fds()
   returns 0 in several distinct cases: LISTEN_PID unset,
   LISTEN_PID != getpid(), LISTEN_PIDFDID set and != the pidfd
   inode id of this process, or LISTEN_FDS unset. Malformed
   values and fd_cloexec failures return a negative errno. The
   caller's ">= 1" test therefore collapses "not
   socket-activated" and "activation announced but claim failed"
   into the same fallback. sd_listen_fds(0) does NOT unset the
   environment, so LISTEN_FDS can still be read afterwards to
   tell the two cases apart.

3. PATCH. New branch fix/log-failed-socket-activation from
   origin/master af73916a, in a separate worktree
   ~/git/speechd-sockact (kept apart from the #1141 branch);
   final commit 2a95e519 (+25/-1). Earlier versions b444fb77 and
   9ce8cb41 (+93) were superseded, see item 6.
   src/server/speechd.c, all inside main() before the
   socket-selection if-chain:
   - calls sd_listen_fds(0) once and saves the result (not
     called at all when SPEECHD_SOCK_FD is set, as before);
   - result < 0: MSG(-1) with strerror(-r) and the fallback
     target (the real sd_listen_fds failure, e.g.
     EBADF/EINVAL/ERANGE);
   - result == 0 with LISTEN_FDS set and LISTEN_PID ==
     getpid(): MSG(-1) naming the LISTEN_PIDFDID mismatch (the
     supervisor case), the target and the stranded queued
     connections;
   - an inherited environment whose LISTEN_PID names another
     process is ignored silently, as systemd itself treats it
     (no false error);
   - the fallback and the else-if chain are otherwise unchanged;
     the saved result feeds the existing systemd branch. No
     helper functions.
   An early version added the report as another else-if branch,
   which swallowed the fallback chain entirely (server_socket
   stayed 0 and the server watched stdin); the live repro
   caught it. The final version only computes the claim before
   the chain and does not change the branching.

4. VERIFICATION (host systemd 259.9, private prefix, no VM).
   Built with libsystemd and the dummy output module; systemd
   user transient units used for the real activation path.
   Cases:
   a. Plain start, no LISTEN_FDS: no new message.
   b. REAL T47 SHAPE: transient socket/service whose service
      execs a supervisor that forks speech-dispatcher and sets
      LISTEN_PID to the child's pid, leaving systemd's
      LISTEN_PIDFDID pointing at the supervisor. The claim
      returns 0 -> the new ERROR naming LISTEN_PIDFDID, the
      target and the stranded queue. A client connected before
      activation stayed queued 12 s with no reply; a second
      client got "203 OK RATE SET"; both units stayed active.
      ss showed two listeners on the same path: the orphaned
      systemd one (held via inherited fd 3 by supervisor/
      server/sd_dummy) and the server's self-bound one
      (fd 11).
   c. BEFORE/AFTER: Ubuntu's 0.12.1 and a base af73916a build
      run through the same harness produced ZERO
      socket-activation lines while the stranded client stayed
      queued; the base binary is kept with the harness
      artifacts.
   d. Normal activation with the patched binary as the unit's
      ExecStart: "Daemon launched via Systemd socket
      activation", client served, no error.
   e. T50 SPEECHD_SOCK_FD handoff (fd 3 + bogus LISTEN_PID):
      no error, client served; the explicit override is
      untouched.
   f. Negative returns: LISTEN_FDS=100 with fd 4 closed ->
      -EBADF -> "systemd socket activation failed: Bad file
      descriptor"; LISTEN_PIDFDID=garbage -> -EINVAL -> "...
      failed: Invalid argument".
   g. Stale environment: LISTEN_FDS=1 with LISTEN_PID unset or
      =1 -> no message, server starts and serves (systemd's
      own semantics).
   h. Builds clean with libsystemd and with
      --with-systemduserunitdir=no (USE_LIBSYSTEMD undefined).
   Harness scripts and logs kept in a scratch directory
   (repro/supervisor.py, client.py, stranded.py, fdhandoff.py,
   fakeclaim.py, logs). The early test dirs and one 161 MB
   busy-loop log from an intermediate version were deleted; the
   install tree is scratch to delete with the directory.

5. SUBMITTED. New PR, deliberately not added to #1141:

   <https://github.com/brailcom/speechd/pull/1142>

   "server: report a failed socket activation fd claim", final
   commit 2a95e519, 1 file (+25/-1), base master af73916a; no
   CI checks are configured on the repo (0 check-runs). The PR
   body documents the two diagnoses, the inherited-environment
   behaviour, and the base-vs-patched evidence.

6. INDEPENDENT REVIEWS AND REVISIONS (2026-11-18). Three
   rounds of independent maintainer-style review; each concern
   was checked against systemd v259 sd-daemon.c/parse-util.c.
   a. FIRST REVIEW: "accept with changes". MAJOR negative
      sd_listen_fds returns were reported as an identity
      failure: VALID (fixed, now strerror(-r)); MAJOR a
      stale/inherited LISTEN_* environment produced an ERROR
      claiming stranded connections: VALID (now reported only
      when LISTEN_PID == getpid()); MINOR the LISTEN_FDS parse
      differed from systemd's safe_atoi: VALID in principle
      (numeric parse removed); fallback-target wording:
      addressed; fd 3 leak: pre-existing, documented;
      0.12.1-only evidence: addressed by building base
      af73916a and re-running the harness; style fixed. This
      produced 9ce8cb41 (+93).
   b. SECOND REVIEW of that delta: "accept", with two nits
      (comment accuracy, merge the weak branches); both
      applied.
   c. THIRD REVIEW, specifically on size: +93 is too big for a
      log-only fix; a +16 in-main version was proposed. Adopted
      its structure (no helpers; the claim is computed once)
      but kept the fallback target in the message: the
      existing bind log is MSG(4) and the shipped config sets
      LogLevel 2, so the reviewer's claim that the bind path
      already names the socket is wrong at the default level.
      Dropped the separate stale-env warning per the reviewer
      (ignored silently, as systemd does). Final 2a95e519
      (+25/-1), force-pushed; all tests re-run.

## Status

- [2026-11-18] Todo created. NOT STARTED. Our own deployment is
  already fixed (the SPEECHD_SOCK_FD handoff, T50) — this todo
  is purely the upstream contribution, prompted by the owner's
  ruling: "the only upstream issue would be the silent failure —
  it should log an error."
- [2026-11-18] DONE THROUGH SUBMISSION. Upstream search recorded
  (no prior report of the silent fallback); patch on a NEW
  branch fix/log-failed-socket-activation from master af73916a
  (kept separate from #1141); PR
  https://github.com/brailcom/speechd/pull/1142 open, no CI
  checks. Silent fallback reproduced end-to-end under systemd
  259 with the T47 supervisor shape; Ubuntu's pre-patch 0.12.1
  and a base af73916a build log nothing while the queued client
  is stranded, the patched build logs the new ERROR. Log-only:
  the fallback is unchanged and strict refusal is left to the
  maintainers.
- [2026-11-18] INDEPENDENT REVIEWS + REVISIONS: three rounds of
  independent maintainer-style review. First "accept with
  changes" (negative-return wording, stale-env false positive,
  parse divergence, evidence); the delta was re-reviewed to
  "accept". Third review on size: +93 too big, proposed a +16
  in-main version. Adopted its structure; kept the fallback
  path (the bind log is MSG(4) and the shipped config sets
  LogLevel 2) and dropped the separate stale-env warning.
  Final commit 2a95e519 (+25/-1), PR #1142 force-updated;
  strong, negative, normal, handoff, plain, stale and
  no-libsystemd tests re-run.
  OPEN: upstream acceptance (task 5). If upstream changes the
  fallback semantics, re-check our supervisor's
  SPEECHD_SOCK_FD reliance (T50).
  Scratch trimmed to the repro scripts and logs; the install
  tree was deleted, rebuild it from ~/git/speechd-sockact.
  Delete the scratch dir and the worktree once the PR
  settles.
