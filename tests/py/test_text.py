"""Text capacity diagnostics and large-literal relocation (ported from selfhost_text_*.rs)."""

import os
import subprocess
import unittest

from support import ROOT, compile_package, selfhost, temporary_package

BIG = "9223372036854775807"

CAPACITY_CASES = {
    "ascii-header": f"fn invalid(value: Ascii max {BIG}) {{}}\nfn main() {{}}\n",
    "bytes-header": f"fn invalid(value: Bytes max {BIG}) {{}}\nfn main() {{}}\n",
    "text-points": f"fn invalid(value: Text max {BIG}) {{}}\nfn main() {{}}\n",
    "text-header": f"fn invalid(value: Text bytes max {BIG}) {{}}\nfn main() {{}}\n",
    "bytes-to-text": "fn invalid(value: Bytes max 9223372036854775799) { let converted = value.to_text(); print(converted.is_ok()) }\nfn main() {}\n",
    "text-result-tag": "fn invalid(value: Bytes max 9223372036854775791) { let converted = value.to_text(); print(converted.is_ok()) }\nfn main() {}\n",
    "ascii-option-tag": "fn main() { let value: Ascii max 1 = \"a\"; let fitted = value.fit<Ascii max 9223372036854775799>(); print(fitted.is_some()) }\n",
    "padding-header": f"fn main() {{ let value = pad(\"x\", {BIG}L); print(value.len()) }}\n",
    "zero-padding-header": f"fn main() {{ let value = pad_zero(1L, {BIG}L); print(value.len()) }}\n",
    "ascii-concat": "fn invalid(left: Ascii max 4611686018427387903, right: Ascii max 4611686018427387903) { let joined = left + right; print(joined.len()) }\nfn main() {}\n",
    "bytes-concat": "fn invalid(left: Bytes max 9223372036854775799, right: Bytes max 1) { let joined = left + right; print(joined.count()) }\nfn main() {}\n",
}


class TextCapacity(unittest.TestCase):
    def test_impossible_text_bounds_are_diagnostics_not_compiler_overflows(self):
        for name, source in CAPACITY_CASES.items():
            with self.subTest(name), temporary_package({"main.nl": source}) as directory:
                result = compile_package(directory, output="module.ll", timeout=30)
                stderr = result.stderr.decode(errors="replace")
                self.assertEqual(result.returncode, 2, f"{name}: {stderr}")
                self.assertEqual(result.stdout, b"", f"{name}: unexpected compiler stdout")
                self.assertIn("error", stderr, name)
                self.assertNotIn("not supported by the self-hosted compiler yet", stderr, name)
                self.assertFalse((directory / "module.ll").exists(), f"{name}: emitted invalid IR")


class TextRelocation(unittest.TestCase):
    def test_first_large_literal_survives_relocation_and_borrowed_slicing(self):
        # The literal comes before every declaration, so it is the first expression node: node zero must
        # not double as planner scratch.
        source = ('test "large first literal" {\n    let payload = b"' + "A" * (1024 * 1024) + '"\n'
                  "    print(payload.count())\n    let sliced = head(payload)\n    expect sliced == b\"AAAA\"\n}\n"
                  "fn head(input: Bytes max 1048576) -> Bytes max 1048576 { input.slice(0L..4L) }\n")
        with temporary_package({"main.nl": source, "package.toml": 'capabilities = ["out"]\n'}) as directory:
            built = compile_package(directory, output="module.ll", extra=["--test", "--test-region-threshold=0"], timeout=120)
            self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
            env = dict(os.environ, NLC_OPT_LEVEL="1")
            linked = subprocess.run([str(ROOT / "scripts" / "nlc"), "link-ir", "module.ll", "-o", "program"],
                                    cwd=directory, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(linked.returncode, 0, linked.stderr.decode(errors="replace"))
            env = dict(os.environ, NLC_TEST_INDEX="0", NLC_TEST_STACK_FORCE_MOVE="1", NLC_STACK_STATS="1", NLC_STACK_VERIFY="1")
            env.pop("NLC_STACK_PREALLOC", None)
            ran = subprocess.run(["./program"], cwd=directory, env=env, timeout=30,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stderr = ran.stderr.decode(errors="replace")
            self.assertEqual(ran.returncode, 0, stderr)
            self.assertEqual(ran.stdout, b"1048576\n")

            def statistic(name):
                for line in stderr.splitlines():
                    if line.startswith("nl offset stack entry "):
                        for field in line.split():
                            if field.startswith(name + "="):
                                return int(field[len(name) + 1:])
                self.fail(f"missing {name}: {stderr}")

            self.assertGreater(statistic("growths"), 0, stderr)
            self.assertGreater(statistic("relocations"), 0, stderr)
            self.assertLess(statistic("peak_used"), 3 * 1024 * 1024,
                            f"borrowed slice reserved an extra source-sized temporary: {stderr}")


if __name__ == "__main__":
    unittest.main()
