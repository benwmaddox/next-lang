#!/usr/bin/env python3
"""Compares the template compiler written in next-lang (tools/gen/tmpl) with the Python prototype (tools/tmpl.py).

    python3 tools/gen/compare_tmpl.py <path to the built tmpl binary>

For each case (a struct file and a template file in a temporary package) both tools run; the exit status, the error
text and the generated templates.gen.nl must be identical. Real packages (apps/campfire, tests/py/programs/templates)
are compared too.
"""

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
ROW = "struct Row {\n    key: long\n    found: bool\n    name: Bytes max 16\n    note: Ascii max 8\n}\n"
H = "html template t(row: Row) max 2000\n"
L = "html template t(row: Row, items: list<Row, 3>) max 2000\n"
CASES = [
    ("overflow", ROW, "html template t(row: Row) max 100\n<p>{row.name}</p>\n"),
    ("exact", ROW, "html template t(row: Row) max 105\n<p>{row.name}</p>\n"),
    ("url-start", ROW, 'html template t(row: Row) max 200\n<a href="{row.name}">x</a>\n'),
    ("url-ok", ROW, 'html template t(row: Row) max 400\n<a href="/x/{row.name}?k={row.key}">x</a><a href="https://a/{row.note}">y</a>\n'),
    ("script", ROW, H + "<script>var x = {row.key};</script>\n"),
    ("onclick", ROW, H + '<a onclick="{row.name}">x</a>\n'),
    ("unquoted", ROW, H + "<a title={row.name}>x</a>\n"),
    ("between-attrs", ROW, H + "<a {row.name}>x</a>\n"),
    ("comment", ROW, H + "<!-- {row.name} -->\n"),
    ("nothing", ROW, H + "{nothing}\n"),
    ("missing-field", ROW, H + "{row.missing}\n"),
    ("struct-hole", ROW, H + "{row}\n"),
    ("bad-filter", ROW, H + "{row.key|upper}\n"),
    ("money-text", ROW, H + "{row.name|money}\n"),
    ("if-long", ROW, H + "{#if row.key}x{#end}\n"),
    ("if-no-end", ROW, H + "{#if row.found}x\n"),
    ("if-sides", ROW, H + '{#if row.found}<b class="{#else}<i>{#end}x\n'),
    ("non-ascii", ROW, H + "<p>café</p>\n"),
    ("defaults", "struct Row {\n    key: long = 0L\n    name: Bytes max 16 = Bytes.empty()\n}\n", "html template t(row: Row) max 400\n<p>{row.name}</p>\n"),
    ("loop", ROW, "html template t(items: list<Row, 3>) max 330\n<ul>{#for r in items}<li>{r.name}</li>{#end}</ul>\n"),
    ("loop-overflow", ROW, "html template t(items: list<Row, 3>) max 300\n<ul>{#for r in items}<li>{r.name}</li>{#end}</ul>\n"),
    ("loop-not-list", ROW, L + "{#for r in row}x{#end}\n"),
    ("loop-struct-hole", ROW, L + "{#for r in items}{r}{#end}\n"),
    ("loop-field", ROW, L + "{#for r in items}{r.nothing}{#end}\n"),
    ("loop-no-end", ROW, L + "{#for r in items}x\n"),
    ("loop-open-tag", ROW, L + '{#for r in items}<b class="{#end}\n'),
    ("loop-unknown", ROW, L + "{#for r in nothing}x{#end}\n"),
    ("json", ROW, 'json template t(row: Row) max 400\n{{"a":{row.name},"b":"x{row.name}","c":{row.key},"d":{row.found},"e":{row.note}}}\n'),
    ("json-text-ctl", ROW, 'json template t(row: Row) max 400\n{{"a":"\\n{row.name}\\""}}\n'),
    ("money-raw", ROW, "html template t(row: Row) max 600\n<p>${row.key|money} {row.name|raw} {row.note|raw}</p>\n"),
    ("raw-in-attr", ROW, 'html template t(row: Row) max 600\n<p class="{row.name|raw}">x</p>\n'),
    ("int-param", ROW, "html template t(n: int, ok: bool, s: Ascii max 5) max 300\n{n} {ok} {s}\n"),
    ("else", ROW, H + "{#if row.found}yes{#else}no{#end}!\n"),
    ("empty-else", ROW, H + "{#if row.found}yes{#else}{#end}!\n"),
    ("nested", ROW, L + "{#for r in items}{#if r.found}<b>{r.name}</b>{#else}<i>{r.note}</i>{#end}{#end}\n"),
    ("long-literal", ROW, "html template t(row: Row) max 2000\n" + "abcdefghij" * 40 + '"quoted"\\ back\t tab\n'),
    ("two-templates", ROW, "// comment\n\nhtml template a(row: Row) max 100\nhi {row.key}\n\nhtml template b(row: Row) max 100\n\nyo\n\n"),
    ("duplicate", ROW, "html template a(row: Row) max 100\nx\nhtml template a(row: Row) max 100\ny\n"),
    ("stray-text", ROW, "stray\nhtml template a(row: Row) max 100\nx\n"),
    ("brace-error", ROW, H + "a { b\n"),
    ("unknown-tag", ROW, H + "{#frob x}\n"),
    ("literal-braces", ROW, H + "{{ and }} and a } too\n"),
    ("script-literal", ROW, H + "<script>var a = 1; if (a) { b(); }</script><p>{row.key}</p>\n"),
    ("quoted-attr", ROW, H + "<input value='{row.name}' title=\"{row.note}\" data-x=\"{row.key}\">\n"),
    ("no-trailing-newline", ROW, "html template t(row: Row) max 100\nplain"),
    ("empty-body", ROW, "html template t(row: Row) max 100\n"),
    ("tabs-header", ROW, "html\ttemplate\tt( row: Row ,  n: long )  max\t100 \nx {n}\n"),
    ("html-state", ROW, H + "<b>x</b><i class=a>y</i><!-- c --><p a=\"1\">{row.key}</p>\n"),
]


