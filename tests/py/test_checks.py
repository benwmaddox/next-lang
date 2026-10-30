"""Ports of the small selfhost checks that were Rust integration tests."""

import resource
import subprocess
import sys
import unittest

from support import ROOT, compile_package, run_script, selfhost, temporary_package, verify_ir


class Checks(unittest.TestCase):
    def test_forced_selfhost_relocations_match_ordinary_runs(self):
        result = run_script("check-selfhost-relocation.py")
        self.assertEqual(result.returncode, 0, result.stdout.decode() + result.stderr.decode())

    def test_c_runtime_io_fixtures_match(self):
        result = run_script("check-selfhost-c-io.py", "--compiler", str(selfhost()))
        self.assertEqual(result.returncode, 0, result.stdout.decode() + result.stderr.decode())

    def test_compiler_peak_memory_on_its_own_source_stays_within_budget(self):
        # Real memory, not the worst-case bound: the compiler's peak resident set on its own source.
        budget_kib = 512 * 1024
        output = ROOT / f".memory-check-{__import__('os').getpid()}.ll"
        script = ("import resource, subprocess, sys\n"
                  "subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
                  "print(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)\n")
        try:
            measured = subprocess.run(
                [sys.executable, "-c", script, str(selfhost()), "build", "selfhost", "-o", output.name, "--runtime=core"],
                cwd=ROOT, stdout=subprocess.PIPE, check=True)
        finally:
            output.unlink(missing_ok=True)
        peak = int(measured.stdout.decode().strip())
        self.assertLessEqual(peak, budget_kib, f"peak resident set {peak} KiB exceeds {budget_kib} KiB")

    def test_type_table_access_and_struct_classification_stay_behind_the_interface(self):
        # The compiler is split across selfhost/compiler_*.nl; the audit reads them in name order.
        paths = sorted((ROOT / "selfhost").glob("compiler_*.nl"), key=lambda p: p.name)
        source = "".join(path.read_text() for path in paths)
        in_type_module = False
        begins = ends = 0
        for number, line in enumerate(source.splitlines(), 1):
            if "// TYPE MODULE BEGIN" in line:
                self.assertFalse(in_type_module, f"nested type module at line {number}")
                in_type_module = True
                begins += 1
                continue
            if "// TYPE MODULE END" in line:
                self.assertTrue(in_type_module, f"type module ends before it begins at line {number}")
                in_type_module = False
                ends += 1
                continue
            code = line.split("//")[0]
            self.assertNotIn("struct_types[", code, f"direct struct table index at line {number}")
            if not in_type_module:
                self.assertNotIn("type_records[", code, f"type table index outside its module at line {number}")
            compact = "".join(code.split())
            start = compact.find("TY_STRUCT_BASE")
            while start >= 0:
                end = start + len("TY_STRUCT_BASE")
                before = compact[start - 1] if start > 0 else ""
                after = compact[end] if end < len(compact) else ""
                self.assertFalse(before in "<>=!" and before != "" or after in "<>=" and after != "",
                                 f"TY_STRUCT_BASE comparison at line {number}")
                start = compact.find("TY_STRUCT_BASE", end)
        self.assertEqual(begins, 1, "expected one type-module start marker")
        self.assertEqual(ends, 1, "expected one type-module end marker")
        self.assertFalse(in_type_module, "type module is not closed")

    def test_shared_constant_dependencies_are_memoized_and_lower_to_immediates(self):
        # Each level uses its predecessor twice. Without declaration memoization this small,
        # forward-referencing graph needs over a trillion visits.
        lines = ["const C0: long = 3141592653L"]
        for level in range(1, 41):
            lines.append(f"const C{level}: long = C{level - 1} - C{level - 1} + 3141592653L")
        source = "\n".join(reversed(lines)) + "\nfn answer() -> long { C40 }\nfn main() { print(answer()) }\n"
        with temporary_package({"main.nl": source}) as directory:
            compiled = compile_package(directory, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stderr.decode())
            ir = (directory / "out.ll").read_text()
            self.assertIn("ret i64 3141592653", ir, "the constant-returning function must return an immediate value")
            verified = verify_ir(directory)
            self.assertEqual(verified.returncode, 0, verified.stderr.decode())


if __name__ == "__main__":
    unittest.main()
