# Implement locale/language selection for Ubuntu Core Desktop

## Impact / Priority

PRIORITY: Medium — a real, visible feature gap, confirmed pre-existing
on BOTH the fat base and the thin variant (user-verified 2026-11-06:
Settings > System > Region & Language shows NO languages to select and
"Manage installed languages" does nothing — identical on fat, so not a
base-swap regression, but a genuine broken feature users hit on first
contact with the desktop). What a user loses: the ability to pick
their language/region at first boot or afterwards — for non-English
users this is close to a blocker for daily use; for English users it
is invisible. The end-to-end state has never worked in this project's
images, so "what a real user would observe" is not hypothetical — it
is the recorded behavior above.

## Design (from the Stage A base-swap design, §4 + unknown-#4 resolution)

The mechanism was designed and partially verified during the base-swap
Stage A work:
- Compiled locales: glibc resolves via LOCPATH from non-rootfs paths —
  EMPIRICALLY VERIFIED on the live VM (setlocale resolves from
  LOCPATH outside /usr/lib/locale; both plain processes and systemd
  service children; survives snap run into confined processes).
  LOCPATH must point at a snap-visible path (/snap/...), not /tmp
  (private-tmp).
- Propagation to the greeter/session: two verified routes — a gdm
  (or SDDM) service drop-in Environment=LOCPATH=..., or pam_env via
  /etc/environment (both greeter and user PAM sessions read it).
- Language data: the langpack .mo catalogs (2,787 usr/share/locale
  paths on the fat base) belong in the content snap (mechanism C);
  usr/lib/locale compiled-locale set is identical stock-vs-fat (544
  C.* dirs — the fat base never shipped natural-language compiled
  locales either, which is why the picker was empty: no
  /usr/share/i18n/SUPPORTED-driven generation and no langpacks
  installed).
- The picker's data source: gdm/gnome-language-selector and the
  Settings panel read the installed-languages list from
  accountsservice/localed + the presence of locale data; the fat base
  shipped /usr/share/i18n/SUPPORTED and the wizard consumed
  SetLanguage via provd (language-tools gap noted during the Stage A
  work).

## Work items

1. Content snap: ship natural-language compiled locales (the set
   behind SUPPORTED, or a curated major-languages set for size) +
   langpack .mo data in gnome-desktop-runtime (GNOME) and the
   kf6/plasma equivalents (KDE); define LOCPATH=<snap lib-locale dir>.
2. Wiring: LOCPATH via /etc/environment (covers greeter + session +
   confined apps; the verified route) — bake in the variant or seed
   via build.sh; SDDM side needs the equivalent for KDE.
3. localed/accountsservice: verify SetLocale + the language list
   plumbing (the locale1 read-only dbus policy issue was already
   fixed on the variant — 312844c); provd/ubuntu-desktop-init
   SetLanguage path end-to-end.
4. Gate (interactive-heavy, needs VNC): wizard language selection
   changes the greeter/session language; Settings > Region & Language
   lists languages and switching works after logout/login; KDE
   equivalent (systemsettings locale page + SDDM language); the
   C.UTF-8 default path unaffected.
5. Size note: langpacks are large — record the image-size cost
   honestly (curated set vs full SUPPORTED).

## Notes

- Do NOT scope-creep into input methods/keyboard layouts (those work;
  SetX11Keyboard was verified during the wizard gates).
- The pre-existing nature (broken on fat too) means this is a feature
  implementation, not a regression fix — sequence it after the
  publish/CI work unless it blocks a release goal.
