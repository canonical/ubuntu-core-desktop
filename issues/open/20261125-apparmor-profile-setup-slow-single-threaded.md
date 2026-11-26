# Snap AppArmor profile setup is single-threaded and pathologically slow

## Impact / Priority

Medium-high. It does not affect an image after boot,
but it is the dominant cost of a first boot on slow hosts and it is what
made the new CI image boot gate flaky: the gate sat waiting for
snapd.seeded for 20+ minutes, which looked exactly like "the desktop is
broken". It also means a user on modest hardware watches a black screen
for a very long time with no explanation. On a fast laptop the same image
seeds in ~90 s, so the spread between hosts is ~40x for the same work.

What happens, precisely:

- Profile *compilation* (apparmor_parser --replace --write-cache) runs
  when a snap is installed, refreshed or seeded - i.e. essentially once
  per snap version. That is the slow part.
- At every boot, snapd.apparmor.service re-loads the already compiled
  profiles from /var/cache/apparmor. That part is cheap: measured 0.1 s
  for 75 profiles (KDE image) on this host.
- So the 20 minute case is compilation, not a per-boot cost.

Measured on this host (Ryzen AI MAX+, so a fast CPU), inside the guest:

    plasma-desktop-session, 19 profiles:
      -j1  -> 3.8 s
      -j4  -> 2.1 s      (1.8x)
    i.e. ~200 ms per complex profile.

The GNOME session snap (ubuntu-desktop-session) is the worst offender:
~80 profiles (gnome-shell, gsd-*, gvfs*, xdg-desktop-portal*,
localsearch*, ibus*, ...), which is ~16 s single-threaded here.

On GitHub-hosted runners (KVM confirmed available, 86 GB free disk, so
neither disk nor TCG is the cause) the same step takes 20+ min. The
spread is not explained yet - see "to investigate".

Why it is single-threaded:

snapd does not hardcode -j1: numberOfJobsParam() (sandbox/apparmor/
profile.go) returns -j(ncpu-2), floored at -j1 for machines with two
CPUs or fewer, and LoadProfiles only adds it when ConserveCPU is set -
which SetupMany (the "many snaps at once" path used by seeding) does.
The CI gate was booting its VM with -smp 2, so snapd took the 2-CPU
branch and deliberately used -j1: the gate itself was forcing the
single-threaded path. Fixed by booting the gate VM with -smp 4
(=> -j2); seeding dropped from ~3 min to ~2 min in the first runs.

For a normal user this means the job count already scales with their
CPU count (a 16-core machine gets -j14), which is worth knowing before
"fixing" this: the pathological case is specifically low-vCPU VMs and
contended runners.

Sizes (measured on a freshly seeded GNOME image, 2026-11-25):

- profile text in /var/lib/snapd/apparmor/profiles: 174 files, 18 MB.
  The largest single one is snap.ubuntu-desktop-session.gnome-shell at
  299 KB; ubuntu-desktop-session alone accounts for 72 profiles / 15 MB.
- compiled cache in /var/cache/apparmor: 186 files, 32 MB (one hash
  directory, f6da0254.0).

So the compiled set is small enough to ship in an image (32 MB against
a 3-6 GB image) if a precompilation route is ever taken; the obstacle
is snapd's --skip-read-cache on setup, not disk space.

Compile time for the 72 ubuntu-desktop-session profiles on a fast host
(4 vCPU guest, KVM): -j1 20.7 s, -j2 10.6 s - close to linear. On the
CI runners the same work has taken 20+ min, i.e. ~60x slower, which no
amount of -j tuning explains; that gap is still unexplained.

Can the profiles be pre-compiled? (answered 2026-11-25, from the source)

Compilation is deterministic and carries nothing host-specific: the
inputs are the profile text, the policy features (snapd's own abi
file), the parser version and the flags. There is no machine id, uuid
or hostname in the result, so the same inputs produce the same binary
policy anywhere. The cache is keyed on content/mtime, that is all.

BUT it cannot be exploited by shipping /var/cache/apparmor in the
image: Backend.Setup and Backend.SetupMany pass SkipReadCache for all
*changed* profiles, i.e. they always invoke apparmor_parser with
--skip-read-cache, deliberately:

    "we know those changed for sure. This allows us to work despite
     time being wrong (e.g. in the past); apparmor_parser caching is
     based on mtime"  (interfaces/apparmor/backend.go)

The cache is written on every compile but only read for *unchanged*
profiles, which is why a warm boot loads 75 profiles in ~0.1s while
seeding recompiles everything from scratch.

Two real options, both of which mean changing how the image is built:

1. preseed. snapd already supports it: with preseed set, the same
   path is used with SkipKernelLoad, compiles the profiles at image
   build time and writes the cache. That is exactly the "precompile"
   this question is about - but it populates /var and skips first-
   boot seeding, which is a change to the Ubuntu Core image model
   (seed partition -> seed at first boot), not a local tweak.
2. patch our snapd fork not to skip the read cache when the cached
   entry matches, or to preseed the cache with mtimes the parser
   accepts. Cheap to try, must be validated: a stale cache silently
   loading an old policy is a security-relevant failure mode, which
   is presumably why upstream forces the recompile.

To investigate:

1. Measure on the runner, not just locally. The boot gate now prints
   the last seeding tasks on timeout; extend that to run the parser
   timing (same flags snapd uses, -j1 vs -j4) inside the gate VM and
   print the numbers. That turns "20 min" into "20 min where?".
2. Confirm the per-profile cost is CPU and not I/O: on a slow host,
   run the same command with the cache on tmpfs vs disk, and watch CPU
   vs iowait. A 100x spread for pure CPU work would be surprising; if
   it is I/O, the cache location is the fix. (Note the runner is a
   nested VM on shared hardware, so "slow CPU" is also plausible.)
3. Look at the profile count itself. Many of the 80 are tiny wrapper
   apps (gsd-*, some *-service entries); if a chunk of them can be
   consolidated into fewer profiles with the same confinement, that
   reduces the work independently of parallelism.
4. If preseed is on the table (see above), that removes seeding from
   first boot entirely and makes this whole issue moot - but it is a
   change to the image build model, so decide at project level first.

Notes:

- Never "fix" this by letting the CI gate publish when seeding is slow:
  the gate needs seeding to finish because GDM is ordered behind
  snapd.seeded (gdm-homedirs Requires=snapd.seeded, gdm Requires=
  gdm-homedirs). A 30 min seeding budget is the current workaround.
