# Check the GNOME keyring PAM handoff works on Ubuntu Core Desktop

## Impact / Priority

PRIORITY: Low — NOT a regression. Keyring behavior was never tested on
the fat base either, so there is no baseline this could have regressed
from. The structural half is already done: the thin core26-desktop
variant bakes a /usr/bin/gnome-keyring-daemon wrapper (commit 2907994)
at the exact path pam_gnome_keyring.so embeds, exec'ing the daemon
from gnome-desktop-runtime with the content snap's lib path; the
dependency closure is verified (ldd, 0 missing) and the wrapper runs
(--version via the content snap works). The UNTESTED half is the
functional PAM handoff: at password login, does the login keyring
actually unlock without a second prompt?

What a real user would observe if it's broken: any app that stores
secrets via the Secret Service API (org.freedesktop.secrets) pops an
extra "Unlock keyring" password dialog the first time it needs the
keyring after login. That is an annoyance and a small security-UX
regression vs classic Ubuntu (where PAM unlock is standard), but not a
functional break — secrets still work, just with an extra prompt.
Bounded, cosmetic-ish, and invisible to users who never use
keyring-backed apps.

## Background

The final independent review of the base-swap project (finding 6)
flagged that pam_gnome_keyring.so embeds /usr/bin/gnome-keyring-daemon,
which the fat base shipped on its rootfs but the thin variant initially
lacked — so the handoff could not work. The wrapper (2907994) restored
fat structural parity. The review's own instruction was "classify
against the fat baseline" — and the classification is: never tested on
fat either. Hence deferral rather than a gate.

## How to test when picked up (no seahorse needed — it isn't installed)

1. Password-login image (not autologin — the handoff runs in the PAM
   session phase of a password login): build or boot one (the
   build-gnome image at the time of writing used --user testuser
   --password testpass, no autologin).
2. `snap install chromium` — Chromium uses gnome-keyring via the
   Secret Service API for saved passwords (Firefox does NOT: its
   built-in store is its own encrypted file, it won't exercise the
   keyring).
3. Save a password in Chromium (any site form), then confirm the
   Secret Service has it: the keyring daemon should hold it.
4. Log out, log back in with the password, revisit the site:
   - PASS: autofill works, NO "Unlock keyring" dialog (PAM handoff
     unlocked it at login)
   - FAIL: an "Unlock keyring" prompt appears before autofill
5. If FAIL, diagnose: did pam_gnome_keyring exec the wrapper (journal
   around the login: the PAM module logs its daemon interaction)?
   Did the wrapper's daemon connect to the session's keyring socket?
   Note the wrapper runs the daemon UNCONFINED like the fat base did
   (the gdm profile's existing Ux rule mediates it).

## Also worth checking in the same pass (cheap once the setup exists)

- the login keyring is CREATED on first password login (classic GNOME
  does this; if no keyring exists there is nothing to unlock —
  arguably the handoff then trivially "works" but secrets apps would
  create it lazily later, without the login-password binding)
- screen lock/unlock does NOT re-trigger a keyring prompt (the
  reauthentication path keeps the keyring unlocked)

## Relationship to other work

- Not a base-swap gate item; tracked separately so the main base-swap
  work item's honest-scope statement stays accurate.
- If broken, the likely fix layers: the wrapper (variant) or the
  session snap's keyring startup interplay — check what actually
  happens before changing anything.
