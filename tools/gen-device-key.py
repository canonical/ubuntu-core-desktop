#!/usr/bin/env python3
"""Per-build device key + serial assertion helpers for build.sh.

Replicates what snapd does for device keys (asserts.GenerateKey: RSA-4096,
OpenPGP v4 packets serialized with the fixed 2016-01-01 timestamp, see
snapd asserts/crypto.go) without needing a Go toolchain, so it runs on
build hosts and CI runners alike.

Subcommands:
  gen             Generate a fresh device keypair and the serial assertion
                  headers to sign:
                    <outdir>/device-key.privkey  content for the snapd
                        keypair-manager file
                        /var/lib/snapd/save/device/private-keys-v1/<id>
                    <outdir>/device-key.id       the key ID
                        (= the serial's device-key-sha3-384)
                    <outdir>/serial.json         headers; sign with
                        `snap sign -k <brand key>` and seed the result as
                        systems/<label>/assertions/serial.assert
  find-seed-part  Print the byte offset of a named GPT partition of an
                  image (default ubuntu-seed), for mtools' offset=.
"""

import argparse
import base64
import datetime
import hashlib
import json
import os
import secrets
import struct
import subprocess
import sys
import tempfile

# snapd v1FixedTimestamp (asserts/crypto.go): 2016-01-01T00:00:00Z
FIXED_TS = 1451606400
# x/crypto/openpgp packet types (new-format headers)
PKT_PUBLIC_KEY = 6
PKT_SECRET_KEY = 5
ALGO_RSA = 1


