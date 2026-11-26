# Retry KDE build without the DRM-master patch

## Impact / Priority

Medium. A KDE login can currently show a black screen, preventing the
user from seeing or using the desktop. The observed failure may instead
be caused by the desktop background not being set, so the impact and
the correct fix need to be confirmed with an end-to-end login test on
rebuilt images.

## Context

The investigation recorded in `20260922-kwin-drm-master-black-screen.md`
identified a DRM-master handoff problem and led to a related patch that
appears to have been merged. Subsequent investigation indicates that the
root cause of the visible black screen was the background not being set.
We need to establish whether the DRM-master patch addressed a real
problem or changed behavior that was already correct.

## Work

- Identify the commits and build inputs related to the KDE DRM-master
  change, including the merged patch.
- Prepare and run a comparable KDE build with that patch reverted or
  otherwise excluded, while retaining the background-setting fix and
  other unrelated required changes.
- Boot the resulting image and perform repeated real graphical login
  tests, including logout/login if relevant. Verify that the desktop
  renders, KWin has the expected DRM state, and the background is set.
- Compare the no-DRM-master-patch result with the current build. If the
  desktop remains correct, clean up the now-unnecessary commits/patch
  and document the evidence; if it fails, separate the DRM handoff
  behavior from the background issue before changing the fix.

## Done when

A rebuilt image has been tested with the DRM-master patch absent, the
observed desktop behavior and relevant KWin/logind state have been
recorded, and any unnecessary commits or patches have been removed or
retained with an evidence-based explanation.

## Resolution (established in later work; note appended on import)

The KDE black-screen root cause was the missing background/wallpaper
setup, not the DRM-master patch; the desktop-background bug and the
DRM-master arrangement (kwin gaining its DRM state via the kwin app's
own login-session-control route and slots) were both fixed and
committed on the from-source pipeline's `desktop/26` branch, and the
image boots to a working desktop. No further patch-revert comparison
was needed; treat the DRM-master change as kept with that evidence.
