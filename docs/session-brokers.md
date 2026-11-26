# Privileged helper brokers used by the confined desktop session

These are small, narrowly-scoped privileged services that exist because
some piece of the confined GNOME/KDE session needs to do something a
snap-confined process cannot do for itself, without handing that
process broad capabilities.

## FUSE mount broker (xdg-fuse-broker)

`xdg-document-portal` runs confined and needs to create a FUSE mount
for its document directory, but a confined process has no real
`CAP_SYS_ADMIN` to call `mount(2)` itself. `xdg-fuse-broker` is a small
privileged root service that performs the actual FUSE mount on behalf
of the confined portal, together with a shim that replaces
`fusermount3` and hands the confined process a live FUSE file
descriptor over a Unix socket (via `SCM_RIGHTS`) instead of letting it
mount anything directly.

Access to the broker is gated by a dedicated snapd interface
(`fuse-device`) that grants only `/dev/fuse`, the broker's socket, and
a mount rule scoped to the portal's own doc directory — it does not
grant `CAP_SYS_ADMIN` or any other broad capability. This exists so
that GTK/portal-based file-open dialogs in confined apps (which depend
on `xdg-document-portal`) work at all, without widening the portal's
confinement to include real mount privileges.

## GNOME session environment broker

The session environment broker is a small Go D-Bus service in the
`ubuntu-desktop-session` snap. GNOME session apps need the user's
systemd and D-Bus activation environments (e.g. `DISPLAY`,
`XDG_SESSION_ID`, locale variables) kept in sync with what Mutter
reports via `Setenv`, but writing those shared environments directly
would require giving the session broad write permission. The broker
exists to mediate those updates: it is the only thing allowed to
actually write them.

`gnome-session-service` is the broker's sole authorized client and
forwards Mutter's `Setenv` updates to it; GNOME Session's own bulk
shared-environment export path is disabled so nothing else can write
these environments directly. The broker authenticates each caller by
UID and AppArmor label, only accepts updates for an explicit
display/session/locale allowlist, strips any `SNAP`/`SNAP_*` variables,
and forces host-visible values for `XDG_RUNTIME_DIR` and `XAUTHORITY`
before applying them to both the D-Bus activation environment and the
user systemd manager. It is not a general-purpose D-Bus or systemd
proxy, and it does not change the session's own child-process
environment.
