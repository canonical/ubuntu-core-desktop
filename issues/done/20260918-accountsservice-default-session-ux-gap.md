# No supported way for users to select/keep the confined ubuntu-desktop-session

## Impact / Priority

High from a product/UX standpoint, even though it causes no crash or
data loss -- this is the difference between "the confined session is a
real, supported, user-facing feature" and "the confined session only
exists via manual developer commands". Concretely, for any real
(non-developer, non-SSH) user sitting at this machine's physical
console:
  - There is no gear/settings icon on the GDM greeter to pick a session
    at all in this build, so a user has no discoverable way to choose
    "Ubuntu Desktop (confined)" over the plain/unconfined session even
    if they wanted to.
  - Even if a session were selected once via the internal D-Bus
    workaround (`busctl ... SetSession`/`SetXSession`), that setting
    does NOT survive a reboot -- confirmed live: after this project's
    earlier manual fix was applied, `/var/lib/AccountsService/users/
    your_username` still shows `Session=` empty. So even a power user
    who discovers the manual D-Bus incantation has to re-run it after
    every reboot just to get their session choice to stick, which most
    users would reasonably read as "this is broken" or "my setting
    keeps getting reset", not as a documented limitation.
  - Net effect for a normal user: they will always land in the plain,
    unconfined `gnome-session`, never the confined/sandboxed
    `ubuntu-desktop-session`, regardless of login method (autologin or
    real password login), unless a developer intervenes on their
    behalf via SSH/console every single boot. If the confined session
    is meant to be this product's actual security value proposition,
    right now essentially no real end user will ever experience it.

## Context

Originally recorded as item 1 in
`20260915-followup-confined-session-apparmor-gaps.md` (now closed
out/split -- see that file's 2026-09-18 update). Re-verified live on
the test VM:

    $ sudo cat /var/lib/AccountsService/users/your_username
    [User]
    Session=
    Icon=/home/your_username/.face
    SystemAccount=false

`Session=` is blank despite the manual fix having been applied earlier
in this project (via `busctl call org.freedesktop.Accounts
/org/freedesktop/Accounts/User<uid> org.freedesktop.Accounts.User
SetSession s "ubuntu-desktop-session"` / `SetXSession` likewise) --
confirming the earlier suspicion that editing/setting this only takes
effect in accounts-daemon's in-memory state for that boot and is not
persisted to disk, or is not persisted the way GDM expects on
subsequent boots.

Known facts (still accurate):
  - There is no `AutomaticLoginSession`/`DefaultSession` key in
    `/usr/share/gdm/gdm.schemas` on this GDM build -- GDM autologin
    (`gdm-autologin`) unconditionally execs the literal `gnome-session`
    binary and does NOT consult AccountsService `Session=` or any
    `.desktop` file at all. Only a real (password) greeter login
    honours `AccountsService` `Session=<name>` matched against
    `/usr/share/wayland-sessions/<name>.desktop`.
  - This greeter build has no visible session-chooser gear icon, so
    there is currently no UI path for a user to pick a session
    themselves even on a real password login.

Two independent gaps, either of which alone would block real users
from getting the confined session, and both currently present:
  1. No UI to choose a session (greeter gear icon missing).
  2. Even a chosen/set session doesn't persist across reboot.

## Next steps

1. Add a session-chooser UI element to the greeter (the standard GDM
   gear icon on the login screen), OR make `ubuntu-desktop-session` the
   accounts-service default for newly-created users (so no explicit
   choice is even needed) -- decide which matches the product's
   intended UX before implementing either.
2. Investigate why `SetSession`/`SetXSession` via D-Bus doesn't persist
   to `/var/lib/AccountsService/users/<user>` across a reboot -- check
   whether accounts-daemon on this image is even writing that file back
   out (permissions/writable-path issue?), or whether GDM re-seeds/
   resets it in some case on this Core image (compare against how this
   works on a stock Ubuntu Desktop, where picking a session in the
   gear-icon menu does persist).
3. Once either/both are fixed, decide (and document) which login path
   (autologin vs. real password login) is the actual supported one for
   this product -- autologin structurally cannot honour a session
   choice at all per the facts above, so if autologin is meant to stay
   supported long-term, item 1's fix must go further than just
   AccountsService (e.g. bake the session choice directly into
   whatever generates the autologin config).

## Validation

1. Fresh image, fresh user, real password greeter login: user can see
   and pick "Ubuntu Desktop (confined)" (or equivalent) from a visible
   UI element, without any SSH/D-Bus intervention.
2. Reboot and log in again without re-selecting anything: the same
   session choice is honoured automatically (persisted correctly).
3. If autologin is meant to remain supported, confirm (or explicitly
   document as a known limitation) whether autologin can be made to
   honour the confined session too, given GDM's current
   `gdm-autologin`-execs-`gnome-session`-directly behaviour.

## Resolution (2026-11-27): every login is now the confined session

The gap was real when written: the confined session was opt-in through
AccountsService's `Session=` key, which neither persisted across a
reboot nor appeared in any UI. The architecture has since inverted
that, so there is nothing left for a user to select or keep.

- GNOME, fat-base path: `build.sh` bakes a `gnome-session` shim
  because GDM's Wayland launcher execs the literal `gnome-session` on
  PATH and ignores both the .desktop entry's `Exec=` and
  AccountsService's `Session=` key. The shim redirects every real user
  to `core-desktop-session-wrapper.sh`, i.e. into the confined session.
- GNOME, thin desktop/26 path: the base's gdm drop-in re-homes the
  session launch to `gnome-content-launch --session-dispatch`, which
  dispatches into the session snap. Verified live (confined
  `gnome-shell` on seat0, password login and wizard-continued session)
  in `20261110-image-login-findings-f1-f2-f4.md`.

So no real user can land in the plain, unconfined `gnome-session` any
more, which was this file's core complaint (next-step items 1 and 3).
The part of the intent that is still real - letting a user *choose*
between desktop sessions, including the greeter gear icon - belongs to
`20260922-multiple-desktop-session-support.md`, so it is tracked, not
dropped. Next-step item 2 (`Session=` not persisting) is moot for the
same reason: nothing reads that key on the session-launch path.

Closing as superseded by the forced-dispatch design.
