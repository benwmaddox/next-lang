"""Shared selectors and worker-count policy for the selfhost test harnesses."""

from __future__ import annotations

import fnmatch
import os
from pathlib import Path
import subprocess


CLASSES = ("build", "diagnose", "rejects", "unsupported")


def worker_count() -> int:
    configured = os.environ.get("NLC_TEST_JOBS")
    if configured is not None:
        try:
            jobs = int(configured)
        except ValueError as error:
            raise ValueError("NLC_TEST_JOBS must be a positive integer") from error
        if jobs < 1:
            raise ValueError("NLC_TEST_JOBS must be a positive integer")
        return jobs
    return max(1, (os.cpu_count() or 1) // 2)


def add_filter_arguments(parser) -> None:
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="GLOB",
        help="include package paths matching this glob (may be repeated)",
    )
    parser.add_argument("--class", dest="package_class", choices=CLASSES)
    parser.add_argument(
        "--changed",
        nargs="?",
        const="HEAD",
        metavar="REV",
        help="include packages changed since REV (default: HEAD)",
    )


def changed_paths(root: Path, revision: str | None) -> set[str] | None:
    if revision is None:
        return None
    changed: set[str] = set()
    for command in (
        ["git", "diff", "--name-only", "--diff-filter=ACMRDT", revision, "--"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        result = subprocess.run(
            command,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            text=True,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or "git returned a failure status"
            raise ValueError(f"cannot list files changed since {revision}: {detail}")
        changed.update(line for line in result.stdout.splitlines() if line)
    return changed


def select_packages(
    packages: list[str],
    classifications: dict[str, str],
    patterns: list[str],
    package_class: str | None,
    changed: set[str] | None,
) -> list[str]:
    selected: list[str] = []
    for package in packages:
        if patterns and not any(fnmatch.fnmatchcase(package, pattern) for pattern in patterns):
            continue
        if package_class is not None and classifications.get(package) != package_class:
            continue
        if changed is not None and not any(
            path == package or path.startswith(package.rstrip("/") + "/") for path in changed
        ):
            continue
        selected.append(package)
    return selected


def filter_label(patterns: list[str], package_class: str | None, revision: str | None) -> str:
    if not (patterns or package_class or revision is not None):
        return "all packages"
    parts: list[str] = []
    if patterns:
        parts.append("only=" + ",".join(patterns))
    if package_class:
        parts.append("class=" + package_class)
    if revision is not None:
        parts.append("changed=" + revision)
    return " ".join(parts)
