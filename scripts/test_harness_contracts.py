"""Package-class protocol contracts shared by comparison and relocation."""

from pathlib import Path
import tempfile
import unittest

from test_harness import CLASSES, read_classification_table


class ClassificationContracts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name)
        self.root = self.parent / "repo"
        self.root.mkdir()
        (self.root / "package").mkdir()
        self.table = self.root / "classification.tsv"

    def test_existing_two_column_classes_remain_supported(self):
        for kind in CLASSES:
            with self.subTest(kind=kind):
                self.table.write_text(f"{kind}\tpackage\n")
                classes = read_classification_table(self.table, self.root)
                self.assertEqual(classes, {"package": kind})

    def test_invalid_or_ambiguous_package_records_are_rejected(self):
        for row in [
            "unknown\tpackage\n",
            "build\tpackage\nunsupported\tpackage\n",
            "build\tmissing-package\n",
            "unsupported\tpackage\tunexpected-column\n",
        ]:
            with self.subTest(row=row):
                self.table.write_text(row)
                with self.assertRaises(ValueError):
                    read_classification_table(self.table, self.root)


if __name__ == "__main__":
    unittest.main()
