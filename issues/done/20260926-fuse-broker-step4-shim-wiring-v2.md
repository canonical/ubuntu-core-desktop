# Wire the fusermount3 shim into xdg-document-portal (Step 4 redo)

## Impact / Priority

The original Step 4 wiring was blocked: it said to revert the AppArmor
mount-rule patch with no replacement, which left the portal's AppArmor
profile with ZERO mount rules for the doc path. AppArmor's mount
mediation is default-deny, so mount(2) failed with EACCES — and libfuse
only invokes the fusermount3 fallback (the shim) on EPERM, so the shim
was never spawned and the portal stayed broken. This redo fixes the
design: the scoped mount ALLOW rule is kept inside the new
`fuse-device` interface (no capability sys_admin). Impact derived from
the original note's described symptoms.

## Context

Supersedes Step 4, 4(a)-4(d) of the master fusermount-broker plan (that
plan's Steps 1-3 are DONE and unaffected; its Step 5/6 still apply
after this file's steps all pass — see "Handoff" at the bottom).

The blocker analysis this file is based on is summarized in section 0
below — the errno findings there were the entire reason this redo
exists.

## 0. One-line status / blocker confirmation

CONFIRMED BLOCKER: the original Step 4(b) said "revert the AppArmor
mount-rule patch in fuse_support.go" with no replacement. That leaves
the portal's AppArmor profile with ZERO mount rules for the doc path.
AppArmor's mount mediation is default-deny, so mount(2) then fails with
EACCES, not EPERM. libfuse's fuse_mount_sys() (mount.c:505-600) only
invokes the fusermount3 fallback (the shim) on EPERM; on any other
errno (including EACCES) it logs "fuse: mount failed" and gives up.
Empirically confirmed on the VM across 5 profile variants: only a
profile WITH a scoped mount ALLOW rule (and no capability sys_admin)
produces EPERM and reaches the shim.

=> Fix: the doc-path mount ALLOW rule must be KEPT (not deleted), just
re-homed into the new minimal `fuse-device` interface instead of
`fuse-support`, alongside the udev + /dev/fuse + broker-socket rules.
`capability sys_admin` and the broad `/dev/fuse rw,`-only grant are
what get removed — not the mount rule itself.

Design decision this implies (was an open question): the
doc-mount-allow rule lives IN the new `fuse-device` interface, not in a
resurrected fuse_support.go. This makes fuse-device a single
self-contained grant: udev tag + /dev/fuse rw, + broker socket rw, +
scoped mount allow, with NO capability sys_admin and NO broad mount
access. Step 4.1 below re-confirms this with the user before any code
is written.

## 1. Step-sizing principle for this file

Every step below is scoped to ONE repo (or VM-only actions) and ONE
concern, with an explicit, mechanically-checkable verification block.
Do not proceed past a step's verification block if it fails — stop and
report back instead of improvising a workaround, since several of these
steps encode a security boundary (no accidental capability sys_admin
grant).

### Step 4.1: Re-confirm the design decision

Not a delegated step — do this directly and synchronously before
anything below.

Ask: "Confirmed based on the EPERM/EACCES finding: the doc-mount-allow
AppArmor rule will live inside the new `fuse-device` interface (not a
revived fuse_support.go), scoped to
/run/user/[0-9]*/snap.@{SNAP_INSTANCE_NAME}/doc/{,**} with
options=(rw,nosuid,nodev), fstype=fuse.*, and WITHOUT capability
sys_admin. Proceed on this basis?"

If the user wants a different placement (e.g. keep it in a separate
"fuse-doc-mount" interface, or gate it some other way), STOP and redo
Step 4.2's file plan before continuing — do not silently pick a
different design.

Verification: explicit user go-ahead captured (commit message or an
equivalent written record), or documented reason if the design changed.

### Step 4.2: Implement the new builtin snapd interface `fuse-device`

Note: single repo, security-sensitive; needs to mirror existing
interface conventions exactly.

Repo: ubuntu-core-desktop-snapd (branch 26-dev). Preconditions: Step 4.1
done.

What to create:

- interfaces/builtin/fuse_device.go, modeled on
  interfaces/builtin/fuse_support.go, but containing ONLY:

  - registerIface() call in init()
  - commonInterface embed, name "fuse-device"
  - base declaration: deny-auto-connection: true, slot on core only
    (implicitOnCore true)
  - connectedPlugUDev: []string{`KERNEL=="fuse"`}
  - connectedPlugAppArmor containing exactly:

        /dev/fuse rw,
        /run/xdg-fuse-broker.sock rw,
        mount fstype=fuse.* options=(rw,nosuid,nodev) ** -> /run/user/[0-9]*/snap.@{SNAP_INSTANCE_NAME}/doc/,
        mount fstype=fuse.* options=(rw,nosuid,nodev) ** -> /run/user/[0-9]*/snap.@{SNAP_INSTANCE_NAME}/doc/**,

  - Explicitly NO `capability sys_admin,` line. NO other mount rules
    (do not copy the /var/snap/... rules from fuse_support.go).
  - connectedPlugSecComp: only what's needed for the shim's own
    syscalls if any extra beyond the default template is required
    (check fuse_support.go's secomp addition of `mount` — the CONFINED
    process itself does not call mount(2) directly in this design since
    the broker does it, but AppArmor still mediates the mount() call
    the KERNEL makes on the confined process's behalf via mount(2)
    inside its mount namespace — only add secomp `mount`/`umount2` if a
    real EPERM-then-shim run in Step 4.7 shows a seccomp kill instead;
    do not add speculatively).

- interfaces/builtin/fuse_device_test.go, modeled on
  fuse_support_test.go: gocheck Suite, MockConnectedPlug/Slot,
  TestAppArmorSpec (assert both mount lines AND the socket rule AND NO
  "capability sys_admin" substring present), TestUDevSpec,
  TestStaticInfo, TestAutoConnect (should be false / requires gadget
  connection since deny-auto-connection: true), TestInterfaces.

Verification (must all pass before Step 4.3):

- `go build ./...` succeeds in ubuntu-core-desktop-snapd.
- `go test ./interfaces/builtin/... -check.f FuseDevice` passes with 0
  failures.
- `grep -n "capability sys_admin" interfaces/builtin/fuse_device.go`
  returns NOTHING (empty output). If it returns a match, the step has
  failed — do not proceed.
- `grep -c "mount fstype=fuse" interfaces/builtin/fuse_device.go`
  returns exactly 2.
- `./run-checks` (or the project's documented lint/test entrypoint) is
  clean for the new files specifically (gofmt, vet).

### Step 4.3: Add the snapcraft layout wiring the shim to /usr/bin/fusermount3

Note: snapcraft layout semantics need care.

Repo: ubuntu-desktop-session-snap (branch 26-dev). Preconditions: none
(independent of 4.2; can run in parallel with it).

What to change:

- snap/snapcraft.yaml: add a top-level `layout:` stanza (there is
  currently NO `layout:` key in the file — confirm this is still true
  before editing, in case another change landed first) that bind mounts
  the fusermount3-shim part's installed binary
  (/usr/libexec/ubuntu-desktop-session/fusermount3, built by the
  existing fusermount3-shim part, KEEP that part as-is) to
  /usr/bin/fusermount3.
- IMPORTANT constraint: snapcraft `layout:` bind-mounts are GLOBAL to
  the snap's mount namespace, not scoped per-app. Since
  /usr/bin/fusermount3 in the base snap (core26-desktop) is only
  meaningfully used by xdg-document-portal in THIS snap (confirm via
  `grep -rl fusermount3 snap/` and a check of what other apps/parts in
  this snap's snapcraft.yaml might shell out to `fusermount3`/
  `fusermount` — if literally none do, the global redirect is safe; if
  any other app does, flag this before proceeding, do not silently
  redirect a binary another app relies on).

Verification (must all pass before Step 4.4):

- `grep -rn "fusermount" snap/snapcraft.yaml` shows the shim part
  (unchanged), the new layout entry, and nothing else references
  fusermount3 in a way the layout would break.
- `snapcraft expand-extensions` (or equivalent snapcraft.yaml validation
  the project already uses — check for a documented lint step before
  inventing one) succeeds with no YAML/schema errors.
- Manual diff review: the layout stanza touches ONLY the
  /usr/bin/fusermount3 path, nothing else.

### Step 4.4: Replace fuse-support wiring with fuse-device (3 repos)

Note: multi-repo — must keep unrelated fuse_support.go content
byte-for-byte intact; this is a revert, not a rewrite.

Preconditions: Step 4.2 done (fuse-device interface must exist before
anything plugs it) and Step 4.3 done.

Repo A: ubuntu-desktop-session-snap

- snap/snapcraft.yaml, xdg-document-portal app's `plugs:` list:
  replace `fuse-support` with `fuse-device`. Do not touch
  daemon/daemon-scope/activates-on/restart-delay or any other plug in
  that list.

Repo B: pc-amd64-gadget-desktop

- gadget/gadget-amd64.yaml `connections:` list: replace the trailing
  `- plug: <snap-id>:fuse-support` entry with
  `- plug: <same-snap-id>:fuse-device`. Do not touch the
  network-control auto-connection (network-control is needed elsewhere
  and contributes unrelated mount rules — leave it alone).

Repo C: ubuntu-core-desktop-snapd

- interfaces/builtin/fuse_support.go: remove ONLY the doc-mount-rule
  block added for this work (the two `mount fstype=fuse.* ... doc/`
  lines and their preceding comment, at ~lines 79-86). Leave every
  other line of this file EXACTLY as it was before (capability
  sys_admin, /dev/fuse rw,, the connectedPlugUDev fuse tag, the
  /var/snap/... mount rules, secomp `mount` addition — all of that is
  fuse-support's own pre-existing, unrelated business and must NOT be
  touched). Confirm with
  `git log -p --follow interfaces/builtin/fuse_support.go` or a diff
  against the pre-session commit if unsure which lines were the
  temporary addition vs. pre-existing.
- core-base-desktop/Makefile: keep the `rm -f` of the stock
  xdg-document-portal.service / org.freedesktop.portal.Documents.service
  unit files (still correct, unrelated to the mount mechanism), but
  update the adjacent comment that currently references "using the
  fuse-support interface" so it instead references the fuse-device
  interface + broker/shim design.

Verification (must all pass before Step 4.5):

- No `fuse-support` references remain in
  ubuntu-desktop-session-snap/snap/snapcraft.yaml or
  pc-amd64-gadget-desktop/gadget/gadget-amd64.yaml:

      grep -rn "fuse-support" ubuntu-desktop-session-snap/snap/snapcraft.yaml
        pc-amd64-gadget-desktop/gadget/gadget-amd64.yaml

- `fuse-device` appears exactly once in each file, in the expected
  location.
- `git diff interfaces/builtin/fuse_support.go` in
  ubuntu-core-desktop-snapd shows ONLY the doc-mount-rule block being
  removed — a net-negative diff with no other lines touched. If the
  diff shows any other change, stop and fix before proceeding.
- `go build ./... && go test ./interfaces/builtin/... -check.f
  FuseSupport` still passes in ubuntu-core-desktop-snapd (confirms the
  revert didn't break fuse-support's own remaining tests).
- `git diff core-base-desktop/Makefile` shows only the comment wording
  change; the `rm -f` line itself is unchanged.

### Step 4.5: Pre-image local build/test gate

Note: mechanical — run existing build/test entrypoints, report
pass/fail; no design judgement needed.

Preconditions: Steps 4.2, 4.3, 4.4 all done.

What to run (use each repo's own documented command; do not invent new
ones):

- ubuntu-core-desktop-snapd: full `./run-checks` (or project's standard
  test entrypoint) for the interfaces package at minimum, ideally the
  full suite if time allows.
- ubuntu-desktop-session-snap: `snapcraft pack` (or the project's
  documented snap build entrypoint) for just this snap, confirming it
  packs successfully with the new layout + plug + shim part.
- pc-amd64-gadget-desktop: gadget.yaml validation the project already
  uses, if any (schema/lint), otherwise a visual diff review is
  sufficient since this is a 1-line change already verified in 4.4.

Verification (must all pass before Step 4.6):

- All commands above exit 0.
- The packed ubuntu-desktop-session snap contains /usr/bin/fusermount3
  resolving to the shim's content (unsquashfs and diff/checksum against
  the shim binary built in Step 4.3, or an equivalent inspection) — do
  not just trust that the layout line was added, confirm the artifact.

STOP CONDITION: if anything here fails, do NOT proceed to Step 4.6
(full image rebuild is expensive). Report the failure and fix it first.

### Step 4.6: Full image rebuild [DONE]

Note: mechanical invocation of an existing, already-used build pipeline.

Preconditions: Step 4.5 fully green.

What to run: the image build (`build.sh`), pulling in the three touched
repos (ubuntu-desktop-session-snap, pc-amd64-gadget-desktop,
ubuntu-core-desktop-snapd) plus the untouched-but-required
core-base-desktop (fuse-broker part, already built/committed from
Steps 1-3 — confirm it's still present and unmodified).

Verification (must pass before Step 4.7):

- Build completes with exit code 0 and produces a fresh image artifact
  (check the artifact's mtime/build-id is newer than the source
  changes, not a stale cached image).
- Spot-check the image contains the rebuilt snaps at the expected
  revisions (e.g. via `unsquashfs -l` on the produced snap blobs, or
  whatever inspection method was already used for the prior
  fuse-support build).

STOP CONDITION: if the build fails or silently reuses a cached/stale
snap, do not proceed to boot testing — fix the build first. A "looks
fine" boot test against a stale image would falsely validate nothing.

### Step 4.7: Fresh clean-boot verification [DONE]

(The step that proves the blocker is actually fixed.)

RESULT: first fresh boot still failed (`/dev/fuse: Operation not
permitted`, fuse-device plug listed but unconnected — gadget.yaml static
connections only resolve by snap-id, which local/--dangerous builds
never get). Root cause: `ubuntu-core-desktop/build.sh`'s dev-only
snap-connect workaround loop
(ensure-desktop-session-connections.service) had never been taught
about `fuse-device` when fuse-support was replaced. Fixed by adding
`fuse-device` to that loop's interface list; reran only the final
image-assembly stage (snapd/session/gadget snaps unchanged) and
re-verified on a second, fully clean fresh boot with NO manual
intervention: portal service active/running/NRestarts=0, FUSE mount
present, fuse-device connected automatically, fuse-broker's own log
confirms the shim's mount request was serviced (cmd=M), no new AppArmor
DENIED for fuse/mount. See `20260926-fuse-broker-step4-wiring.md` for
full detail.

Note: VM operation + judgement about ambiguous log output.

Preconditions: Step 4.6 fully green. MUST be a brand-new VM instance
booted from the just-built image — NOT the currently dirty VM (that
VM's live-patched AppArmor profile edits are explicitly known to be
unreliable for this test). If reusing that VM's disk is unavoidable,
fully reset/reprovision it from the new image first, and separately
restore/discard its dirty state before treating any result as valid.

Checks to run, in order, stopping at the first failure:

1. `systemctl --user --machine=your_username@ show
   snap.ubuntu-desktop-session.xdg-document-portal.service
   -p ActiveState,SubState,NRestarts`

   Expect: ActiveState=active, SubState=running, NRestarts=0 or 1 (not
   climbing on a repeat check 30s later).
2. `mount | grep doc` on the host.

   Expect: a fuse.<something> mount at
   /run/user/1000/snap.ubuntu-desktop-session/doc/.
3. `journalctl -b | grep DENIED` filtered to xdg-document-portal,
   fusermount3, and /run/xdg-fuse-broker.sock.

   Expect: NOTHING. Any DENIED here means either the fuse-device
   AppArmor rules are incomplete or mis-scoped — do not proceed, go
   back to Step 4.2 with the exact denial text.
4. Confirm the shim was ACTUALLY invoked (this is the specific blocker
   this file exists to fix — do not skip this check even though 1-3
   passing is suggestive): check the fuse-broker's own log
   (journalctl -u xdg-fuse-broker or equivalent, per core-base-desktop's
   systemd unit) for a mount request ('M' command) received from the
   portal's uid, at the time the portal service started. Cross-check
   against `ps`/audit evidence that /usr/bin/fusermount3 (the shim, not
   a real fusermount3) actually executed inside the portal's
   confinement around that timestamp.
5. `snap connections ubuntu-desktop-session | grep fuse`

   Expect: shows `fuse-device` connected, and does NOT show
   `fuse-support` at all (relaxed per the user's earlier approval).

Verification / STOP CONDITION: if check 3 shows a DENIED for the mount
rule specifically (i.e. errno reverts to EACCES), the fuse-device
interface's mount-allow lines are wrong/missing — return to Step 4.2,
do NOT attempt to patch AppArmor live on the VM as a "fix" (live-patch
testing was explicitly unreliable). If check 4 shows the mount
succeeded WITHOUT the shim ever running (e.g. mount(2) itself returned
0 for the confined process), something has accidentally granted real
CAP_SYS_ADMIN — treat this as a security regression, not a success,
and go back to Step 4.2/4.4 to find the leak.

### Step 4.8: Confirm no accidental privilege escalation [DONE]

(A fast regression check — an independent double-check of Step 4.7's
security property.)

RESULT: on the clean fresh boot, /proc/<portal-pid>/status shows
CapPrm=0000000000000000, CapEff=0000000000000000. No leak.

Note: a single mechanical check — no judgement needed beyond reading
two numbers.

Preconditions: Step 4.7 fully green.

What to run: on the fresh-booted VM, get the confined
xdg-document-portal process's pid and read /proc/<pid>/status looking
at CapEff/CapPrm/CapBnd.

Verification: CapEff and CapPrm are 0000000000000000 (i.e. still no
real capabilities), confirming the mount success in Step 4.7 came from
the broker (a separate, genuinely privileged process) and not from an
accidental capability grant to the confined process itself.

STOP CONDITION: any non-zero CapEff/CapPrm here means Step 4.2 or 4.4
leaked a capability grant somewhere — treat as a blocking security bug,
do not proceed to Step 5 of the master plan until fixed and re-verified
via 4.7 and 4.8 again.

### Step 4.9: Write the summary note and prep handoff [DONE]

(A mechanical writeup.)

RESULT: the summary note was written as
`20260926-fuse-broker-step4-wiring.md`.

Preconditions: Steps 4.1-4.8 all green.

What to do:

- Write the summary note covering: the EACCES-vs-EPERM finding, the
  final decision on where the mount-allow rule lives (fuse-device
  interface), the exact files touched across the 3 repos, and the
  verification results from Steps 4.7/4.8.
- Do NOT mark any plan item done yet — that only happens after the
  master plan's Step 5 (full end-to-end regression) also passes, per
  that plan's Step 6.

Verification: the note is self-contained (readable without the working
session's live context).

## Handoff

Once Steps 4.1-4.9 above are all green, resume execution at Step 5
("Full end-to-end functional + regression verification") of the master
fusermount-broker plan, unchanged — it was never invalidated by this
blocker, only Step 4 was. The plan's Step 6 (documentation/cleanup/
commit) then follows Step 5 as originally written.
