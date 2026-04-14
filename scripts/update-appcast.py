#!/usr/bin/env python3
"""Update (or create) appcast.xml with a new release entry for Sparkle."""

import argparse
import os
import re
import sys
from xml.sax.saxutils import escape

APPCAST_PATH = os.path.join(os.path.dirname(__file__), "..", "appcast.xml")

EMPTY_APPCAST = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Notchly</title>
        <link>https://github.com/javierpr0/notchly</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
    </channel>
</rss>
"""


def parse_signature_line(line: str) -> dict:
    """Parse sign_update output like:  sparkle:edSignature="..." length="..."
    Returns a dict of attribute name -> value.
    """
    attrs = {}
    for match in re.finditer(r'(\S+?)="([^"]*)"', line):
        attrs[match.group(1)] = match.group(2)
    return attrs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--signature-line", required=True,
                        help='Output line from sign_update, e.g. sparkle:edSignature="..." length="..."')
    parser.add_argument("--release-notes-url", required=True)
    parser.add_argument("--min-macos", default="14.0")
    args = parser.parse_args()

    sig_attrs = parse_signature_line(args.signature_line)
    ed_signature = sig_attrs.get("sparkle:edSignature", "")
    length = sig_attrs.get("length", args.length)

    if not ed_signature:
        print("ERROR: could not extract sparkle:edSignature from signature line:", args.signature_line, file=sys.stderr)
        sys.exit(1)

    # Load or initialize appcast
    if os.path.exists(APPCAST_PATH):
        with open(APPCAST_PATH, "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = EMPTY_APPCAST

    new_item = f"""        <item>
            <title>Version {escape(args.version)}</title>
            <sparkle:version>{escape(args.version)}</sparkle:version>
            <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{escape(args.min_macos)}</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>{escape(args.release_notes_url)}</sparkle:releaseNotesLink>
            <pubDate>{escape(args.pub_date)}</pubDate>
            <enclosure url="{escape(args.url)}" sparkle:edSignature="{escape(ed_signature)}" length="{escape(length)}" type="application/octet-stream"/>
        </item>"""

    # Remove any existing item with the same version to keep appcast idempotent
    version_pattern = re.compile(
        r"\s*<item>.*?<sparkle:version>\s*" + re.escape(args.version) + r"\s*</sparkle:version>.*?</item>",
        re.DOTALL,
    )
    content = version_pattern.sub("", content)

    # Insert new item right after <channel> opening tag's metadata block (before first existing <item> or before </channel>)
    if "<item>" in content:
        content = content.replace("<item>", new_item.lstrip() + "\n        <item>", 1)
    else:
        content = content.replace("</channel>", new_item + "\n    </channel>", 1)

    with open(APPCAST_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"appcast.xml updated with version {args.version}")


if __name__ == "__main__":
    main()
