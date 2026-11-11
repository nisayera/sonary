import base64
import os
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(__file__))
import release_tools as rt  # noqa: E402

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: E402

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class ParseTagTests(unittest.TestCase):
    def test_marketing_version_and_build_number(self):
        self.assertEqual(rt.parse_tag("v0.2.0"), ("0.2.0", 200))
        self.assertEqual(rt.parse_tag("v0.1.0"), ("0.1.0", 100))
        self.assertEqual(rt.parse_tag("v1.0.0"), ("1.0.0", 10000))
        self.assertEqual(rt.parse_tag("v0.9.3"), ("0.9.3", 903))

    def test_build_number_grows_with_every_release(self):
        tags = ["v0.1.0", "v0.2.0", "v0.2.1", "v0.9.0", "v1.0.0"]
        builds = [rt.parse_tag(t)[1] for t in tags]
        self.assertEqual(builds, sorted(builds))
        self.assertEqual(len(set(builds)), len(builds))

    def test_rejects_malformed_tags(self):
        for bad in ["0.2.0", "v0.2", "v0.2.x", "release-1", "v1.0.0-beta", ""]:
            with self.assertRaises(ValueError):
                rt.parse_tag(bad)

    def test_rejects_minor_or_patch_above_99(self):
        with self.assertRaises(ValueError):
            rt.parse_tag("v0.100.0")


class SignTests(unittest.TestCase):
    def test_signature_verifies_with_matching_public_key(self):
        key = Ed25519PrivateKey.generate()
        seed = key.private_bytes_raw()
        data = b"archive bytes"
        signature = base64.b64decode(rt.sign(data, base64.b64encode(seed).decode()))
        self.assertEqual(len(signature), 64)
        key.public_key().verify(signature, data)  # raises if invalid

    def test_public_key_of_seed(self):
        key = Ed25519PrivateKey.generate()
        seed_b64 = base64.b64encode(key.private_bytes_raw()).decode()
        expected = base64.b64encode(key.public_key().public_bytes_raw()).decode()
        self.assertEqual(rt.public_key(seed_b64), expected)

    def test_rejects_seed_of_wrong_length(self):
        with self.assertRaises(ValueError):
            rt.sign(b"x", base64.b64encode(b"short").decode())


class AppcastTests(unittest.TestCase):
    def build(self, notes="Hello & <welcome>"):
        return rt.appcast_xml(
            repo="nisayera/sonary", tag="v0.2.0", length=12345, signature="SIG==",
            notes=notes, pub_date="Tue, 03 Nov 2026 18:00:00 +0000",
        )

    def test_item_fields(self):
        root = ET.fromstring(self.build())
        item = root.find("channel/item")
        self.assertEqual(item.find(SPARKLE + "version").text, "200")
        self.assertEqual(item.find(SPARKLE + "shortVersionString").text, "0.2.0")
        self.assertEqual(item.find(SPARKLE + "minimumSystemVersion").text, "26.0")
        enclosure = item.find("enclosure")
        self.assertEqual(
            enclosure.get("url"),
            "https://github.com/nisayera/sonary/releases/download/v0.2.0/Sonary-0.2.0.zip",
        )
        self.assertEqual(enclosure.get("length"), "12345")
        self.assertEqual(enclosure.get(SPARKLE + "edSignature"), "SIG==")

    def test_notes_survive_cdata_terminator_and_markup(self):
        xml = self.build(notes="evil ]]> text & <b>")
        description = ET.fromstring(xml).find("channel/item/description").text
        self.assertEqual(description, "evil ]]> text & <b>")


CHANGELOG = """# Changelog

Intro text.

## [Unreleased]

### Added
- Not out yet.

## [0.83.5] - 2026-11-11

### Summary
Safer updates.

### Fixed
- The panel no longer freezes when Finder hangs.
- Names with <angle> & `code` stay **intact**.

## [0.80.0] - 2026-11-10

### Changed
- Older change.

[0.83.5]: https://github.com/nisayera/sonary/releases/tag/v0.83.5
[0.80.0]: https://github.com/nisayera/sonary/releases/tag/v0.80.0
"""


