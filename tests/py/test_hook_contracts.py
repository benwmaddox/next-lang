"""The C runtime hooks the generated code calls keep their ABI and output (ported from selfhost_context_offsets.rs)."""

import os
import pathlib
import subprocess
import tempfile
import unittest

from hook_contract_fixtures import FIXTURES
from support import ROOT

LINK = str(ROOT / "scripts" / "nlc")


class HookContracts(unittest.TestCase):
    def test_core_context_prefix_matches_the_offset_runtime_layout(self):
        with tempfile.TemporaryDirectory(prefix="nl-offsets-") as temporary:
            binary = pathlib.Path(temporary) / "context-offsets"
            source = ROOT / "tests" / "py" / "context_offsets.c"
            built = subprocess.run(["clang", "-O0", "-pthread", str(source), "-o", str(binary)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(built.returncode, 0, "context-offset probe failed to compile: " + built.stderr.decode(errors="replace"))
            run = subprocess.run([str(binary)], stdout=subprocess.PIPE)
            self.assertEqual(run.returncode, 0)
            c_offsets = [int(value) for value in run.stdout.decode().split()]
        declaration = (ROOT / "core" / "context.nl").read_text()
        context = declaration.split("struct DataStackContext {", 1)[1].split("}", 1)[0]
        fields = []
        for line in context.splitlines():
            if ":" in line:
                name, ty = line.strip().split(":", 1)
                fields.append((name.strip(), ty.strip()))
        fields = fields[:15]
        expected = ["header_mapping", "header_bytes", "mapping", "mapping_bytes", "reservation_bytes", "peak_used_bytes",
                    "entry_name", "base", "top", "limit", "top_offset", "growth_count", "relocation_count",
                    "growth_nanoseconds", "poison_records"]
        self.assertEqual(len(fields), len(expected))
        for index, ((name, ty), want) in enumerate(zip(fields, expected)):
            self.assertEqual(name, want, f"context prefix field {index}")
            self.assertIn(ty, ("sys.Addr", "long"), f"unexpected context prefix type for {name}: {ty}")
        self.assertEqual(c_offsets, [index * 8 for index in range(len(fields))],
                         "DataStackContext offsets differ from the C offset-mode prefix")

    def test_legacy_c_hook_contracts_are_recorded(self):
        # Each body calls one entry in the C hook table; the expected bytes were captured from the runtime.
        with tempfile.TemporaryDirectory(prefix="nl-hooks-") as temporary:
            temporary = pathlib.Path(temporary)
            for fixture in FIXTURES:
                with self.subTest(fixture["name"]):
                    ir = temporary / f"{fixture['name']}.ll"
                    ir.write_text("; nlc-link-ir 1\n; nlc.build test\n; nlc.stack offset\n; nlc.recursion none\n"
                                  'source_filename = "hook-contract"\n' + fixture["body"] + "\n; nlc-link-ir end\n")
                    executable = temporary / fixture["name"]
                    linked = subprocess.run([LINK, "link-ir", str(ir), "-o", str(executable)],
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    self.assertEqual(linked.returncode, 0, linked.stderr.decode(errors="replace"))
                    env = {key: value for key, value in os.environ.items()
                           if key not in ("NLC_STACK_STATS", "NLC_STACK_VERIFY", "NLC_STACK_PREALLOC", "NLC_TEST_STACK_FORCE_MOVE", "NLC_TEST_INDEX")}
                    if fixture["test_index"] is not None:
                        env["NLC_TEST_INDEX"] = fixture["test_index"]
                    ran = subprocess.run([str(executable)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    self.assertEqual(ran.returncode, fixture["status"],
                                     f"{fixture['name']} status, stdout={ran.stdout!r}, stderr={ran.stderr!r}")
                    self.assertEqual(ran.stdout.decode("latin-1"), fixture["stdout"], f"{fixture['name']} stdout")
                    self.assertEqual(ran.stderr.decode("latin-1"), fixture["stderr"], f"{fixture['name']} stderr")


if __name__ == "__main__":
    unittest.main()
