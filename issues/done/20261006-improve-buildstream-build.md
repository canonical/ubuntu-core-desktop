# Speed up the kf6-core-sdk BuildStream build

Date: 2026-10-06
Project: `~/git/kf6-core-sdk` (110 elements, 32 cores, currently ~29 min)

## Impact / Priority

The kf6-core-sdk BuildStream build took ~29 minutes wall-clock with long
stretches where a single core was pinned at 100% and nothing else ran,
so the build was not using the machine's parallelism and rebuilds were
slower than they needed to be. Impact derived from the original note's
described symptoms.

## Goal

Cut wall-clock build time without leaving BuildStream (decision: stay
with BuildStream; Bazel / Make+Ninja+bwrap rejected as too complex or
losing fetch/pinning/cache keys/junctions). Build must stay namespaced
(bwrap) and host-independent.

Symptom: periods where the `bst` process pins one core at 100% and
nothing else is running. Hypothesis: BuildStream's own single-threaded
Python work (cache keys, staging/checkout, compose, mksquashfs,
scheduler stalls on a serial dependency chain), not the actual
compilation.

## Rules

- Change ONE thing at a time; re-measure after each step.
- Record every measurement in a results table at the bottom of this
  file.
- Do not proceed past a gate until its check passes. If a gate fails,
  write down why and stop or revise the plan.

### Step 0: Baseline

- Record versions: `bst --version`, buildbox-casd/-run versions, bwrap,
  disk and filesystem holding ~/.cache/buildstream (`df -h`,
  `findmnt`), nproc, RAM.
- Cold build with empty cache dir (or `--config` pointing at a fresh
  cache):

      /usr/bin/time -v bst build kf6-core26-sdk.bst 2>&1 | tee baseline-cold.log

  (use the actual top-level element name; check `ls elements`)
- Warm no-op rebuild (everything cached):

      /usr/bin/time -v bst build <target> 2>&1 | tee baseline-warm.log

- Save the per-element timings: `bst artifact log` / the build log, or
  the scheduler summary printed at the end.

GATE 0: cold time, warm no-op time and peak RSS are written in the
table. Warm no-op time is the pure BuildStream-overhead floor. If it is
more than ~1 min, overhead is a major problem, so go to Step 2 first.

### Step 1: Find where the time goes (timeline)

- Build the per-element timeline from the log (start/finish per
  element) and compute the critical path (longest chain of dependent
  builds) versus total CPU time.

    * Is average parallelism << 32? If yes, the graph is serial
      (Step 4).
    * Are the longest elements big C++ builds (qtbase, qtwebengine,
      etc.)? If yes, nothing in bst will help them and only ccache /
      more -j will.

- Sample CPU/IO while building: `vmstat 5`, `pidstat -u -d -p ALL 5` or
  htop. Note the wall-clock windows where load is ~1 core, and which
  element was running or being staged then.

GATE 1: a list of stall windows (start/end, bst PID CPU %, what element
or phase) and the critical path with element names and durations.

### Step 2: Profile the bst process during stalls

- Install py-spy (`pipx install py-spy`; may need sudo/ptrace_scope=0).
- During a stall: `py-spy top --pid <bst pid>` and
  `py-spy record -d 60 -o bst.svg --pid <bst pid> --subprocesses`.
- Also check the helper processes (buildbox-casd, buildbox-run,
  mksquashfs, tar, git) with `top`/`perf top -p`: is the single hot core
  bst, casd or a child process?
- Try `bst --debug build ...` and `bst --verbose` for phase timing;
  compare time spent in: key calculation, "Staging sources", "Staging
  dependencies", "Caching artifact", compose, the final checkout/pack.

GATE 2: one sentence naming the dominant stall cause backed by a
flamegraph or per-phase timing, e.g. "staging N deps per element: X min
total". Do NOT optimise anything before this is answered.

### Step 3: Quick wins that don't change the project

