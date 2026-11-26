# Vendored /etc/xdg/autostart/localsearch-3.desktop is hook-trimmed

## Impact / Priority

Low. On the GNOME image the confined localsearch file-indexer
demonstrably runs anyway (observed as a systemd --user unit under
user@1000.service on the 2026-11-04 test VM), so no current end-user
impact is known: file indexing works today. The real risk is latent:
the vendored autostart entry in core-base-desktop
static/etc/xdg/autostart/localsearch-3.desktop is deleted by the
002.1-add-gdm greeter-trim hook (same build-order class as the
org.gnome.Settings.service bug fixed in 59690db), so the static copy
is dead config that silently rots; if anyone "fixes" the trim and
restores it verbatim, the file's OnlyShowIn=GNOME;KDE;... would launch
the GNOME session snap's localsearch on KDE images too, where the
ubuntu-desktop-session snap does not exist.

## Context

Found during the 2026-11-04 maintainer review of the Settings D-Bus
activation fixes (an independent completeness audit of that change).
static/etc/xdg/autostart/localsearch-3.desktop has
Exec=/snap/bin/ubuntu-desktop-session.localsearch-3 plus
X-GNOME-HiddenUnderSystemd=true / X-systemd-skip=true, and
hooks/002.1-add-gdm.chroot line 85 removes
/etc/xdg/autostart/localsearch-3.desktop (intent: drop the apt-staged
copy from the host greeter).

## Next steps

Confirm the indexer's actual start path on the image (systemd unit vs
autostart), then either delete the vendored autostart file from
static/ (if the unit path is authoritative) or make it
desktop-specific and restored after the trim, mirroring the Makefile's
post-hook re-copy now used for the Settings service files.
