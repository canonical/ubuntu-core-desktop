#!/usr/bin/python3
"""Narrow root helper for boot-check's offline image inspection."""

import json
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path


def fail(message):
    print(f"boot-check-privileged: {message}", file=sys.stderr)
    raise SystemExit(2)


def caller():
    if os.geteuid() == 0 and "SUDO_UID" not in os.environ:
        account = pwd.getpwuid(0)
        return 0, 0, Path(account.pw_dir).resolve()
    try:
        uid = int(os.environ["SUDO_UID"])
        gid = int(os.environ["SUDO_GID"])
        account = pwd.getpwuid(uid)
    except (KeyError, ValueError):
        fail("must be invoked through sudo by a regular user")
    if uid == 0 or os.geteuid() != 0:
        fail("must run as root through sudo")
    return uid, gid, Path(account.pw_dir).resolve()


def owned_output(path_arg, uid, home):
    path = Path(path_arg)
    if path.name != "ubuntu-data":
        fail("mountpoint must be named ubuntu-data")
    if path.is_symlink():
        fail("mountpoint must not be a symlink")
    mount_dir = path.resolve(strict=True)
    output_dir = mount_dir.parent
    if not output_dir.is_relative_to(home) or output_dir == home:
        fail("output directory must be below the invoking user's home")
    if output_dir.is_symlink():
        fail("output directory must not be a symlink")
    output_stat = output_dir.stat()
    mount_stat = mount_dir.stat()
    if output_stat.st_uid != uid or output_stat.st_mode & 0o022:
        fail("output directory must be user-owned and not group/world writable")
    expected_mount_owner = 0 if mount_dir.is_mount() else uid
    if mount_stat.st_uid != expected_mount_owner:
        fail("mountpoint must be user-owned before mounting and root-owned while mounted")
    if not mount_dir.is_mount() and mount_stat.st_mode & 0o022:
        fail("mountpoint must not be group/world writable before mounting")
    return mount_dir, output_dir


def checked_mount(path_arg, uid, home):
    mount_dir, _ = owned_output(path_arg, uid, home)
    if not mount_dir.is_mount():
        fail("requested path is not a mountpoint")
    return mount_dir


def safe_path(root, relative, *, expected=None):
    current = root
    for part in relative.parts:
        if part in {"", ".", ".."}:
            fail("invalid internal path")
        current = current / part
        try:
            current_stat = current.lstat()
        except FileNotFoundError:
            fail("required offline image path is missing")
        if stat.S_ISLNK(current_stat.st_mode):
            fail("offline image paths must not contain symlinks")
    if expected == "directory" and not stat.S_ISDIR(current_stat.st_mode):
        fail("offline image path is not a directory")
    if expected == "file" and not stat.S_ISREG(current_stat.st_mode):
        fail("offline image path is not a regular file")
    return current


def system_data_dir(mount_dir):
    candidate = mount_dir / "system-data"
    try:
        candidate_stat = candidate.lstat()
    except FileNotFoundError:
        return mount_dir
    if stat.S_ISLNK(candidate_stat.st_mode) or not stat.S_ISDIR(candidate_stat.st_mode):
        fail("system-data must be a real directory")
    return candidate


def output_paths(output_arg, uid, home):
    output = Path(output_arg)
    if output.is_symlink():
        fail("output directory must not be a symlink")
    output_dir = output.resolve(strict=True)
    if not output_dir.is_relative_to(home) or output_dir == home:
        fail("output directory must be below the invoking user's home")
    output_stat = output_dir.stat()
    if not output_dir.is_dir() or output_stat.st_uid != uid or output_stat.st_mode & 0o022:
        fail("output directory must be user-owned and not group/world writable")
    image = output_dir / "pc.img.copy"
    if image.is_symlink():
        fail("image path must not be a symlink")
    image_stat = image.stat()
    if not stat.S_ISREG(image_stat.st_mode) or image_stat.st_uid != uid:
        fail("image must be owned by the invoking user")
    mount_dir = output_dir / "ubuntu-data"
    if mount_dir.is_symlink() or not mount_dir.is_dir():
        fail("mountpoint must be a real directory below the output directory")
    mount_stat = mount_dir.stat()
    expected_mount_owner = 0 if mount_dir.is_mount() else uid
    if mount_stat.st_uid != expected_mount_owner:
        fail("mountpoint must be user-owned before mounting and root-owned while mounted")
    return output_dir, image, mount_dir


def journal(mount_dir, selector, extra, uid, home):
    mount_dir = checked_mount(mount_dir, uid, home)
    system_data = system_data_dir(mount_dir)
    journal_dir = safe_path(system_data, Path("var/log/journal"), expected="directory")
    for entry in journal_dir.iterdir():
        if entry.is_symlink():
            fail("offline journal directory must not contain symlinks")

    args = ["/usr/bin/journalctl", "-D", str(journal_dir), "-b", "0", "--no-pager"]
    if selector == "all":
        args += ["-o", "short-monotonic"]
    elif selector == "seeded":
        args += ["-u", "snapd.seeded.service", "-o", "short-monotonic"]
    elif selector == "errors":
        args += ["-p", "err..alert", "-o", "short-monotonic"]
    elif selector in {"gdm", "sddm"}:
        args += ["-u", f"{selector}.service", "-o", "cat"]
    elif selector == "kernel":
        args += ["-k", "-o", "cat"]
    elif selector == "user-manager" and re.fullmatch(r"[0-9]+", extra):
        args += ["-u", f"user@{extra}.service", "-o", "short-monotonic"]
    else:
        fail("unsupported journal query")
    os.execv(args[0], args)