Apply each separately and re-run the warm and cold measurements.

 a. Cache/scratch location on fast storage (NVMe or tmpfs). Check that
    the CAS and build dirs share a filesystem so hardlinks/reflinks
    work.
 b. Scheduler tuning in ~/.config/buildstream.conf:

      scheduler:
        builders: <try 4, 8, 16>
        fetchers: 10
        pushers: 4

    and pass `--max-jobs` to match (cores / builders). Find the best
    combination; too many builders x -j oversubscribes the CPU.
 c. Make sure ccache or sccache is not needed for the cold case (see
    Step 5).
 d. Confirm bwrap sandbox is in use (buildbox-run-bubblewrap), not a
    slower fallback.

GATE 3: table shows time for each change; keep only changes that
improve cold or warm time by >3%. Do not lose isolation (no host
leakage).

### Step 4: Reduce staging cost and graph serialisation

Only if Step 1 or 2 pointed here.

- Count the staged dependency files per element
  (`bst show --deps run <el>` plus artifact sizes). Elements that stage
  the whole Qt + base SDK for a small library are the usual culprit.
- Narrow `build-depends` to the real minimum; split meta-elements into
  "stack" elements; use `filter` elements (split rules, e.g. only
  -devel domain) so builds stage headers and libs only; compose one
  slim "build-base" artifact once instead of staging many debs per
  element.
- Look for needless edges that serialise the graph (runtime-depends
  used as build-depends, everything depending on one `stack`).
- Check `bst show --format "%{name} %{state}" ...` after the change:
  cache keys should be unchanged for untouched elements.

GATE 4: critical path shortened and average parallelism up; the built
snap contents are identical (see Verification of output).

### Step 5: Speed up the compiles themselves (cold build)

- Check each cmake/meson element uses ninja with `-j%{max-jobs}`, and
  that no element is accidentally using `make -j1`.
- Disable work nobody needs: tests, docs, examples, translations if not
  shipped (`-DBUILD_TESTING=OFF`, `-DBUILD_QCH=OFF`, ...). Do not
  change shipped behaviour without checking the snap contents.
- Try ccache inside the sandbox as a mounted persistent dir (only helps
  rebuilds after invalidation, so decide if that scenario matters).
- Consider a shared/remote artifact cache (buildbox-casd cache server
  or BuildBarn) for rebuilds after small changes and for CI.

GATE 5: cold build time measured again; document what each flag saved.

### Step 6: Final verification

- Output must be equivalent to the baseline snap:

      unsquashfs -ll old.snap | sort > old.lst

  same for new; diff the lists (sizes may change slightly; paths must
  not), and run the snap's smoke tests / `snap try` and a KDE app build
  against the SDK.
- Reproducibility check: second cold build gives the same artifact
  keys.
- Cold build, warm no-op, and incremental build (touch one leaf
  element) times are in the table, versus baseline.

GATE 6: no content regressions, host independence still true (build
still works with PATH and /usr/local stripped / on a clean machine or
container), and the time target below is met or the reason it can't be
is understood.

## Target

Cold build <= ~20 min (from 29), warm no-op <= ~30 s, one-leaf
incremental rebuild <= a few minutes. Revisit if Step 2 shows the
bottleneck is inherent to BuildStream (then consider upstream
issue/patch, not a rewrite).

## Follow-ups (later, not part of this plan)

- Add related snaps as junctions/elements into one project.
- Remote cache for CI.

## Results table (fill in)

step / change | cold | warm no-op | incremental | notes
--------------+------+------------+-------------+------
baseline      |      |            |             |

## Resolution (2026-11-03)

NEVER STARTED, moot. No step was executed (the results table above is
empty; no commits landed after the initial BuildStream conversion,
ace3601). Moot regardless: the kf6-core-sdk BuildStream build left the
build path entirely when the project adopted the Neon deb-repack
pipeline (see the resolution on
`20261005-convert-kf6-core-sdk-snap-from-snapcraft-to-buildstream.md`),
so there is no production build left to optimise. Kept only as a record
of the planned measurement methodology.
