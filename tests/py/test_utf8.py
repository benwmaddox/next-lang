"""Text conversions follow the UTF-8 boundary rules, checked against Python's independent decoder
(ported from selfhost_utf8.rs)."""

import os
import subprocess
import unittest

from support import ROOT, compile_package, temporary_package

EXTRA_VECTORS = [
    b"", b"ASCII\0\x7f", b"\xc2\x80", b"\xdf\xbf", b"\xe0\xa0\x80", b"\xed\x9f\xbf", b"\xee\x80\x80", b"\xef\xbf\xbf",
    b"\xf0\x90\x80\x80", b"\xf4\x8f\xbf\xbf", b"\xc0\xaf", b"\xc1\xbf", b"\xe0\x9f\xbf", b"\xed\xa0\x80", b"\xed\xbf\xbf",
    b"\xf0\x8f\xbf\xbf", b"\xf4\x90\x80\x80", b"\xf5\x80\x80\x80", b"\xc2\x7f", b"\xe1\x80\x7f", b"\xf1\x80\x80\x7f",
    b"\xc2", b"\xe0\xa0", b"\xf0\x90\x80", b"\xc2\x80\xe0\xa0\x80\xf0\x90\x80\x80",
]


def decode(data):
    try:
        return -1, True, len(data.decode("utf-8"))
    except UnicodeDecodeError as error:
        return error.start, False, None


class Utf8(unittest.TestCase):
    def test_text_conversions_follow_utf8_boundary_rules(self):
        vectors = [bytes([byte]) for byte in range(256)]
        for data in EXTRA_VECTORS:
            vectors.append(data)
            vectors.append(b"A\xc2\xa2" + data)
        source = ["fn main() {"]
        expected = []
        for index, data in enumerate(vectors):
            literal = "".join(f"\\x{byte:02X}" for byte in data)
            source.append(f'    let input_{index}: Bytes max {len(data)} = b"{literal}"')
            source.append(f"    match input_{index}.validate_utf8() {{ ok(_) => print(-1L), err(issue_{index}) => print(issue_{index}.valid_up_to), }}")
            source.append(f"    print(input_{index}.to_text().is_ok())")
            source.append(f"    print(input_{index}.to_ascii().is_ok())")
            offset, valid, count = decode(data)
            expected += [str(offset), str(valid).lower(), str(all(byte < 128 for byte in data)).lower()]
            if valid:
                source.append(f"    print(input_{index}.to_text().unwrap().len())")
                expected.append(str(count))
        source.append("}")
        level = "3" if os.environ.get("NLC_LONG_TESTS") == "1" else "1"
        with temporary_package({"main.nl": "\n".join(source) + "\n", "package.toml": 'capabilities = ["out"]\n'}) as directory:
            built = compile_package(directory, output="module.ll", timeout=90)
            self.assertEqual(built.returncode, 0, "UTF-8 probe build: " + built.stderr.decode(errors="replace"))
            self.assertNotIn("call void @nl_core_nl_text_assert_valid(", (directory / "module.ll").read_text(),
                             "ordinary programs must not revalidate constructed Text")
            linked = subprocess.run([str(ROOT / "scripts" / "nlc"), "link-ir", "module.ll", "-o", "program"], cwd=directory,
                                    env=dict(os.environ, NLC_OPT_LEVEL=level), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(linked.returncode, 0, linked.stderr.decode(errors="replace"))
            ran = subprocess.run(["./program"], cwd=directory, timeout=15, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            self.assertEqual(ran.stdout.decode().splitlines(), expected)

    def test_constructed_text_asserts_its_invariant_in_test_mode(self):
        # Corrupt only this generated test module, just before its constructor assertion. User code has no
        # facility for breaking the Text invariant.
        cases = [
            ('fn main() {}\ntest "Text literal invariant" { let value: Text max 1 = "a"; print(value) }\n', "%text.literal.assert.data."),
            ('fn make_text() -> Text max 1 { "a" }\nfn main() {}\ntest "Text function invariant" { print(make_text()) }\n', "%text.literal.assert.data."),
            ('fn copy(value: Text max 1) -> Text max 1 { value }\nfn main() {}\ntest "Text borrowed-copy invariant" { let source: Ascii max 1 = "a"; print(copy(source)) }\n', "%text.assert.data."),
        ]
        for source, assertion_pointer in cases:
            with self.subTest(assertion_pointer), temporary_package({"main.nl": source, "package.toml": 'capabilities = ["out"]\n'}) as directory:
                built = compile_package(directory, output="checked.ll", extra=["--test"], timeout=60)
                self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
                checked = (directory / "checked.ll").read_text()
                assertion = next((line for line in checked.splitlines()
                                  if "call void @nl_core_nl_text_assert_valid(" in line and assertion_pointer in line), None)
                self.assertIsNotNone(assertion, "test-mode Text construction must assert its invariant")
                pointer = assertion.split("ptr %nl.ctx, ptr ", 1)[1].split(", i64 ", 1)[0]
                corrupted = checked.replace(assertion, f"  store i8 -1, ptr {pointer}, align 1\n{assertion}", 1)
                (directory / "corrupted.ll").write_text(corrupted)
                linked = subprocess.run([str(ROOT / "scripts" / "nlc"), "link-ir", "corrupted.ll", "-o", "corrupted"], cwd=directory,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(linked.returncode, 0, linked.stderr.decode(errors="replace"))
                ran = subprocess.run(["./corrupted"], cwd=directory, env=dict(os.environ, NLC_TEST_INDEX="0"), timeout=15,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(ran.returncode, 70, ran.stderr.decode(errors="replace"))
                self.assertIn("invalid Text constructed (compiler or core library bug)", ran.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
