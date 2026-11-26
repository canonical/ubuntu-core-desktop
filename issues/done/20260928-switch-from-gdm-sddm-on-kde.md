# Switch the KDE configuration from GDM to SDDM

Status: DONE — KDE SDDM baseline built and verified

## Impact / Priority

Without a working SDDM integration, the KDE configuration had no display
manager once GDM moved out of the generic base: a current KDE image
could not boot to a login greeter and was not a valid post-Stage-3A
baseline. Impact derived from the original note's symptoms.

## Context

The ongoing work separates the GNOME desktop from `core26-desktop`; GDM
is expected to leave the generic base as part of that work and remain
with the GNOME desktop configuration. KDE should use its default
manager, SDDM.

Stage 3A has now moved the GDM daemon and greeter runtime into
`gnome-desktop-content`. The KDE image build does not seed that snap,
and no working SDDM service/greeter integration currently replaces it.
Therefore a current KDE image cannot be treated as a valid
post-Stage-3A baseline until this work is complete.

This is a product-configuration change, not a request to build a
general runtime display-manager selector. The selected system
configuration must start only its chosen manager.

## Goal

Boot the KDE-selected Core26 configuration into SDDM and allow login to
a working KDE Plasma session. Keep GDM out of the generic `core26` base
and avoid starting GDM in the KDE configuration.

## Work

1. Inspect the KDE snap, device model/seed, and current system-service
   integration. Identify where GDM is currently selected or enabled and
   where SDDM and KDE session metadata need to be supplied.
2. Keep GDM with the GNOME desktop configuration as it is moved out of
   `core26-desktop`. Do not add GDM to the generic `core26` base.
3. Update the KDE product configuration to include and enable SDDM, its
   required greeter/runtime content, and the KDE session entries. Use
   the project's supported snap/system integration mechanism; do not
   assume SDDM can read arbitrary files from another confined snap.
4. Ensure the KDE-selected configuration does not enable GDM.
   Installing KDE must not silently switch an existing system's manager
   or start a second manager. Define the supported behavior for systems
   that have multiple desktop sessions installed.
5. Keep this change limited to the supported GDM/GNOME and SDDM/KDE
   configurations. Do not add a generic manager selector, install-hook
   conflict checker, or arbitrary LightDM support in this task.
6. Add or update integration tests for boot, greeter startup, session
   launch, and manager service state.

## Acceptance criteria

* A KDE-selected Core26 system boots to the SDDM greeter.
* A user can start a KDE Plasma session from that greeter.
* No GDM service is enabled or started in the KDE-selected
  configuration.
* GDM remains the manager for the GNOME desktop configuration and is
  absent from the generic `core26` base.
* Reboot and supported update/recovery paths do not leave both managers
  active or make the system unable to reach a login prompt.
* Any multi-desktop session-selection behavior is explicitly tested and
  documented; unsupported manager/session pairings are not implied.
* Building and booting the KDE image with the image build
  (`build.sh --desktop kde`) produces the baseline consumed by
  `20261001-remove-kde-core26-desktop-dependency.md`; it must not depend
  on `gnome-desktop-content` or a running GDM service.
* The exact SDDM packaging/runtime owner, service enablement, session
  metadata, source revisions, and known exceptions are documented so the
  next note can distinguish display-manager failures from session-base
  regressions.

## Resolution (2026-10-01)

The KDE image now uses SDDM from `plasma-desktop-session`, rebuilt from
the pinned Ubuntu source against KDE Neon Qt 6.11.1 / KF6 6.30.0 /
Plasma 6.7.5. The KDE image masks GDM, and the GNOME/GDM split and
unsupported mixed GNOME/KDE configuration are documented. The session
snap and KDE image builds succeeded; the VNC guest passed the SDDM/Qt
6.11.1 greeter and login checks, including a reboot back to the greeter.
The user confirmed the final login worked.

Update/recovery testing is deferred by the user and remains unverified.
No runtime test combining GNOME and KDE was run; that configuration is
explicitly unsupported.

Related commits: `ubuntu-core-desktop` `4a2e166`, `ff2159d`,
`f350a32`; `plasma-desktop-session` `d7b5a7f`, `356621b`, `0e32eef`;
`plasma-core-desktop` `4054673a`.
