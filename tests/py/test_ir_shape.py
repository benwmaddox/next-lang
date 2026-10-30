"""Checks on the shape of emitted IR and on compile-time scaling (ported from selfhost_*.rs)."""

import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
import time
import unittest

from support import ROOT, compile_package, selfhost, temporary_package


class FieldProjection(unittest.TestCase):
    def test_indexed_scalar_field_projection_avoids_materializing_the_row(self):
        output_dir = ROOT / "target" / "b1-scalar-field-projection"
        output_dir.mkdir(parents=True, exist_ok=True)
        output = output_dir / "selfhost-regression.ll"
        built = subprocess.run(
            [str(selfhost()), "build", "tests/e3/b1_scalar_field_projection", "-o", output.relative_to(ROOT).as_posix(), "--runtime=core"],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        ir = output.read_text()
        # read_base is the first user function in the fixture, so it is nl_fn_0.
        self.assertIn("define i64 @nl_fn_0(", ir, "read_base is missing from emitted selfhost LLVM IR")
        body = ir.split("define i64 @nl_fn_0(", 1)[1].split("\n}\n", 1)[0]
        lines = [line.strip() for line in body.splitlines()]
        field_address = None
        for line in lines:
            if " = " in line:
                address, instruction = line.split(" = ", 1)
                if "getelementptr" in instruction and "coll.field.index.offset." in instruction:
                    field_address = address
                    break
        self.assertIsNotNone(field_address, "read_base has no direct scalar field GEP")
        self.assertTrue(any(f"= load i64, ptr {field_address}" in line for line in lines),
                        f"read_base must load the projected scalar from its field GEP:\n{body}")
        self.assertTrue(any("call void @nl_fail(ptr %nl.ctx, i32 16" in line for line in lines),
                        f"read_base must preserve the list index bounds check:\n{body}")
        index_node_id = None
        for line in lines:
            if " = " in line:
                result = line.split(" = ", 1)[0]
                prefix = "%coll.index.negative."
                if result.startswith(prefix):
                    digits = "".join(c for c in result[len(prefix):] if c.isdigit() and True)
                    # stop at the first non-digit
                    digits = ""
                    for character in result[len(prefix):]:
                        if not character.isdigit():
                            break
                        digits += character
                    if digits:
                        index_node_id = digits
                        break
        self.assertIsNotNone(index_node_id, "read_base has no index bounds-check node marker")
        aggregate_result = f"%v{index_node_id} = load "
        aggregate_address = f"ptr %addr.{index_node_id},"
        for line in lines:
            self.assertFalse(line.startswith(aggregate_result) or (" = load " in line and aggregate_address in line),
                             f"the aggregate Index node must not produce its own scalar load:\n{body}")
        self.assertNotIn("coll.gather", body)
        self.assertNotIn("@nl.copy", body, f"read_base must not gather or copy the row before projecting its field:\n{body}")
        self.assertNotIn("region.offset", body, f"read_base must not reserve a large temporary for the projected row:\n{body}")


class NameScopes(unittest.TestCase):
    def test_repeated_parameter_name_checks_scale_subcubically(self):
        def build_time(package):
            started = time.monotonic()
            result = subprocess.run(
                ["timeout", "30", str(selfhost()), "build", ".", "-o", "out.ll", "--runtime=core"],
                cwd=package, env=dict(os.environ, NLC_OPT_LEVEL="1"), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            return time.monotonic() - started

        timings = []
        with tempfile.TemporaryDirectory(prefix="nl-name-scope-") as temporary:
            for functions in (1000, 2000):
                package = pathlib.Path(temporary) / str(functions)
                generated = subprocess.run(
                    [sys.executable, str(ROOT / "scripts" / "gen-selfhost-bench.py"), str(package), "--functions", str(functions)],
                    cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(generated.returncode, 0, generated.stderr.decode(errors="replace"))
                build_time(package)  # warm process and file-system caches
                timings.append(statistics.median(build_time(package) for _ in range(3)))
        one_thousand, two_thousand = timings
        self.assertLessEqual(two_thousand, one_thousand * 4 + 0.5,
                             f"repeated-parameter name checking grew too quickly: 1k={one_thousand:.2f}s, 2k={two_thousand:.2f}s")


if __name__ == "__main__":
    unittest.main()
