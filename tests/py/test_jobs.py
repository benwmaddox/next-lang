"""`spawn` starts functions on their own threads and the program waits for them (programs in tests/py/programs)."""

import os
import subprocess
import unittest

from support import ROOT


def run_program(package):
    """Build and run tests/py/programs/<package> with the driver script; returns the CompletedProcess."""
    if os.name == "nt":
        command = ["pwsh", "-NoProfile", "-File", str(ROOT / "scripts" / "nlc.ps1"), "run", f"tests/py/programs/{package}"]
    else:
        command = [str(ROOT / "scripts" / "nlc"), "run", f"tests/py/programs/{package}"]
    env = dict(os.environ)
    return subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)


class Jobs(unittest.TestCase):
    def test_spawned_functions_run_and_the_program_waits_for_them(self):
        from support import selfhost
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        for attempt in range(3):
            ran = run_program("jobs")
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            # the order of lines depends on which thread finishes first
            self.assertEqual(sorted(ran.stdout.decode().split()), sorted(["0", "499501", "1999002", "4498503"]), f"attempt {attempt}")


if __name__ == "__main__":
    unittest.main()