def mpi(i: int) -> bytes:
    b = i.to_bytes((i.bit_length() + 7) // 8, "big")
    return struct.pack(">H", i.bit_length()) + b


def packet(ptype: int, body: bytes) -> bytes:
    # x/crypto/openpgp serializeHeader: new-format header; lengths < 8384
    # use the two-byte form, otherwise the five-byte form (RSA-4096 keys
    # always take the five-byte form).
    hdr = bytearray([0x80 | 0x40 | ptype])
    n = len(body)
    if n < 192:
        hdr.append(n)
    elif n < 8384:
        n2 = n - 192
        hdr.append(192 + (n2 >> 8))
        hdr.append(n2 & 0xFF)
    else:
        hdr.append(255)
        hdr += struct.pack(">I", n)
    return bytes(hdr) + body


def pubkey_body(n: int, e: int) -> bytes:
    # OpenPGP v4 public-key body: version, creation time, algo, MPI(n),
    # MPI(e)
    return (
        b"\x04"
        + struct.pack(">I", FIXED_TS)
        + bytes([ALGO_RSA])
        + mpi(n)
        + mpi(e)
    )


def privkey_body(n, e, d, p, q, u) -> bytes:
    priv = mpi(d) + mpi(p) + mpi(q) + mpi(u)
    checksum = sum(priv) & 0xFFFF
    return (
        pubkey_body(n, e)
        + b"\x00"  # s2k type 0: unencrypted
        + priv
        + struct.pack(">H", checksum)
    )


def encode_v1(pkt: bytes) -> str:
    # asserts encodeV1: base64(0x01 || packet), wrapped at 76 chars
    raw = b"\x01" + pkt
    b64 = base64.b64encode(raw).decode()
    return "\n".join(b64[i : i + 76] for i in range(0, len(b64), 76))


def parse_rsa_der(der: bytes):
    # minimal DER walker for a PKCS#1 RSAPrivateKey:
    # SEQUENCE { INTEGER v, n, e, d, p, q, dP, dQ, qInv }
    # (handles both PKCS#1 and PKCS#8-wrapped output from openssl)

    def read_len(buf, off):
        first = buf[off]
        off += 1
        if first < 0x80:
            return first, off
        n = first & 0x7F
        val = int.from_bytes(buf[off : off + n], "big")
        return val, off + n

    def read_tag(buf, off):
        tag = buf[off]
        ln, off = read_len(buf, off + 1)
        return tag, off, off + ln

    def read_int(buf, off):
        tag, off, end = read_tag(buf, off)
        assert tag == 0x02, "expected INTEGER"
        return int.from_bytes(buf[off:end], "big"), end

    def find_privseq(buf, off=0):
        # depth-first search for a SEQUENCE consisting only of INTEGERs;
        # descends into SEQUENCE and OCTET STRING containers (PKCS#8 wraps
        # the PKCS#1 key in an OCTET STRING)
        while off < len(buf) - 2:
            tag, body, end = read_tag(buf, off)
            if tag in (0x30, 0x04):
                if tag == 0x30:
                    # try to read the children as INTEGERs
                    pos = body
                    vals = []
                    ok = pos < end
                    while ok and pos < end:
                        try:
                            v, pos = read_int(buf, pos)
                        except AssertionError:
                            ok = False
                            break
                        vals.append(v)
                    if ok and pos == end and len(vals) >= 6:
                        return vals
                # else descend into this container
                found = find_privseq(buf[body:end])
                if found is not None:
                    return found
            off = end
        return None

    vals = find_privseq(der)
    assert vals is not None, "no RSAPrivateKey structure found in DER"
    version, n, e, d, p, q = vals[0], vals[1], vals[2], vals[3], vals[4], vals[5]
    assert version == 0
    # OpenPGP requires p > q; u = q^-1 mod p
    if p < q:
        p, q = q, p
    u = pow(q, -1, p)
    return n, e, d, p, q, u


def cmd_gen(args):
    with tempfile.TemporaryDirectory() as td:
        key_pem = os.path.join(td, "device.pem")
        subprocess.run(
            ["openssl", "genrsa", "-out", key_pem, "4096"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        der = subprocess.run(
            ["openssl", "rsa", "-in", key_pem, "-outform", "DER"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        ).stdout
        n, e, d, p, q, u = parse_rsa_der(der)

    pub_pkt = packet(PKT_PUBLIC_KEY, pubkey_body(n, e))
    priv_pkt = packet(PKT_SECRET_KEY, privkey_body(n, e, d, p, q, u))

    # key ID: sha3-384 over v1Header + serialized public packet
    # (asserts newOpenPGPPubKey), base64url without padding
    digest = hashlib.sha3_384(b"\x01" + pub_pkt).digest()
    key_id = base64.urlsafe_b64encode(digest).rstrip(b"=").decode()

    serial = args.serial or ("ucd-" + str(secrets.token_hex(8)))

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "device-key.privkey"), "w") as f:
        f.write(encode_v1(priv_pkt) + "\n")
    with open(os.path.join(args.out_dir, "device-key.id"), "w") as f:
        f.write(key_id + "\n")
    with open(os.path.join(args.out_dir, "serial.json"), "w") as f:
        json.dump(
            {
                "type": "serial",
                "authority-id": args.brand_id,
                "brand-id": args.brand_id,
                "model": args.model,
                "serial": serial,
                "device-key": encode_v1(pub_pkt),
                "device-key-sha3-384": key_id,
                "timestamp": datetime.datetime.now(datetime.timezone.utc)
                .replace(microsecond=0)
                .isoformat()
                .replace("+00:00", "Z"),
            },
            f,
            indent=2,
        )
        f.write("\n")
    print(key_id)


def cmd_find_seed_part(args):
    with open(args.image, "rb") as f:
        f.seek(512)  # LBA 1: GPT header (512-byte sectors assumed)
        hdr = f.read(92)
        if hdr[:8] != b"EFI PART":
            print(f"not a GPT image: {args.image}", file=sys.stderr)
            return 1
        part_lba, num_parts, part_size = struct.unpack_from("<QII", hdr, 72)
        for i in range(num_parts):
            f.seek(part_lba * 512 + i * part_size)
            entry = f.read(part_size)
            if entry[:16] == b"\x00" * 16:
                continue
            first_lba = struct.unpack_from("<Q", entry, 32)[0]
            name = entry[56:128].decode("utf-16-le").rstrip("\x00")
            if name == args.name:
                print(first_lba * 512)
                return 0
    print(f"partition {args.name!r} not found in {args.image}", file=sys.stderr)
    return 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    gen = sub.add_parser("gen", help="generate a device keypair + serial.json")
    gen.add_argument("--out-dir", required=True)
    gen.add_argument("--brand-id", required=True)
    gen.add_argument("--model", required=True)
    gen.add_argument("--serial", default=None)
    gen.set_defaults(func=cmd_gen)

    fp = sub.add_parser(
        "find-seed-part", help="print a GPT partition's byte offset"
    )
    fp.add_argument("--image", required=True)
    fp.add_argument("--name", default="ubuntu-seed")
    fp.set_defaults(func=cmd_find_seed_part)

    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
