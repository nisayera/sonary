#!/usr/bin/env python3
"""Release helpers for Sonary: version numbers, Sparkle EdDSA signatures and the appcast feed.

Usage:
  release_tools.py version TAG                 -> prints "MARKETING BUILD"
  release_tools.py project-version [--project project.yml]
                                               -> prints "TAG MARKETING BUILD" for the version in project.yml
  release_tools.py check-project [--project project.yml] [--changelog CHANGELOG.md]
                                               -> fails unless the build number in project.yml follows from
                                                  its version and CHANGELOG.md has a dated entry for it
  release_tools.py set-version VERSION [--project project.yml]
                                               -> writes MARKETING_VERSION and CURRENT_PROJECT_VERSION
  release_tools.py notes --tag TAG [--changelog CHANGELOG.md] --out FILE [--appcast-out FILE]
                                               -> the GitHub release body (Markdown) for TAG from CHANGELOG.md,
                                                  and optionally the same changes as HTML for the appcast
  release_tools.py appcast --tag TAG --archive FILE --repo OWNER/REPO --notes FILE --out FILE
      (reads the base64 Ed25519 seed from env SPARKLE_ED_PRIVATE_KEY; --notes is HTML)
  release_tools.py public-key                  -> prints the public key for the seed in SPARKLE_ED_PRIVATE_KEY
"""
import argparse
import base64
import html
import os
import re
import sys
from email.utils import formatdate

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


def _private_key(seed_b64: str):
    # Imported here, so the version and changelog commands run without the package installed.
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

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


# MARK: project.yml


def project_version(project_yml: str) -> tuple[str, int]:
    """(MARKETING_VERSION, CURRENT_PROJECT_VERSION) as written in project.yml."""
    marketing = re.search(r'^\s*MARKETING_VERSION:\s*"?([0-9.]+)"?\s*$', project_yml, re.M)
    build = re.search(r'^\s*CURRENT_PROJECT_VERSION:\s*"?([0-9]+)"?\s*$', project_yml, re.M)
    if not marketing or not build:
        raise ValueError("project.yml needs MARKETING_VERSION and CURRENT_PROJECT_VERSION")
    return marketing.group(1), int(build.group(1))


def set_project_version(project_yml: str, version: str) -> str:
    """project.yml with MARKETING_VERSION set to version and CURRENT_PROJECT_VERSION derived from it."""
    marketing, build = parse_tag("v" + version)
    text, found_marketing = re.subn(r'^(\s*MARKETING_VERSION:\s*).*$', rf'\g<1>"{marketing}"', project_yml,
                                    count=1, flags=re.M)
    text, found_build = re.subn(r'^(\s*CURRENT_PROJECT_VERSION:\s*).*$', rf'\g<1>{build}', text,
                                count=1, flags=re.M)
    if not found_marketing or not found_build:
        raise ValueError("project.yml needs MARKETING_VERSION and CURRENT_PROJECT_VERSION")
    return text


# MARK: CHANGELOG.md
#
# The changelog follows Keep a Changelog (https://keepachangelog.com/en/1.1.0/), like Vorssaint's:
#
#   ## [0.83.5] - 2026-11-11
#
#   ### Summary
#   One or two sentences about the release.
#
#   ### Added / ### Changed / ### Fixed / ### Removed / ### Security
#   - One line per change, written for the people who use Sonary.
#
# The section of a version becomes the body of its GitHub release and the notes Sparkle shows
# before an update, so every release says in plain words what changed.

_HEADING = re.compile(r"^## \[([^\]]+)\](?:\s*-\s*(\d{4}-\d{2}-\d{2}))?\s*$")


def changelog_section(changelog: str, version: str) -> str:
    """The body of the dated `## [version] - YYYY-MM-DD` entry, without its heading."""
    lines = changelog.splitlines()
    start = None
    for index, line in enumerate(lines):
        match = _HEADING.match(line)
        if match and match.group(1) == version:
            if not match.group(2):
                raise ValueError(f"CHANGELOG.md entry for {version} has no date (## [{version}] - YYYY-MM-DD)")
            start = index + 1
            break
    if start is None:
        raise ValueError(f"CHANGELOG.md has no entry for {version}")
    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break
    # Link references at the end of the file ([0.83.5]: https://...) are not part of the notes.
    body = [line for line in lines[start:end] if not re.match(r"^\[[^\]]+\]:\s*\S+", line)]
    text = "\n".join(body).strip()
    if not re.search(r"^- \S", text, re.M):
        raise ValueError(f"CHANGELOG.md entry for {version} lists no changes")
    return text


def install_notes(marketing: str) -> str:
    """How to install a release, below the changes on its GitHub page."""
    return f"""### Install
Requires macOS 26 on a Mac with Apple silicon. Download `Sonary-{marketing}.dmg` below, open it and drag Sonary to Applications.

Sonary is not notarized by Apple yet, so macOS blocks the first launch:

1. Open Sonary. When macOS says it cannot verify the app, click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the note about Sonary.
3. Click **Open Anyway**, confirm with your password or Touch ID, then click **Open Anyway** once more.

Right-click → Open no longer skips this check since macOS 15. Updates after that install from inside the app (Sparkle), without these steps."""


