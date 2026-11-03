#!/usr/bin/env python3
"""Release helpers for Sonary: version numbers, Sparkle EdDSA signatures and the appcast feed.

Usage:
  release_tools.py version TAG                 -> prints "MARKETING BUILD"
  release_tools.py appcast --tag TAG --archive FILE --repo OWNER/REPO --notes FILE --out FILE
      (reads the base64 Ed25519 seed from env SPARKLE_ED_PRIVATE_KEY)
  release_tools.py public-key                  -> prints the public key for the seed in SPARKLE_ED_PRIVATE_KEY
"""
import argparse
import base64
import os
import re
import sys
from email.utils import formatdate

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

MIN_SYSTEM_VERSION = "26.0"


def parse_tag(tag: str) -> tuple[str, int]:
    """'v0.2.0' -> ('0.2.0', 200). Build number = major*10000 + minor*100 + patch (always grows)."""
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
    if not match:
        raise ValueError(f"Tag must look like v0.2.0, got {tag!r}")
    major, minor, patch = (int(part) for part in match.groups())
    if minor > 99 or patch > 99:
        raise ValueError("minor and patch must be at most 99")
    return f"{major}.{minor}.{patch}", major * 10000 + minor * 100 + patch


def _private_key(seed_b64: str) -> Ed25519PrivateKey:
    seed = base64.b64decode(seed_b64)
    if len(seed) != 32:
        raise ValueError("Ed25519 seed must be 32 bytes (base64)")
    return Ed25519PrivateKey.from_private_bytes(seed)


def sign(data: bytes, seed_b64: str) -> str:
    """Base64 Ed25519 signature of data, as expected in sparkle:edSignature."""
    return base64.b64encode(_private_key(seed_b64).sign(data)).decode()


def public_key(seed_b64: str) -> str:
    """Base64 public key, as expected in the app's SUPublicEDKey."""
    return base64.b64encode(_private_key(seed_b64).public_key().public_bytes_raw()).decode()


def _cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def appcast_xml(*, repo: str, tag: str, length: int, signature: str, notes: str, pub_date: str) -> str:
    marketing, build = parse_tag(tag)
    url = f"https://github.com/{repo}/releases/download/{tag}/Sonary-{marketing}.zip"
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sonary</title>
    <item>
      <title>Version {marketing}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{marketing}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <description>{_cdata(notes)}</description>
      <enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>
"""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    v = sub.add_parser("version")
    v.add_argument("tag")
    a = sub.add_parser("appcast")
    a.add_argument("--tag", required=True)
    a.add_argument("--archive", required=True)
    a.add_argument("--repo", required=True)
    a.add_argument("--notes", required=True)
    a.add_argument("--out", required=True)
    sub.add_parser("public-key")
    args = parser.parse_args(argv)

    if args.command == "version":
        marketing, build = parse_tag(args.tag)
        print(marketing, build)
        return 0

    seed = os.environ.get("SPARKLE_ED_PRIVATE_KEY", "").strip()
    if not seed:
        print("SPARKLE_ED_PRIVATE_KEY is not set", file=sys.stderr)
        return 2
    if args.command == "public-key":
        print(public_key(seed))
        return 0

    with open(args.archive, "rb") as handle:
        data = handle.read()
    with open(args.notes, encoding="utf-8") as handle:
        notes = handle.read()
    xml = appcast_xml(
        repo=args.repo, tag=args.tag, length=len(data), signature=sign(data, seed),
        notes=notes, pub_date=formatdate(usegmt=False),
    )
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(xml)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
