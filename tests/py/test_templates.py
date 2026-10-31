"""Templates (tools/tmpl.py): contexts, escaping, size bounds, and a program that builds and runs them."""

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

from support import ROOT
from test_jobs import run_program
from support import selfhost

sys.path.insert(0, str(ROOT / "tools"))
import tmpl  # noqa: E402


def compile_template(source, structs="struct Row {\n    key: long\n    found: bool\n    name: Bytes max 16\n    note: Ascii max 8\n}\n"):
    with tempfile.TemporaryDirectory(prefix="nl-tpl-") as directory:
        (pathlib.Path(directory) / "main.nl").write_text(structs)
        (pathlib.Path(directory) / "t.tpl").write_text(source)
        tmpl.compile_package(directory)
        return (pathlib.Path(directory) / "templates.gen.nl").read_text()


class Generator(unittest.TestCase):
    def test_a_template_that_can_overflow_its_buffer_is_an_error(self):
        # 16 bytes of name, each up to 6 bytes escaped for HTML text: 96 + 7 literal bytes
        with self.assertRaises(tmpl.TemplateError) as caught:
            compile_template("html template t(row: Row) max 100\n<p>{row.name}</p>\n")
        self.assertIn("can write up to 103 bytes", str(caught.exception))
        compile_template("html template t(row: Row) max 105\n<p>{row.name}</p>\n")

    def test_a_hole_may_not_start_a_url(self):
        with self.assertRaises(tmpl.TemplateError) as caught:
            compile_template('html template t(row: Row) max 200\n<a href="{row.name}">x</a>\n')
        self.assertIn("javascript:", str(caught.exception))

    def test_holes_in_script_or_event_attributes_or_unquoted_values_are_errors(self):
        for body in ["<script>var x = {row.key};</script>", '<a onclick="{row.name}">x</a>', "<a title={row.name}>x</a>", "<a {row.name}>x</a>", "<!-- {row.name} -->"]:
            with self.assertRaises(tmpl.TemplateError, msg=body):
                compile_template(f"html template t(row: Row) max 2000\n{body}\n")

    def test_unknown_names_and_fields_and_filters_are_errors(self):
        for body in ["{nothing}", "{row.missing}", "{row}", "{row.key|upper}", "{row.name|money}", "{#if row.key}x{#end}", "{#if row.found}x"]:
            with self.assertRaises(tmpl.TemplateError, msg=body):
                compile_template(f"html template t(row: Row) max 2000\n{body}\n")

    def test_the_two_sides_of_an_if_must_leave_the_html_in_the_same_place(self):
        with self.assertRaises(tmpl.TemplateError):
            compile_template("html template t(row: Row) max 2000\n{#if row.found}<b class=\"{#else}<i>{#end}x\n")

    def test_non_ascii_text_is_refused(self):
        with self.assertRaises(tmpl.TemplateError):
            compile_template("html template t(row: Row) max 2000\n<p>café</p>\n")

    def test_struct_defaults_are_not_part_of_the_field_type(self):
        generated = compile_template("html template t(row: Row) max 400\n<p>{row.name}</p>\n",
                                     structs="struct Row {\n    key: long = 0L\n    name: Bytes max 16 = Bytes.empty()\n}\n")
        self.assertIn("tpl_html_text_bytes_16_400(out, row.name)", generated)

    def test_loops_over_lists_bound_the_output_by_the_count(self):
        # 3 rows of  <li>  +  16 bytes of name at up to 6 bytes each  +  </li>  =  4 + 96 + 5 = 105 per row, and 4 + 5 for the list
        generated = compile_template("html template t(items: list<Row, 3>) max 330\n<ul>{#for r in items}<li>{r.name}</li>{#end}</ul>\n")
        self.assertIn("for r in items {", generated)
        with self.assertRaises(tmpl.TemplateError) as caught:
            compile_template("html template t(items: list<Row, 3>) max 300\n<ul>{#for r in items}<li>{r.name}</li>{#end}</ul>\n")
        self.assertIn("can write up to 324 bytes", str(caught.exception))

    def test_loop_errors(self):
        for body in ["{#for r in row}x{#end}", "{#for r in items}{r}{#end}", "{#for r in items}{r.nothing}{#end}", "{#for r in items}x",
                     "{#for r in items}<b class=\"{#end}", "{#for r in nothing}x{#end}"]:
            with self.assertRaises(tmpl.TemplateError, msg=body):
                compile_template(f"html template t(row: Row, items: list<Row, 3>) max 2000\n{body}\n")

    def test_json_text_outside_quotes_is_quoted(self):
        generated = compile_template('json template t(row: Row) max 400\n{{"a":{row.name},"b":"x{row.name}"}}\n')
        self.assertIn("tpl_json_quoted_bytes_16_400", generated)
        self.assertIn("tpl_json_string_bytes_16_400", generated)


class Program(unittest.TestCase):
    def test_a_package_with_templates_builds_and_runs(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("templates")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        lines = ran.stdout.decode().split("\n")
        # the name is  a<b>&"c'\<space><newline>
        self.assertEqual(lines[0], "<h1>a&lt;b&gt;&amp;&quot;c&#39;\ ")
        self.assertEqual(lines[1], '</h1><a href="/item/42" title="a&lt;b&gt;&amp;&quot;c&#39;\ ')
        self.assertEqual(lines[2], '">item 42</a>')
        self.assertEqual(lines[3], "<p>$12.34</p>")
        self.assertEqual(lines[4], "<h1></h1><a href=\"/item/-7\" title=\"\">item -7</a>")
        self.assertEqual(lines[5], "<p>gone</p>")
        self.assertEqual(lines[6], r'''{"id":42,"name":"a<b>&\"c'\\ \n","note":"a a<b>&\"c'\\ \n b","ok":true}''')
        self.assertEqual(lines[7], r'''<ul><li class="n42">a&lt;b&gt;&amp;&quot;c&#39;\ ''')
        self.assertEqual(lines[8], '</li><li class="n8"></li></ul>')


if __name__ == "__main__":
    unittest.main()
