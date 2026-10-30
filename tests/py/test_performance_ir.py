"""Benchmark loops keep the stack base and top hot after optimisation (ported from selfhost_performance_ir.rs).

The self-hosted compiler's IR for four benchmark pairs is optimised with clang -O3; every loop that indexes a
list must contain no per-iteration region reservation and no reload of the context base."""

import pathlib
import re
import shutil
import subprocess
import unittest

from support import ROOT, compile_package, temporary_package

LABEL = re.compile(r"^[A-Za-z0-9_.$]+$")


def metadata_id(line):
    if "=" not in line:
        return None
    left = line.strip().split("=", 1)[0].strip()
    if left.startswith("!") and left[1:].isdigit():
        return left[1:]
    return None


def metadata_rhs(line):
    return "".join(line.strip().split("=", 1)[1].split())


def tbaa_tags(ir):
    context_type = program_type = None
    definitions = {}
    for line in ir.splitlines():
        identifier = metadata_id(line)
        if identifier is not None:
            rhs = metadata_rhs(line)
            if '!{!"contextbase"' in rhs:
                context_type = identifier
            if '!{!"programstorage"' in rhs:
                program_type = identifier
            definitions[identifier] = rhs

    def access_tag(type_id):
        assert type_id is not None, "optimized IR retains the TBAA type node"
        expected = f"!{{!{type_id},!{type_id},i640}}"
        for identifier, rhs in definitions.items():
            if rhs == expected:
                return identifier
        raise AssertionError("optimized IR retains the scalar TBAA access tag")

    return access_tag(context_type), access_tag(program_type)


def branch_targets(instruction):
    return re.findall(r"label %([A-Za-z0-9_.$]+)", instruction)


def parse_functions(ir):
    functions = []
    current = None
    block = None
    for line in ir.splitlines():
        trimmed = line.strip()
        if trimmed.startswith("define "):
            name = trimmed.split("@", 1)[1].split("(", 1)[0].split(" ", 1)[0] if "@" in trimmed else ""
            current = {"name": name, "blocks": []}
            block = None
            continue
        if current is None:
            continue
        if trimmed == "}":
            if block is not None:
                current["blocks"].append(block)
            functions.append(current)
            current = None
            block = None
            continue
        if line and not line[0].isspace() and ":" in trimmed:
            label = trimmed.split(":", 1)[0]
            if label and LABEL.match(label):
                if block is not None:
                    current["blocks"].append(block)
                block = {"label": label, "instructions": [], "successors": []}
                continue
        if block is not None:
            if trimmed.startswith(("br ", "switch ")):
                for target in branch_targets(trimmed):
                    if target not in block["successors"]:
                        block["successors"].append(target)
            if trimmed and not trimmed.startswith(";"):
                block["instructions"].append(trimmed)
    return functions


def natural_loops(function):
    blocks = function["blocks"]
    if not blocks:
        return []
    labels = {block["label"] for block in blocks}
    entry = blocks[0]["label"]
    predecessors = {}
    for block in blocks:
        for target in block["successors"]:
            if target in labels:
                predecessors.setdefault(target, []).append(block["label"])
    dominators = {label: ({entry} if label == entry else set(labels)) for label in labels}
    changed = True
    while changed:
        changed = False
        for label in labels:
            if label == entry:
                continue
            preds = predecessors.get(label, [])
            new = set(dominators[preds[0]]) if preds else set()
            for pred in preds[1:]:
                new &= dominators[pred]
            new.add(label)
            if dominators[label] != new:
                dominators[label] = new
                changed = True
    loops = []
    for block in blocks:
        source = block["label"]
        for header in block["successors"]:
            if header not in labels or header not in dominators[source]:
                continue
            body = {header, source}
            pending = [source]
            while pending:
                node = pending.pop()
                for pred in predecessors.get(node, []):
                    if pred not in body:
                        body.add(pred)
                        if pred != header:
                            pending.append(pred)
            loops.append(body)
    return loops


class PerformanceIr(unittest.TestCase):
    def assert_hot_loop_ir(self, pair, ir, context_tag, program_tag):
        checked = 0
        for function in parse_functions(ir):
            if not function["name"].startswith("nl_fn_"):
                continue
            by_label = {block["label"]: block for block in function["blocks"]}
            for loop in natural_loops(function):
                instructions = [line for label in loop if label in by_label for line in by_label[label]["instructions"]]
                if not any("%coll.index." in line for line in instructions):
                    continue
                checked += 1
                for line in instructions:
                    self.assertFalse("@nl_context_reservation_bytes" in line or "@nl_stack_grow" in line or "%nl.scope.end." in line,
                                     f"{pair} {function['name']} hot loop contains per-iteration region reservation in:\n{line}")
                if pair != "tight_list":
                    self.assertTrue(any(line.startswith("store ") and f"!tbaa !{program_tag}" in line for line in instructions),
                                    f"{pair} {function['name']} hot loop has no typed program-store marker")
                for label in loop:
                    if label not in by_label:
                        continue
                    for line in by_label[label]["instructions"]:
                        reload = "load ptr" in line and f"!tbaa !{context_tag}" in line
                        self.assertFalse(reload, f"{pair} {function['name']} hot loop reloads the context base in block {label}:\n{line}")
        self.assertGreater(checked, 0, f"{pair} has no optimized user loop with a %coll.index marker")

    def assert_raw_alias_tags(self, pair, ir):
        self.assertIn('!9001 = !{!"context base", !9000}', ir)
        self.assertIn('!9004 = !{!"program storage", !9000}', ir)
        function = ""
        tagged_base_loads = 0
        for line in ir.splitlines():
            if line.strip().startswith("define "):
                function = line.split("@", 1)[1].split("(", 1)[0].split(" ", 1)[0] if "@" in line else ""
            if "load ptr" in line and "ptr %sys.ptr." in line and function == "nl_context_current_base":
                self.assertIn("!tbaa !9002", line, f"{pair} context-base load lost its TBAA marker: {line}")
                tagged_base_loads += 1
            if line.lstrip().startswith("store ") and "ptr %sys.ptr." in line:
                self.assertNotIn("!tbaa !9003", line, f"{pair} raw sys/context store was tagged as program storage: {line}")
        self.assertEqual(tagged_base_loads, 1, f"{pair} should tag only nl_context_current_base's header load")
        self.assertTrue(any(line.lstrip().startswith("store ") and "!tbaa !9003" in line for line in ir.splitlines()),
                        f"{pair} emitted no typed program-storage store marker")

    def test_selfhost_benchmark_loops_keep_base_and_top_hot(self):
        for pair in ("increment_heavy", "struct_update", "tight_list", "calls"):
            with self.subTest(pair), temporary_package({}) as directory:
                shutil.copy(ROOT / "bench" / "vs-rust" / pair / "main.nl", directory / "main.nl")
                built = compile_package(directory, output="module.ll")
                self.assertEqual(built.returncode, 0, f"build {pair} with selfhost: " + built.stderr.decode(errors="replace"))
                self.assert_raw_alias_tags(pair, (directory / "module.ll").read_text())
                optimized = subprocess.run(["clang", "-O3", "-S", "-emit-llvm", "module.ll", "-o", "module.opt.ll"],
                                           cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(optimized.returncode, 0, f"optimize {pair} IR: " + optimized.stderr.decode(errors="replace"))
                ir = (directory / "module.opt.ll").read_text()
                context_tag, program_tag = tbaa_tags(ir)
                self.assert_hot_loop_ir(pair, ir, context_tag, program_tag)


if __name__ == "__main__":
    unittest.main()