class ChangelogTests(unittest.TestCase):
    def test_section_of_one_version_without_its_heading(self):
        section = rt.changelog_section(CHANGELOG, "0.83.5")
        self.assertTrue(section.startswith("### Summary\nSafer updates."))
        self.assertIn("- The panel no longer freezes when Finder hangs.", section)
        self.assertNotIn("Older change", section)
        self.assertNotIn("Not out yet", section)

    def test_last_section_drops_link_references(self):
        section = rt.changelog_section(CHANGELOG, "0.80.0")
        self.assertEqual(section, "### Changed\n- Older change.")

    def test_missing_undated_or_empty_entries_stop_the_release(self):
        with self.assertRaises(ValueError):
            rt.changelog_section(CHANGELOG, "9.9.9")
        with self.assertRaises(ValueError):
            rt.changelog_section("## [1.0.0]\n\n### Fixed\n- x\n", "1.0.0")
        with self.assertRaises(ValueError):
            rt.changelog_section("## [1.0.0] - 2026-01-01\n\n### Summary\nNothing listed.\n", "1.0.0")

    def test_release_body_is_changes_then_install(self):
        body = rt.release_notes(CHANGELOG, "v0.83.5")
        self.assertTrue(body.startswith("### Summary"))
        self.assertLess(body.index("### Fixed"), body.index("### Install"))
        self.assertIn("Sonary-0.83.5.dmg", body)
        self.assertIn("Privacy & Security", body)
        self.assertIn("Open Anyway", body)
        self.assertNotIn("choose Open, then Open again", body)

    def test_the_repository_changelog_has_the_project_version(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "project.yml"), encoding="utf-8") as handle:
            marketing, build = rt.project_version(handle.read())
        self.assertEqual(rt.parse_tag("v" + marketing)[1], build)
        with open(os.path.join(root, "CHANGELOG.md"), encoding="utf-8") as handle:
            self.assertIn("- ", rt.changelog_section(handle.read(), marketing))


class MarkdownTests(unittest.TestCase):
    def test_headings_lists_and_inline_markup(self):
        out = rt.markdown_to_html(rt.changelog_section(CHANGELOG, "0.83.5"))
        self.assertIn("<h3>Summary</h3>", out)
        self.assertIn("<p>Safer updates.</p>", out)
        self.assertIn("<ul><li>The panel no longer freezes when Finder hangs.</li>", out)
        self.assertIn("&lt;angle&gt; &amp; <code>code</code> stay <strong>intact</strong>", out)

    def test_numbered_lists_links_and_continuation_lines(self):
        out = rt.markdown_to_html("1. One\n   more\n2. [Two](https://example.com)\n\nText")
        self.assertEqual(out, '<ol><li>One more</li><li><a href="https://example.com">Two</a></li></ol>\n<p>Text</p>\n')

    def test_output_is_valid_inside_the_appcast(self):
        html = rt.markdown_to_html(rt.changelog_section(CHANGELOG, "0.83.5"))
        xml = rt.appcast_xml(repo="nisayera/sonary", tag="v0.83.5", length=1, signature="S",
                             notes=html, pub_date="Wed, 11 Nov 2026 12:00:00 +0100")
        self.assertEqual(ET.fromstring(xml).find("channel/item/description").text, html)


class ProjectVersionTests(unittest.TestCase):
    PROJECT = 'settings:\n  base:\n    MARKETING_VERSION: "0.80.0"\n    CURRENT_PROJECT_VERSION: 8000\n'

    def test_reads_version_and_build(self):
        self.assertEqual(rt.project_version(self.PROJECT), ("0.80.0", 8000))

    def test_set_version_derives_the_build_number(self):
        updated = rt.set_project_version(self.PROJECT, "0.83.5")
        self.assertEqual(rt.project_version(updated), ("0.83.5", 8305))
        self.assertIn('    MARKETING_VERSION: "0.83.5"\n', updated)

    def test_rejects_a_project_without_versions(self):
        with self.assertRaises(ValueError):
            rt.project_version("name: Sonary\n")
        with self.assertRaises(ValueError):
            rt.set_project_version("name: Sonary\n", "1.0.0")


if __name__ == "__main__":
    unittest.main()
