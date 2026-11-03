"""Pool owners: ids name their pool, several pools and pools in structs (selfhost/pool_owners.nl)."""

import os
import subprocess
import unittest

from support import ROOT, selfhost

POSITIVE = ["pools", "pools_ids", "pools_set", "pool_fields", "pool_owners", "pool_nested_call", "pool_owner_flow", "pool_index", "list_of_arrays_foreach", "enum_list_literals", "nested_foreach", "nested_foreach_probes", "map_rich", "map_ids", "map_foreach", "sort_lib", "pool_readonly_params", "pool_results", "const_images", "text_arrays", "text_arena", "text_window"]


def nlc(*args):
    env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
    return subprocess.run(["bash", str(ROOT / "scripts" / "nlc"), *args], cwd=ROOT, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600, check=False)


class PoolOwners(unittest.TestCase):
    def test_programs_run_with_expected_output(self):
        for name in POSITIVE:
            with self.subTest(name):
                result = nlc("run", f"tests/c_runtime/{name}")
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                expected = (ROOT / "tests" / "c_runtime" / name / "expected.stdout").read_bytes()
                self.assertEqual(result.stdout, expected)

    def test_mixing_pools_is_a_build_error(self):
        errors = ROOT / "tests" / "pool_owner_errors"
        for directory in sorted(errors.iterdir()):
            with self.subTest(directory.name):
                result = nlc("check", f"tests/pool_owner_errors/{directory.name}")
                self.assertEqual(result.returncode, 2, result.stdout.decode() + result.stderr.decode())
                self.assertEqual(result.stderr, (directory / "expected.stderr").read_bytes())


if __name__ == "__main__":
    unittest.main()