def release_notes(changelog: str, tag: str) -> str:
    """The GitHub release body: the changes from CHANGELOG.md, then how to install."""
    marketing, _ = parse_tag(tag)
    return changelog_section(changelog, marketing) + "\n\n" + install_notes(marketing) + "\n"


def _inline_html(text: str) -> str:
    escaped = html.escape(text, quote=True)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    return re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', escaped)


def markdown_to_html(markdown: str) -> str:
    """The small part of Markdown a changelog uses (### headings, - and 1. lists, paragraphs,
    `code`, **bold**, links) as HTML, which is what Sparkle shows as release notes."""
    out: list[str] = []
    paragraph: list[str] = []
    items: list[str] = []
    list_tag = ""

    def flush_paragraph():
        if paragraph:
            out.append("<p>" + _inline_html(" ".join(paragraph)) + "</p>")
            paragraph.clear()

    def flush_list():
        nonlocal list_tag
        if items:
            out.append(f"<{list_tag}>" + "".join(f"<li>{_inline_html(item)}</li>" for item in items)
                       + f"</{list_tag}>")
            items.clear()
        list_tag = ""

    for raw in markdown.splitlines():
        line = raw.strip()
        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        bullet = re.match(r"^[-*]\s+(.*)$", line)
        numbered = re.match(r"^\d+\.\s+(.*)$", line)
        if not line:
            flush_paragraph()
            flush_list()
        elif heading:
            flush_paragraph()
            flush_list()
            level = min(6, max(3, len(heading.group(1))))
            out.append(f"<h{level}>{_inline_html(heading.group(2))}</h{level}>")
        elif bullet or numbered:
            flush_paragraph()
            tag = "ul" if bullet else "ol"
            if list_tag and list_tag != tag:
                flush_list()
            list_tag = tag
            items.append((bullet or numbered).group(1))
        elif items and raw.startswith((" ", "\t")):
            items[-1] += " " + line
        else:
            flush_list()
            paragraph.append(line)
    flush_paragraph()
    flush_list()
    return "\n".join(out) + "\n"


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


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    v = sub.add_parser("version")
    v.add_argument("tag")
    pv = sub.add_parser("project-version")
    pv.add_argument("--project", default="project.yml")
    cp = sub.add_parser("check-project")
    cp.add_argument("--project", default="project.yml")
    cp.add_argument("--changelog", default="CHANGELOG.md")
    sv = sub.add_parser("set-version")
    sv.add_argument("version")
    sv.add_argument("--project", default="project.yml")
    n = sub.add_parser("notes")
    n.add_argument("--tag", required=True)
    n.add_argument("--changelog", default="CHANGELOG.md")
    n.add_argument("--out", required=True)
    n.add_argument("--appcast-out")
    a = sub.add_parser("appcast")
    a.add_argument("--tag", required=True)
    a.add_argument("--archive", required=True)
    a.add_argument("--repo", required=True)
    a.add_argument("--notes", required=True)
    a.add_argument("--out", required=True)
    sub.add_parser("public-key")
    args = parser.parse_args(argv)

    try:
        if args.command == "version":
            marketing, build = parse_tag(args.tag)
            print(marketing, build)
            return 0
        if args.command == "project-version":
            marketing, build = project_version(_read(args.project))
            print(f"v{marketing}", marketing, build)
            return 0
        if args.command == "check-project":
            marketing, build = project_version(_read(args.project))
            _, expected = parse_tag(f"v{marketing}")
            if build != expected:
                raise ValueError(f"CURRENT_PROJECT_VERSION is {build}, but version {marketing} needs {expected}. "
                                 f"Run: python3 scripts/release_tools.py set-version {marketing}")
            changelog_section(_read(args.changelog), marketing)
            print(f"project.yml {marketing} ({build}) and its CHANGELOG.md entry are in order")
            return 0
        if args.command == "set-version":
            _write(args.project, set_project_version(_read(args.project), args.version))
            print(*project_version(_read(args.project)))
            return 0
        if args.command == "notes":
            changelog = _read(args.changelog)
            _write(args.out, release_notes(changelog, args.tag))
            if args.appcast_out:
                marketing, _ = parse_tag(args.tag)
                _write(args.appcast_out, markdown_to_html(changelog_section(changelog, marketing)))
            return 0
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    seed = os.environ.get("SPARKLE_ED_PRIVATE_KEY", "").strip()
    if not seed:
        print("SPARKLE_ED_PRIVATE_KEY is not set", file=sys.stderr)
        return 2
    if args.command == "public-key":
        print(public_key(seed))
        return 0

    with open(args.archive, "rb") as handle:
        data = handle.read()
    xml = appcast_xml(
        repo=args.repo, tag=args.tag, length=len(data), signature=sign(data, seed),
        notes=_read(args.notes), pub_date=formatdate(usegmt=False),
    )
    _write(args.out, xml)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