def run(tool, directory):
    result = subprocess.run(tool, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=directory.parent)
    generated = directory / "templates.gen.nl"
    return result.returncode, result.stderr.decode(errors="replace"), generated.read_text() if generated.exists() else None


def compare(name, make, tool_python, tool_native, failures):
    with tempfile.TemporaryDirectory(prefix="nl-cmp-") as base:
        results = []
        for label, tool in (("py", tool_python), ("nl", tool_native)):
            directory = pathlib.Path(base) / label
            directory.mkdir()
            make(directory)
            results.append(run(tool + ["pkg" if False else label], directory))
        python_result, native_result = results
        # error text names the directory it was given; make them comparable
        normalise = lambda text: text.replace("py/", "X/").replace("nl/", "X/")
        py = (python_result[0], normalise(python_result[1]), python_result[2])
        nl = (native_result[0], normalise(native_result[1]), native_result[2])
        if py != nl:
            failures.append(name)
            print(f"MISMATCH {name}")
            print(f"  python: exit {py[0]} {py[1].strip()}")
            print(f"  native: exit {nl[0]} {nl[1].strip()}")
            if py[2] != nl[2] and py[2] is not None and nl[2] is not None:
                import difflib
                for line in list(difflib.unified_diff(py[2].splitlines(), nl[2].splitlines(), "python", "native", lineterm=""))[:20]:
                    print("   ", line)
        else:
            print(f"same     {name}")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    native = [str(pathlib.Path(sys.argv[1]).resolve())]
    python = [sys.executable, str(ROOT / "tools" / "tmpl.py")]
    failures = []
    for name, structs, source in CASES:
        def make(directory, structs=structs, source=source):
            (directory / "main.nl").write_text(structs)
            (directory / "t.tpl").write_text(source)
        compare(name, make, python, native, failures)
    for package in ("apps/campfire", "tests/py/programs/templates"):
        def make(directory, package=package):
            for item in (ROOT / package).iterdir():
                if item.suffix in (".nl", ".tpl") and item.name != "templates.gen.nl":
                    shutil.copy(item, directory / item.name)
        compare(package, make, python, native, failures)
    print(f"{len(failures)} different" if failures else "all the same")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