def copy_state(mount_dir, destination, uid, gid, home):
    mount_dir = checked_mount(mount_dir, uid, home)
    output_dir = mount_dir.parent
    destination_path = Path(destination)
    expected = output_dir / "snapd-state.json"
    if destination_path != expected:
        fail("state snapshot destination must be snapd-state.json in the output directory")

    system_data = system_data_dir(mount_dir)
    source = safe_path(system_data, Path("var/lib/snapd/state.json"), expected="file")
    source_fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    dest_fd = os.open(expected, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
    try:
        source_stat = os.fstat(source_fd)
        dest_stat = os.fstat(dest_fd)
        if not stat.S_ISREG(source_stat.st_mode) or not stat.S_ISREG(dest_stat.st_mode):
            fail("state snapshot source and destination must be regular files")
        if dest_stat.st_uid != uid:
            fail("state snapshot destination must be owned by the invoking user")
        os.fchown(dest_fd, uid, gid)
        os.fchmod(dest_fd, 0o600)
        with os.fdopen(source_fd, "rb", closefd=False) as src, os.fdopen(dest_fd, "wb", closefd=False) as dst:
            shutil.copyfileobj(src, dst)
    finally:
        os.close(source_fd)
        os.close(dest_fd)


def read_passwd(mount_dir, username, uid, home):
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*[$]?", username):
        fail("invalid account name")
    mount_dir = checked_mount(mount_dir, uid, home)
    system_data = system_data_dir(mount_dir)
    passwd_file = safe_path(system_data, Path("var/lib/extrausers/passwd"), expected="file")
    fd = os.open(passwd_file, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if line.split(":", 1)[0] == username:
                print(line.rstrip("\n"))
                return


def read_ssh(mount_dir, uid, home):
    mount_dir = checked_mount(mount_dir, uid, home)
    system_data = system_data_dir(mount_dir)
    ssh_config = system_data / "etc/ssh/sshd_config.d/listen.conf"
    if ssh_config.exists():
        ssh_config = safe_path(system_data, Path("etc/ssh/sshd_config.d/listen.conf"), expected="file")
        fd = os.open(ssh_config, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, encoding="utf-8", errors="replace") as stream:
            for line in stream:
                fields = line.split()
                if len(fields) >= 2 and fields[0] == "ListenAddress":
                    print(fields[1])


def main(argv):
    uid, gid, home = caller()
    if not argv:
        fail("operation is required")
    operation, *args = argv

    if operation == "mount" and len(args) == 3:
        output_dir, image, mount_dir = output_paths(args[0], uid, home)
        offset_text, size_text = args[1:]
        if not re.fullmatch(r"[0-9]+", offset_text) or not re.fullmatch(r"[1-9][0-9]*", size_text):
            fail("invalid partition offset or size")
        if any(mount_dir.iterdir()):
            fail("mountpoint must be empty")
        subprocess.run([
            "/usr/bin/mount", "-t", "ext4", "-o",
            f"loop,ro,noload,offset={offset_text},sizelimit={size_text}",
            str(image), str(mount_dir),
        ], check=True)
    elif operation == "umount" and len(args) == 1:
        _, _, mount_dir = output_paths(args[0], uid, home)
        if mount_dir.is_mount():
            subprocess.run(["/usr/bin/umount", str(mount_dir)], check=True)
    elif operation == "journal" and len(args) in {2, 3}:
        _, _, mount_dir = output_paths(args[0], uid, home)
        if args[1] not in {"all", "seeded", "errors", "gdm", "sddm", "kernel", "user-manager"}:
            fail("unsupported journal query")
        if args[1] == "user-manager" and (len(args) != 3 or not re.fullmatch(r"[0-9]+", args[2])):
            fail("invalid user manager id")
        if args[1] != "user-manager" and len(args) != 2:
            fail("unexpected journal query argument")
        journal(str(mount_dir), args[1], args[2] if len(args) == 3 else "", uid, home)
    elif operation == "copy-state" and len(args) == 2:
        _, _, mount_dir = output_paths(args[0], uid, home)
        copy_state(str(mount_dir), args[1], uid, gid, home)
    elif operation == "read-passwd" and len(args) == 2:
        _, _, mount_dir = output_paths(args[0], uid, home)
        read_passwd(str(mount_dir), args[1], uid, home)
    elif operation == "read-ssh" and len(args) == 1:
        _, _, mount_dir = output_paths(args[0], uid, home)
        read_ssh(str(mount_dir), uid, home)
    else:
        fail("unsupported operation or invalid arguments")


if __name__ == "__main__":
    main(sys.argv[1:])
