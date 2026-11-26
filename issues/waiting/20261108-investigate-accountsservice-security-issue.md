---
upstream: https://gitlab.freedesktop.org/accountsservice/accountsservice/-/merge_requests/191
waiting_since: 2026-11-09
---

# AccountsService SetPassword record injection (upstream security bug)

## Impact / Priority

PRIORITY: Uncertain — potentially High for upstream/distros, but latent
in OUR deployment. The finding is an input-validation flaw in the
upstream accountsservice daemon (the code we stage is the unmodified
resolute archive deb, md5-gated): the SetPassword handler builds
"%s:%s\n" from the caller-supplied username and "crypted" string and
pipes it to `chpasswd -e` with no separator validation. A caller
authorized to call SetPassword can supply a "hash" containing
"\n<otheruser>:$6$..." — chpasswd processes it as TWO records and
changes another account's password too.

What a real user would observe, if exploitable in a given deployment:
on a system whose polkit policy lets a non-admin user change only
THEIR OWN password (a common desktop configuration for
change-own-password), a malicious local user could change ANOTHER
user's password — including root's — i.e. full local account takeover
with no admin credentials. In OUR Ubuntu Core Desktop deployment the
shipped policy requires admin authentication for BOTH
change-own-password and administration paths, so a non-admin caller
cannot reach the vulnerable code; the flaw is latent here, not
exploitable (per the final independent review's security assessment).
No end-user-visible impact exists in our images today.

What is NOT yet established (and what this work must pin down): (a)
whether the vulnerable path exists in the upstream SOURCE or is a
distro patch — current evidence is a disassembly of our staged binary
only; (b) what polkit policies real distros ship (Ubuntu desktop,
Debian, Fedora) for change-own-password — this decides exploitability
in the wild; (c) a working end-to-end reproduction on a vulnerable
configuration. Per this project's methodology, the conclusion must
rest on a real reproduced flow (a real user making the dbus call on a
real system), not on disassembly or synthetic reasoning alone.

## Background

Found during the final independent review of the base-swap project
(2026-11-07/08, an upstream-maintainer-perspective review). The
reviewer disassembled the staged daemon (accountsservice
23.13.9-8ubuntu5.2, resolute) at 0x20a00-0x20ae4: the callback
constructs the record without separator validation and passes it to
chpasswd -e. chpasswd itself does no validation of the crypt string.

Interim mitigation ALREADY IN PLACE (do not re-do): the
accountsservice-snap ships a compiled chpasswd guard (repo
accountsservice-snap, commit 333550c) installed ahead of the real
chpasswd in the daemon's path: only forwards `chpasswd -e`, accepts
exactly ONE record matching `^user:\$6\$salt\$hash$` (rejects embedded
newlines, CR, other formats, oversized input), then execs chpasswd.real
(preserving the 1017-extrausers fallback chain). Verified by direct
testing (valid passes through; multi-record / malformed / CR /
wrong-mode all rejected rc=2) and by the integration gate's decisive
assertion (injected SetPassword payload fails AND root's hash in
extrausers/shadow is unchanged). This makes our deployment safe
regardless of the upstream outcome; drop the guard only when a fixed
upstream release is what we consume.

## Work items

1. SOURCE VERIFICATION: check the upstream accountsservice source
   (freedesktop gitlab / the GitHub mirror) for the SetPassword
   implementation in 23.13.x — confirm the chpasswd -e invocation and
   the unvalidated format-string construction are upstream code, not
   a Debian/Ubuntu patch. Record the exact file/function/commit.
2. REPRODUCTION on a vulnerable configuration: a classic Ubuntu (or
   Debian/Fedora) VM with the distro accountsservice and a polkit
   policy where a non-admin user can call SetPassword for their own
   account; as that real user, make the dbus call with an injected
   second record; observe whether the other account's password
   changes (end-to-end proof, or refutation). Also check what
   policies are actually shipped by default in current distro
   releases — the exploitability map.
3. IF CONFIRMED UPSTREAM:
   a. Security report through the project's security process
      (determine whether accountsservice has a private disclosure
      channel — freedesktop/GNOME infrastructure; otherwise Ubuntu
      security for the distro package). The escalation scenario
      (non-admin local user -> other-user/root password change)
      likely justifies responsible disclosure before any public
      issue. Include: affected versions, preconditions (polkit
      policy), the reproduction, and the proposed fix.
   b. Pull request with the fix: validate the crypted string in the
      daemon before invoking the helper — reject CR/LF and anything
      not matching the expected crypt format (mirror what our guard
      enforces); add tests including the multi-record injection case.
   c. Coordinate with our deployment: track the fix's release; when
      our snap consumes a fixed upstream, remove the guard (note
      already in the snap README).
   [STATUS 2026-11-09 (updated 2): 3a DONE — confidential report
   filed as fdo GitLab issue #149; maintainer Jordan Petridis
   (@alatiera) replied within hours asking for an MR and closed
   #149 — flow moved to the MR. 3b DONE — public MR !191 opened
   from fork chris-bainbridge/accountsservice (branch
   fix/set-password-validation @ ca97c40, after an independent
   pre-MR review):

       https://gitlab.freedesktop.org/accountsservice/accountsservice/-/merge_requests/191

   3c remains open long-term. Deviation from the prescription above:
   the upstream fix is minimal CR/LF rejection ONLY — the full
   guard-format regex was deliberately rejected as over-restrictive
   for upstream (multiple legitimate crypt schemes); rationale in
   the MR description.]
4. IF REFUTED at source level (e.g. it IS a distro patch, or the
   path is unreachable upstream): document why, keep our guard as
   hardening, close this item with the resolution note.

## Notes / gotchas

- Our evidence chain: reviewer disassembly -> direct guard testing ->
  integration-gate root-hash-unchanged assertion. The upstream claim
  is the one leg without source-level proof yet — do that first.
- The same class of bug (unvalidated caller string reaching a
  line-oriented helper) is worth grepping the daemon for in the same
  pass: any other Set* path that shells out with interpolated user
  input (SetRealName etc. go through usermod args — check those for
  their own injection classes while in the source).
- Repo state: accountsservice-snap main @ 333550c (guard); the
  upstream source check should use a fresh clone or the upstream
  repo, not our staging repo.

## Progress log (2026-11-09)

Durable findings from each phase get folded back into this file.

[2026-11-09 session start] Plan approved: break into investigation
tasks.
Phase 1 (4 parallel investigation tasks):
  T1 evidence brief — precise claims from the final review + snap
  README
  T2 source verification — upstream vs distro patch (work item 1)
  T3 polkit survey — distro default policies / exploitability map
  (part of work item 2)
  T4 env recon — VM tooling for the reproduction (prep for work item
  2)
Phase 2: independent verification of T2's claims, audit of other
  Set*/helper injection paths (notes item), reproduction build-out.
Phase 3 (only if confirmed upstream): security report draft + fix PR
  draft; NOTHING gets sent/published without owner approval
  (responsible disclosure).

[Phase 1 complete — all four tasks done]
T1 evidence brief:
- The final review contains only PROSE (no disassembly addresses, no
  version strings); the 0x20a00-0x20ae4 address exists only in this
  file's own text. No raw disassembly artifact was preserved.
- accountsservice-snap HEAD has moved to 3e45003; the guard was
  broadened in 05974aa (accepts any $<id>$ crypt scheme, not only
  $6$) — the regex quoted in "Interim mitigation" above is STALE.
- Integration gate decisive assertion (8c): root /etc/shadow hash
  unchanged after injected SetPassword AND testuser extrausers hash
  unchanged. ("extrausers/shadow" phrasing above was imprecise.)
- Gate docs lived only in session scratch; they have since been
  re-persisted with the other durable artifacts.

T2 source verification — VERDICT: UPSTREAM
- Tag 23.13.9: src/user.c user_set_password() (dbus handler, ~L2548)
  builds "%s:%s\n" from username + crypted (L2564-2566, no
  validation); user_change_password_authorized_cb() (~L2498) spawns
  /usr/sbin/chpasswd -e (argv at L2508) with the record on stdin.
  Only g_regex use in the whole tree is locale parsing. [Spot-check:
  grep of the checked-out tag confirms both lines.]
- Introduced by commit 4fde420a7b25d1a54bdb4e4ade67770a5ac79d02
  (Simon McVittie, 2023-02-03, "user: Replace usermod -p with
  chpasswd -e" — that commit was itself the fix for CVE-2012-6655 /
  Debian #757912, i.e. an old fix that introduced this new surface).
  First released in 23.11.69. Still present on origin/main (a
  systemd-homed guard was added later; no validation was).
- Ubuntu resolute 23.13.9-8ubuntu5.2: orig.tar src/user.c
  byte-identical to upstream tag; all 35 debian/patches applied,
  none touch SetPassword/chpasswd. Debian salsa series likewise
  clean. => WORK ITEM 1 ANSWERED (pending independent re-verify, T5).

T3 polkit survey — exploitability map:
- org.freedesktop.accounts.change-own-password defaults =
  auth_admin/auth_admin/auth_admin on Ubuntu 26.04 (23.13.9-8ubuntu5),
  Ubuntu 26.10 (26.27.3-0ubuntu1), Debian 13 (23.13.9-7), Fedora 45
  (26.27.3-2.fc45) — verified from shipped debs/rpm, not web pages.
- auth_admin has been the upstream default since 0.6.55 (2019); no
  distro patches it. => On DEFAULT installs of every surveyed distro
  a non-admin CANNOT reach SetPassword. The Impact section's "common
  desktop configuration" premise is NOT any surveyed default; the bug
  is exploitable only where an admin relaxed change-own-password
  (or via a compromised admin-equivalent, which adds nothing).
  Real-world severity: defense-in-depth / policy-dependent, not
  default-exploitable.
- GNOME Settings changes the user's own password via /usr/bin/passwd
  directly (not accountsservice); KDE's users KCM does route through
  accountsservice SetPassword on all three distros.

T4 env recon:
- qemu-system-x86_64 10.2.1 + KVM verified working unprivileged
  (no sudo on host). Recommended: Ubuntu cloud image + genisoimage
  NoCloud seed + slirp hostfwd ssh + serial socket; ~10 min setup,
  ~4-6 GB disk (put it somewhere disk-backed; a RAM-backed tmpfs
  quota caused ENOSPC during the first attempt).
- Critical gotcha: polkit allow_active needs the dbus call from an
  Active logind session — tty1 autologin with default VGA kept
  (-display none, NOT -vga none); ssh sessions are Active=no.

[Phase 2 dispatched] T5 independent re-verification of T2/T3 claims
from primary sources; T6 end-to-end reproduction on an Ubuntu VM
(default-policy denial as negative control, then relaxed
change-own-password = vulnerable config, injection into victim + root
accounts, before/after shadow hashes + functional su proofs); T7 audit
of other Set*/helper injection classes in the upstream source.

[Impact model clarified — owner Q&A 2026-11-09]
"Admin" = polkit admin identity from shipped polkitd 50-default.rules:
unix-group:sudo (Ubuntu 26.04/26.10, Debian 13), unix-group:wheel
(Fedora 45). On DEFAULT installs:
- Non-admin: cannot reach SetPassword (auth_admin gate; proven by T6
  phase-1 denial). Not exploitable.
- Admin (sudo/wheel): CAN reach and fire the injection, but gains
  nothing — already root-equivalent (sudo passwd root). NO privilege
  boundary crossed. Bug effectively inert on defaults.
Where it matters:
1. Relaxed-policy deployments (change-own-password = yes/auth_self):
   non-admin local user -> root takeover; proven end-to-end by T6
   (unprivileged testuser changed root's shadow hash in an Active
   session). Core disclosure scenario.
2. Admin-approval scenario on defaults: non-admin initiates the call
   with injected payload; admin authenticates the polkit prompt
   ("change own password") believing it benign; the injected root
   change rides in the same authorized call. Payload travels in the
   dbus message pre-auth, executes post-auth. Narrow (needs admin to
   type credentials at the attacker's prompt) but real; include in
   report.
KDE note: the vuln is in the daemon, not KDE's UI — any raw dbus
caller reaches it. KDE KCM relevance: proves own-password-change via
accountsservice is an intended user flow (so relaxed policies are
plausible); on defaults, KDE users get an admin prompt for own
password changes — UX pressure that encourages exactly the relaxation
that makes scenario 1 exploitable. (Verify KDE KCM own-account source
claim directly when drafting the report; T3 cites plasma-workspace
kcms/users/src/user.cpp ~L300.)

[Phase 2 complete — all three tasks returned]
T5 verification: claims C1-C7 ALL CONFIRMED by independent
re-derivation (clone integrity checked against remote; tag file
sha256-matched an independent HTTPS raw fetch; orig tar + debian.tar +
salsa + Ubuntu deb re-downloaded fresh). Only discrepancy: cosmetic —
T3 cited resolute pkg -8ubuntu5; the archive now carries -8ubuntu5.2
(policy byte-identical, md5 matches T3's). Note: salsa's resolute
branch lags the Ubuntu archive — archive.ubuntu.com is authoritative
for Ubuntu source. => Work item 1 fully answered and double-verified:
UPSTREAM.

T6 reproduction (consolidated RESULTS + runbook):
- Guest: Ubuntu 26.04.1 LTS (resolute) server cloud image; distro
  accountsservice 23.13.9-8ubuntu5.2 (EXACT match to our staged deb);
  qemu 10.2.1 KVM/q35; tty1 autologin = logind Active=yes session.
- Phase 1 default-policy negative control: SetPassword as testuser
  DENIED ("Authentication is required"); shadow unchanged. Correct.
- Phase 2a (policy relaxed to allow_active=yes — the vulnerable
  config): own-password SetPassword succeeded; testuser shadow hash
  == expected openssl-computed hash, exact.
- Phase 2b victim injection: CONFIRMED — victim's shadow hash ==
  injected vsal hash.
- Phase 2c root injection: CONFIRMED — root's /etc/shadow hash ==
  injected rsal hash (PwnedRoot1!), set by unprivileged testuser via
  one change-own-password-authorized dbus call from an Active tty
  session. Daemon journal captured showing the multiline payload.
=> Work item 2 answered: real reproduced flow per methodology
  (default-policy denial + vulnerable-config exploitation), on the
  exact distro package version we stage.
- The repro VM was kept running so T8 could independently verify
  against it; the reproduction is rebuildable from the runbook in
  ~10 min.
- Gotcha recorded: dbus object path is
  /org/freedesktop/Accounts/User<UID> — NO slash before the UID (two
  early attempts failed on that; logs kept).
- Honest infrastructure-failure log kept (group name collision with
  pre-existing 'admin' group, cloud-init write_files ordering,
  getty enable deadlock, one double-boot mistake → disk rebuilt).

T7 other-paths audit:
- SetPassword -> chpasswd is the ONLY stdin-to-helper path in the
  daemon (sole STDIN_PIPE usage in tree; unchanged on origin/main).
- All usermod/useradd/userdel/passwd/chage argv paths SAFE: caller
  values land in option-value positions (cannot be misparsed as
  options), shadow-side validation rejects ':', '\n', leading '-';
  no shell (system/popen) anywhere in the Set* paths.
- GKeyFile writes (/var/lib/AccountsService/users/*) escape \n \r \
  — no group/key forging; SetLanguage(s) locale-regex validated.
- Minor warts: SetIconFile spawns /bin/cat <file> without '--'
  (argv misparse, LOW impact — child runs as caller uid; already
  replaced by memfd read on origin/main); caller's /proc cmdline
  echoed to syslog (log forging, informational only).
- origin/main delta: no new Set* methods, no new helper binaries,
  no new stdin pipes since 23.13.9.
=> The "grep for same bug class" item answered: no other
  high-severity injection class exists in the daemon.

[Phase 2b dispatched] T8: independent verification of T6 — artifact
review + fresh-salt LIVE re-run via the running VM + spot-checks of
T7's key claims. (Verification of T5 already double-covered T2/T3.)

[Phase 2b complete — T8 verification: REPRODUCTION INDEPENDENTLY
CONFIRMED, all items PASS]
- Evidence review V1-V6: live dpkg version matches (23.13.9-8ubuntu5.2
  on 26.04.1 resolute); live policy diff byte-identical to T6's
  saved diff; phase-1 denial logged; T8 host-recomputed own2/own3/
  vsal/rsal hashes EXACT-match live /etc/shadow; fresh journalctl
  pull matches T6's excerpt; session Active=yes in every phase log;
  timeline mutually consistent (no fabrication signs).
- LIVE RE-RUN R1-R4 (decisive): T8 wrote its own phase script with
  FRESH salts (t8own/t8root/t8aux), restarted getty@tty1, and one
  SetPassword call from the Active session with a 3-record payload
  changed root AND victim hashes to T8-chosen values — all three
  shadow hashes exact-match T8's independent openssl computations.
  T6's result fully reproduced.
- T7 spot-checks S1-S3 PASS (chpasswd is the sole STDIN_PIPE; comma
  check exists at src/user.c:1228-1231; no system()/popen()).
- Minor notes: exploitation requires the documented policy relaxation
  (stock policy blocks — that is the point of the negative control);
  VM evidence state now holds t8* hashes (T6 logs untouched).
=> Work items 1 and 2 CLOSED (verified). Same-class grep item CLOSED.

[Phase 3 dispatched — DRAFTS ONLY, nothing sent/published]
T9: security report draft + private-disclosure-channel research
(upstream fdo GitLab / GNOME infra / Ubuntu Security fallback).
T10: candidate upstream fix (validate crypted before chpasswd; reject
CR/LF; tests incl. multi-record injection case) built on a scratch
clone; PR description draft with public-safe variant. Submission of
anything remains the owner's explicit decision.

[Phase 3 complete — 2026-11-09. Drafts QA'd, corrected, READY. NOTHING
SENT. Pausing at the owner-decision point.]
- T9 report draft: body + cover note + SUBMISSION OPTIONS. Primary
  channel: CONFIDENTIAL issue on fdo GitLab (tick "This issue is
  confidential"; new accounts need admin approval — create the
  account early if going this route). Fallbacks: Ubuntu Security
  (private Launchpad bug / security@ubuntu.com — established route
  for this package: CVE-2020-16126/27, -2021-3939, -2023-3297) and
  Debian team@security.debian.org. GNOME-security route demoted:
  currently unreliable (30-day policy since 2026-08-01; tracker
  stopped accepting new reports 2026-10-01, no successor).
- T10 fix: reject '\n'/'\r' in user_set_password() BEFORE polkit auth
  (placement verified: validation precedes action-id selection +
  daemon_local_check_auth()); dbusmock test; built and run (29 OK / 5
  known env failures = pristine-main baseline).
- Adversarial QA caught: CRITICAL test-would-fail-in-upstream-CI
  (suite runs as uid 5555; mock allowed only change-own-password;
  demonstrated empirically); MAJOR stale scratch build dir; MAJOR
  stale GNOME-security claim. Fixed all three: test now allows
  both polkit actions (caller-uid-agnostic — old test fails the
  flipped-uid CI scenario, new passes); error text "must not contain
  line breaks"; single amended commit 2666bd7 (author+committer =
  REPORTER_NAME placeholder); rebuilt + suite re-run; origin/main
  still 88e3de5; fix.patch clean onto pristine main.
- Review corrections folded in: PR variant (a) end-to-end overclaim
  (patched-daemon testing) reworded to what was actually
  verified (unpatched daemon exploitation + our snap chpasswd guard
  via the same methodology); nonexistent make_crypted() reference
  removed from the report; maintainer emails confirmed against
  accountsservice.doap (Matthias Clasen, Ray Strode).
- Durable artifacts: the investigation reports (01-06, 08-12) +
  policy evidence + the fix.patch/PR-description pair + the repro
  results/runbook/logs, all kept alongside the base-swap evidence.
- OPEN (owner): decide channel + reporter identity (fill
  REPORTER_NAME in report, cover note, and patch author via
  git rebase --reset-author); decide attachments (runbook/logs) vs
  on-request; fix PR only AFTER report acknowledged. 3c
  guard-removal tracking stays open long-term.
  Also noted: "Interim mitigation" section's $6$-only regex is stale
  vs accountsservice-snap HEAD 3e45003 (guard broadened in 05974aa —
  see T1 brief).

[Owner decisions, 2026-11-09: HOLD — no submission for now; drafts
parked as durable artifacts, this item stays OPEN at the owner-
decision point. To resume: pick the channel (recommendation +
mechanics in the report draft's SUBMISSION OPTIONS), fill
REPORTER_NAME in report + cover note + patch author, then submit;
create the fdo GitLab account EARLY if going that route (approval
lag). Fix PR follows only after the report is acknowledged.]

[Independent maintainer review — 2026-11-09, owner-requested: a
reviewer acting as an independent accountsservice maintainer.]
- VERDICT: YES — confidential upstream security reporting is
  warranted. Core reasoning: "The daemon authorizes the targeted
  account, then sends attacker-controlled LF-delimited records to a
  privileged helper that independently processes additional account
  names. Enabling own-password changes is not equivalent to granting
  arbitrary account administration." As maintainer: would acknowledge
  privately, merge + backport a focused fix, support a CVE with
  explicitly policy-dependent severity. Explicitly NOT an
  unauthenticated stock-distro local-root; no emergency updates
  warranted on current evidence.
- Reviewer's independent checks: found NO bypass of the proposed LF
  check; no allocation/integer-overflow/overlap/aliasing/lifetime
  defects in the fix; D-Bus string constraints confirm the check's
  completeness; hint never reaches helper stdin; homed targets
  rejected on main; recomputed the live VM's shadow hashes and
  inspected the VM read-only — agrees with the reproduction.
- Findings: F1 MAJOR — the survey conflated shipped action defaults
  with effective per-install policy, and missed Ubuntu's
  49-ubuntu-admin rules (admin identities = unix-group:sudo AND
  legacy admin group; verified first-hand on the live VM). F2-F8
  MINOR: negative-control wording (benign call, not identical call);
  journal multiline output is /proc/<pid>/cmdline reflection, not a
  trace of helper stdin; CR does not terminate records in shadow
  4.17.4 (fgets, LF-delimited) — CR rejection is hardening; the
  report's regex suggestion over-restrictive (legacy encodings,
  special password states); automated test proved less than
  documented; username-side NSS trust needs qualifying; two
  ancillary audit conclusions (locale-regex trailing-LF, SetIconFile
  cat misparse) overstated.
- ALL corrections applied and spot-checked: report Preconditions
  reworked to a 3-way scope (shipped defaults / tested effective
  policy / unexamined spins+overrides), Ubuntu admin identities
  corrected, controls + journal + admin-approval wording fixed
  (approval scenario now marked reasoned-not-tested, not a
  stock-policy bypass), allow-list recommendation removed, full main
  SHA pinned (88e3de5283c831789835e52851d58ba57a58eeca), patch
  code-comment fixed (LF = terminator, CR = hardening), test
  restructured: deny-all-polkit + 5 injection variants
  (embedded/leading/trailing LF, CR, CRLF) prove pre-auth rejection
  empirically; benign leg both-actions-allowed; suite 29 OK / 5
  known env failures; new fix.patch (commit 3fec3ee) clean onto
  pristine main; author+committer still REPORTER_NAME placeholder.
  The audit report received a corrections addendum (originals
  retained). NOTE-TO-OWNER strengthened: ANY patch submission
  discloses the issue (the patch text itself explains
  arbitrary-account injection; the test includes a root-record case)
  — a "public-safe" PR variant is NOT confidentiality protection;
  private-first means offering the patch via the confidential
  channel.
- Reviewer's guidance for the owner: report privately and fix;
  further dangerous VM experiments unnecessary before initial
  reporting; deployment-policy coverage and patched-daemon end-to-
  end testing can inform later severity/release decisions.
- STATUS UNCHANGED: HOLD (owner decision 2026-11-09 stands). The
  drafts now carry the independent review's corrections and are
  ready for the send/no-send decision.

[2026-11-09, submission prep] Authenticated to fdo GitLab as
chris-bainbridge. Route decision: fdo GitLab CONFIDENTIAL issue
(Launchpad-first rejected: account-approval argument moot, bug is
upstream-pristine; CVE question answered — assignment is
venue-independent: maintainers/Red Hat CNA, Canonical CNA for the
Ubuntu package, MITRE fallback; independent reviewer supports CVE
with policy-dependent severity). REVIEW PACKAGE assembled for owner
sign-off — NOTHING POSTED: issue-title + issue-body (intro + report
body extracted verbatim from the draft with REPORTER_NAME ->
"Chris Bainbridge", owner to confirm form), attachments (RESULTS +
all phase logs incl. independent t8 re-run + policy diff/orig +
shadow before/after + journal + fix.patch), manifest (file-by-file
guide + open review items). fix.patch still had placeholder author
— needed the owner's commit email before posting. Runbook
deliberately NOT attached (report says available on request).
Awaiting owner review + explicit go.

[2026-11-09, owner review round 1 APPLIED]
- Intro rewritten per owner verbatim (straight technical summary, no
  greeting/confidential header line — confidential flag is on the
  issue itself); issue body rebuilt, 0 placeholders.
- Identity set: Chris Bainbridge <chris.bainbridge@canonical.com>.
  fix.patch re-authored (new commit 384fec9, author+committer set,
  content unchanged 2 files/80 insertions); PR-description identity
  refs updated to match.
- RESULTS.md submission copy sanitized for upstream (archival copy
  unchanged — full record kept): removed the live-VM section
  (ssh/PID/sockets/host paths), the infrastructure-failures section,
  hypervisor/seed env rows, internal T2/T6 references, results-vm
  path prefixes, host-side phrasing. ALSO fixed an inaccurate caveat
  (old text: relaxed policy "matches the standard desktop-default
  experience" — contradicted our own survey; now: relaxed policy =
  defined vulnerable config, stock auth_admin blocks non-admins,
  only change made to shipped policy).
- Leakage grep over attachments: clean except authentic /var/tmp
  path in policy-change.diff header (harmless raw diff) and "T8"
  naming in t8-phase.log header (internal naming, kept as raw
  evidence).
- OPEN (owner): drop-or-keep the two failed-attempt logs
  (phase1-race-firstboot/wrongpath — now unexplained after
  sanitization; recommended dropping). Then awaiting final go.

[2026-11-09, owner review round 2 APPLIED — FOCUSED PACKAGE]
- Owner decision: drop failed-attempt logs AND trim the attachment
  set to a focused bug report ("they should be able to reproduce
  this by reading the main body"). Final attachments: RESULTS.md
  (consolidated evidence: exact commands, per-test outcomes, policy
  diff inline, before/after hash table) + fix.patch. All other
  artifacts (phase logs, t8 re-run log, standalone policy diff +
  orig, shadow snapshots, journal excerpt) dropped from the package
  — archived and offered "on request".
- Consistency edits: report body Reproduction header + decisive-
  evidence sentence + cover-note phrase; owner intro sentence
  ("a consolidated reproduction-results file is attached");
  RESULTS.md log/file references -> "available on request".
  Issue body rebuilt; 0 placeholders.
- Package state: issue title, issue body, intro, manifest,
  attachments/{RESULTS.md, fix.patch}. Awaiting owner FINAL GO.

[2026-11-09 — REPORT FILED. UPSTREAM CONFIDENTIAL ISSUE #149]

    https://gitlab.freedesktop.org/accountsservice/accountsservice/-/work_items/149

  (classic form /-/issues/149 redirects)
- Filed via GitLab API as chris-bainbridge; confidential=true
  verified with a fresh GET after creation; state opened; author
  chris-bainbridge; description 13,110 chars (owner intro + full
  report body + "Attached evidence" section), spot-checks OK
  (credit line, pinned main SHA, object-path note, both links).
- Two uploads linked in the issue: RESULTS.md + fix.patch (authored
  Chris Bainbridge <chris.bainbridge@canonical.com>).
- Nothing public: no MR, no public issue, no distro emails sent.
- NEXT STEPS (owner): watch for maintainer response (Ray Strode /
  Matthias Clasen). After acknowledgement: loop in Ubuntu Security
  (private Launchpad security bug or security@ubuntu.com — note the
  upstream issue is being coordinated) and Debian
  team@security.debian.org; offer fix + repro. Public fix MR only
  after upstream coordinates disclosure (they already hold fix.patch
  privately). CVE assignment is venue-independent: maintainers can
  route via Red Hat CNA; Canonical can assign for the Ubuntu package.
- Remaining long-term: work item 3c — remove the snap's chpasswd
  guard only when our snap consumes a fixed upstream release.

[2026-11-09 — MAINTAINER RESPONSE + MR !191 OPENED]
- Jordan Petridis (@alatiera) replied on #149 within hours asking
  for a merge request, then closed the issue — the MR is now the
  sole channel (the MR description references #149, so GitLab
  cross-links it back automatically; no manual comment needed).
- Pre-MR review (owner-requested): an independent maintainer-
  perspective review — verdict MERGE-READY-WITH-NITS, ZERO
  CRITICAL/MAJOR findings; confirmed the check's placement and
  completeness ("No LF can reach the single record on chpasswd's
  stdin"), D-Bus string constraints, all five prior fixes present
  in the commit, and the MR description accurate.
- Disposition of the pre-MR-review findings: APPLIED the
  commit-message scoping NIT ("record injection" -> "record
  injection through SetPassword"). DECLINED the test MINOR (the
  suggested assertNotIn('line breaks') already exists in the test —
  the change would only weaken the assertIn('chpasswd') proof; the
  real-chpasswd side effect requires running the suite as root
  locally with a resolvable 'rupert', which upstream CI doesn't do
  — uid 5555 per .gitlab-ci.yml) and the strpbrk NIT (g_utf8_strchr
  matches the file's SetRealName validation precedent).
- Commit amended 384fec9 -> ca97c40 (message-only change; author +
  committer Chris Bainbridge <chris.bainbridge@canonical.com>;
  content unchanged, 2 files / 80 insertions). fix.patch
  regenerated. NOTE: the patch uploaded to #149 remains 384fec9
  (as-filed record); the MR carries ca97c40.
- Fork created: chris-bainbridge/accountsservice (project 28904,
  import finished); branch fix/set-password-validation pushed.
- Gotcha hit + resolved: POSTing the MR to the TARGET project (838)
  returns 403 for external contributors — the correct fork flow is
  POST to the FORK project with target_project_id=838.
- MR !191 OPENED + verified:

    https://gitlab.freedesktop.org/accountsservice/accountsservice/-/merge_requests/191

  (state opened, sha ca97c40, author chris-bainbridge, source
  28904:fix/set-password-validation -> 838:main, remove_source_branch
  set; description = variant (a) + confidential-issue reference;
  content spot-checks OK — two initial "missing" flags were check-
  phrase artifacts: stale pre-review wording memory and markdown
  ** bolding around "Tests:").
- NEXT (owner): watch !191 for maintainer feedback and respond;
  after merge, loop Ubuntu Security + Debian for the distro side
  (or earlier if preferred — nothing public beyond the fix itself
  is out); CVE via maintainers/Red Hat CNA or Canonical (venue-
  independent); then 3c once our snap consumes a fixed upstream.

[2026-11-11 — MAINTAINER REVIEW ON !191; REVISION PUSHED]
- Adrian Vovk (AdrianVovk) reviewed !191: "requested changes" with
  6 comments — all style/test-design, none disputing the fix:
  (1) no essay in the commit message, just refer to the issue;
  (2) use a single strpbrk call; (3) minimize the code comment;
  (4-5) strip the test's comments and docstring; (6) rework the
  valid-input leg — assert the call REACHES the polkit check
  (PermissionDenied under deny-all mock) instead of relying on a
  real chpasswd failure.
- Revision prepared locally and approved by owner (approval gate:
  all changes + messages pre-approved; owner chose "Approve all").
- New commit caef2ce (was ca97c40): single strpbrk + Adrian's
  one-line comment + <string.h> include (user.c lacked it — util.h
  only pulls glib); test docstring/comments stripped, second
  SetAllowed removed, valid leg asserts PermissionDenied; commit
  message 5 lines + "Fixes: #149". Commit shrank 80 -> 41 inserted
  lines. Rebuilt + suite re-run: 29 OK / 5 FAIL = same 5 known env
  failures; new test PASSES.
- Pushed (force) to fork; MR description REPLACED with trimmed
  version (1766 chars — old one had a stale test paragraph; the
  detail now lives in confidential #149); reply comment posted
  (note id 3775135) summarizing the four changes.
- All three verified via API: MR opened @ caef2ce, description
  updated, note by chris-bainbridge present.
- The pre-MR-review disposition is now superseded where it conflicts
  with the maintainer's preferences (strpbrk NIT now adopted; test's
  real-chpasswd leg replaced per Adrian; commit-message essay
  dropped). fix.patch regenerated for caef2ce.
- NEXT: await re-review/merge on !191; then distro loop (Ubuntu
  Security + Debian), CVE routing, and 3c (snap guard removal) once
  we consume a fixed upstream.

[2026-11-11 — MAINTAINER FOLLOW-UP ON !191: coverage question]
- Q (Jordan, @alatiera): why does the new code block get no coverage
  despite the test running in CI?
- ROOT CAUSE (investigated + proven empirically with a -Db_coverage
  build): stop_daemon() killed the daemon with SIGKILL
  (tests/test-daemon.py:227); gcov only writes .gcda on clean exit,
  so the daemon's coverage data was discarded — ALL daemon-only code
  (src/user.c etc.) showed 0% while lib code got coverage (it runs
  in-process inside Python, which exits cleanly). Daemon itself is
  innocent: handles SIGTERM cleanly (main.c:278 g_unix_signal_add).
  Baseline run: suite green (29 OK / 6 FAIL = 5 known env +
  check-format/no-uncrustify env), and NO accounts-daemon.p/*.gcda
  existed.
- FIX (verified): stop_daemon() now terminate() -> wait(1) ->
  kill fallback, mirroring the existing stop_server() house pattern.
  Re-run: user.c.gcda now present; gcov shows strpbrk check executed
  6x (5 injected rejections + 1 valid fall-through). Suite results
  unchanged.
- Owner approved (approval gate held: change + message presented
  first). Pushed as SECOND commit dba8807 "tests: Stop the daemon
  gracefully so gcov data is flushed" (kept separate from the fix
  commit; fast-forward push, committer identity = Chris Bainbridge).
- Reply posted (note 3777394) explaining cause + fix.
- MR !191 state: opened, head dba8807, two commits (caef2ce fix +
  dba8807 coverage). fix.patch regenerated (both commits).
- NEXT: await merge; then distro loop (Ubuntu Security + Debian),
  CVE routing, 3c after fixed upstream lands.
