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


if __name__ == "__main__":
    unittest.main()
