#!/usr/bin/env python3
"""Template compiler (prototype): turns the *.tpl files of a package into next-lang functions.

    python3 tools/tmpl.py <package-dir>      writes <package-dir>/templates.gen.nl

A template is straight-line code that appends to a bounded `Bytes`, built when the program is built:

    html template page(row: Row, taxed: long) max 512
    <h1>{row.name}</h1><p>item {row.key}</p>
    {#if row.found}<p>price ${taxed|money}</p>{#else}<p>gone</p>{#end}

    json template item(row: Row) max 512
    {{"id":{row.key},"name":{row.name}}}

- The header names the kind (`html` or `json`), the function (`render_<name>`), its parameters and the size of the buffer
  it appends to. Parameters are numbers, bools, `Bytes max N`, `Ascii max N` or structs declared in the package.
- `{path}` writes a value (`row.name`, `taxed`): numbers as digits, bools as true/false, bytes and text escaped for the
  place they are in (HTML text, a quoted HTML attribute, a URL attribute, a JSON string). In JSON a value outside quotes
  is written as a JSON value: text becomes a quoted string. `{path|money}` writes cents as dollars.
- `{#if path}...{#else}...{#end}` chooses by a bool. `{{` and `}}` are literal braces.
- The largest output of a template is worked out when it is built (escaping can multiply a byte by up to six); a template
  that could overflow its buffer, a hole in a place that cannot hold one (a script, an unquoted attribute, the start of
  a URL) or text that is not ASCII is an error.
"""

import os
import re
import sys

ASCII_LIMIT = 128  # longest string literal one append writes


class TemplateError(Exception):
    pass


# ---------------------------------------------------------------- types and structs

def parse_type(text):
    text = text.strip()
    if text in ("long", "int", "bool"):
        return (text, 0)
    match = re.fullmatch(r"(Bytes|Ascii)\s+max\s+(\d+)", text)
    if match:
        return (match.group(1).lower(), int(match.group(2)))
    match = re.fullmatch(r"list\s*<\s*(\w+)\s*,\s*(\d+)\s*>", text)
    if match:
        return ("list", match.group(1), int(match.group(2)))
    return ("struct", text)


def read_structs(directory):
    structs = {}
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".nl"):
            continue
        text = open(os.path.join(directory, name), encoding="utf-8").read()
        text = re.sub(r"//[^\n]*", "", text)
        for match in re.finditer(r"\bstruct\s+(\w+)\s*\{([^}]*)\}", text):
            fields = {}
            for line in match.group(2).splitlines():
                line = line.strip()
                if not line:
                    continue
                field = re.fullmatch(r"(\w+)\s*:\s*(.+?)\s*,?", line)
                if field:
                    fields[field.group(1)] = parse_type(field.group(2))
            structs[match.group(1)] = fields
    return structs


# ---------------------------------------------------------------- parsing a template body

class Lit:
    def __init__(self, text):
        self.text = text


class Hole:
    def __init__(self, path, type_, filter_, context, line):
        self.path, self.type, self.filter, self.context, self.line = path, type_, filter_, context, line


class If:
    def __init__(self, path, then, other, line):
        self.path, self.then, self.other, self.line = path, then, other, line


class For:
    def __init__(self, name, path, element, count, body, line):
        self.name, self.path, self.element, self.count, self.body, self.line = name, path, element, count, body, line


class Template:
    def __init__(self, kind, name, params, size, body, line):
        self.kind, self.name, self.params, self.size, self.body, self.line = kind, name, params, size, body, line


HEADER = re.compile(r"^(html|json)\s+template\s+(\w+)\s*\((.*)\)\s+max\s+(\d+)\s*$")


def split_params(text):
    params = []
    depth = 0
    current = ""
    for char in text:
        if char == "<":
            depth += 1
        elif char == ">":
            depth -= 1
        if char == "," and depth == 0:
            params.append(current)
            current = ""
        else:
            current += char
    if current.strip():
        params.append(current)
    result = []
    for item in params:
        name, _, type_ = item.partition(":")
        result.append((name.strip(), type_.strip()))
    return result


def read_templates(path):
    templates = []
    lines = open(path, encoding="utf-8").read().split("\n")
    current = None
    body = []

    def finish():
        if current is not None:
            text = "\n".join(body)
            if text.endswith("\n"):
                text = text[:-1]
            templates.append(Template(current[0], current[1], current[2], current[3], text, current[4]))

    for number, line in enumerate(lines, 1):
        header = HEADER.match(line)
        if header:
            finish()
            body = []
            current = (header.group(1), header.group(2), split_params(header.group(3)), int(header.group(4)), number)
        elif current is not None:
            body.append(line)
        elif line.strip() and not line.startswith("//"):
            raise TemplateError(f"{path}:{number}: expected a template header, e.g. `html template page(row: Row) max 512`")
    finish()
    # a trailing newline of the whole file is not part of the last body
    return templates


# ---------------------------------------------------------------- contexts

URL_ATTRIBUTES = {"href", "src", "action", "formaction", "poster", "cite", "data"}


class HtmlState:
    def __init__(self):
        self.mode = "text"   # text, tag, dq, sq, unq, comment, raw
        self.tag = ""
        self.attr = ""
        self.value = ""      # literal text seen so far in the current attribute value
        self.raw_until = ""

    def copy(self):
        other = HtmlState()
        other.__dict__.update(self.__dict__)
        return other

    def key(self):
        if self.mode == "text":
            return ("text",)   # what was seen of earlier tags does not matter once back in the text
        return (self.mode, self.tag, self.attr, self.value, self.raw_until)

    def feed(self, text):
        index = 0
        while index < len(text):
            char = text[index]
            rest = text[index:]
            if self.mode == "text":
                if char == "<" and re.match(r"<(!--)", rest):
                    self.mode = "comment"
                    index += 4
                    continue
                if char == "<" and re.match(r"</?[A-Za-z]", rest):
                    match = re.match(r"<(/?)([A-Za-z][A-Za-z0-9-]*)", rest)
                    self.mode = "tag"
                    self.tag = match.group(2).lower()
                    self.closing = bool(match.group(1))
                    self.attr = ""
                    index += len(match.group(0))
                    continue
            elif self.mode == "comment":
                if rest.startswith("-->"):
                    self.mode = "text"
                    index += 3
                    continue
            elif self.mode == "raw":
                if rest.lower().startswith(self.raw_until):
                    self.mode = "tag"
                    self.tag = self.raw_until[2:]
                    self.closing = True
                    self.attr = ""
                    index += len(self.raw_until)
                    continue
            elif self.mode == "tag":
                if char == ">":
                    if self.tag in ("script", "style") and not getattr(self, "closing", False):
                        self.mode = "raw"
                        self.raw_until = "</" + self.tag
                    else:
                        self.mode = "text"
                elif char == "=":
                    pass
                elif char in "\"'":
                    self.mode = "dq" if char == '"' else "sq"
                    self.value = ""
                elif re.match(r"[A-Za-z]", char):
                    match = re.match(r"[A-Za-z][A-Za-z0-9_:-]*", rest)
                    self.attr = match.group(0).lower()
                    index += len(match.group(0))
                    # an unquoted value: name=value
                    after = text[index:index + 2]
                    if after[:1] == "=" and after[1:2] not in ('"', "'", ""):
                        self.mode = "unq"
                    continue
            elif self.mode in ("dq", "sq"):
                if (self.mode == "dq" and char == '"') or (self.mode == "sq" and char == "'"):
                    self.mode = "tag"
                else:
                    self.value += char
            elif self.mode == "unq":
                if char in " \t\n>":
                    self.mode = "text" if char == ">" else "tag"
            index += 1


def html_context(state, where):
    if state.mode == "text":
        return "html_text"
    if state.mode in ("dq", "sq"):
        if state.attr in URL_ATTRIBUTES:
            if not (state.value.startswith("/") or state.value.startswith("http://") or state.value.startswith("https://") or state.value.startswith("#")):
                raise TemplateError(f"{where}: a hole may not start a `{state.attr}` address (it could write `javascript:`); begin the address with `/` or `https://`")
            return "html_url"
        if state.attr.startswith("on") or state.attr == "style":
            raise TemplateError(f"{where}: a hole in `{state.attr}` could run script; build it in the program instead")
        return "html_attr"
    if state.mode == "raw":
        raise TemplateError(f"{where}: a hole inside <{state.tag}> could write script or style; not allowed")
    if state.mode == "comment":
        raise TemplateError(f"{where}: a hole inside an HTML comment")
    if state.mode == "unq":
        raise TemplateError(f"{where}: put the attribute value in quotes before a hole")
    raise TemplateError(f"{where}: a hole between a tag's attributes; put it inside a quoted value or in the text")


class JsonState:
    def __init__(self):
        self.in_string = False
        self.escaped = False

    def copy(self):
        other = JsonState()
        other.__dict__.update(self.__dict__)
        return other

    def key(self):
        return (self.in_string, self.escaped)

    def feed(self, text):
        for char in text:
            if self.in_string:
                if self.escaped:
                    self.escaped = False
                elif char == "\\":
                    self.escaped = True
                elif char == '"':
                    self.in_string = False
            elif char == '"':
                self.in_string = True


# ---------------------------------------------------------------- building the tree

def parse_body(template, structs, path):
    params = {name: parse_type(type_) for name, type_ in template.params}
    loop_scopes = []    # loop variable name -> struct type, innermost last
    where_base = f"{path}:{template.line}"
    state = HtmlState() if template.kind == "html" else JsonState()
    text = template.body
    position = 0

    def resolve(expression, line):
        parts = expression.split(".")
        type_ = None
        for scope in reversed(loop_scopes):
            if parts[0] in scope:
                type_ = ("struct", scope[parts[0]])
                break
        if type_ is None:
            if parts[0] not in params:
                raise TemplateError(f"{path}:{line}: `{parts[0]}` is not a parameter of template {template.name}")
            type_ = params[parts[0]]
        for field in parts[1:]:
            if type_[0] != "struct" or type_[1] not in structs or field not in structs[type_[1]]:
                raise TemplateError(f"{path}:{line}: `{expression}` names no field `{field}`")
            type_ = structs[type_[1]][field]
        if type_[0] == "struct":
            raise TemplateError(f"{path}:{line}: `{expression}` is a struct; name one of its fields")
        if type_[0] == "list":
            raise TemplateError(f"{path}:{line}: `{expression}` is a list; loop over it with {{#for item in {expression}}}")
        return type_

    def resolve_list(expression, line):
        parts = expression.split(".")
        type_ = params.get(parts[0])
        for field in parts[1:]:
            if type_ is None or type_[0] != "struct" or type_[1] not in structs or field not in structs[type_[1]]:
                raise TemplateError(f"{path}:{line}: `{expression}` names no field `{field}`")
            type_ = structs[type_[1]][field]
        if type_ is None or type_[0] != "list":
            raise TemplateError(f"{path}:{line}: `{{#for}}` needs a list<Row, N>, and `{expression}` is not one")
        if type_[1] not in structs:
            raise TemplateError(f"{path}:{line}: the list's element type `{type_[1]}` is not a struct of the package")
        return type_

    def line_at(offset):
        return template.line + 1 + text.count("\n", 0, offset)

    def parse_nodes(stop_tags):
        """Parse until one of the stop tags ({#else} or {#end}); returns (nodes, tag found)."""
        nonlocal position
        nodes = []
        literal = ""

        def flush():
            nonlocal literal
            if literal:
                nodes.append(Lit(literal))
                state.feed(literal)
                literal = ""

        while position < len(text):
            if text.startswith("{{", position):
                literal += "{"
                position += 2
            elif text.startswith("}}", position):
                literal += "}"
                position += 2
            elif text[position] == "{":
                end = text.find("}", position)
                if end < 0:
                    raise TemplateError(f"{path}:{line_at(position)}: a `{{` with no closing `}}`; write `{{{{` for a brace")
                inside = text[position + 1:end].strip()
                line = line_at(position)
                if inside.startswith("#"):
                    word = inside.split()
                    if word[0] in stop_tags:
                        flush()
                        position = end + 1
                        return nodes, word[0]
                    if word[0] == "#for" and len(word) == 4 and word[2] == "in":
                        flush()
                        position = end + 1
                        list_type = resolve_list(word[3], line)
                        before = state.copy()
                        loop_scopes.append({word[1]: list_type[1]})
                        body, tag = parse_nodes({"#end"})
                        loop_scopes.pop()
                        if tag != "#end":
                            raise TemplateError(f"{path}:{line}: `{{#for}}` has no `{{#end}}`")
                        if state.key() != before.key():
                            raise TemplateError(f"{path}:{line}: the body of this `{{#for}}` leaves the {template.kind} in a different place than it found it (an open tag or string); close it in every round")
                        nodes.append(For(word[1], word[3], list_type[1], list_type[2], body, line))
                    elif word[0] == "#if" and len(word) == 2:
                        flush()
                        position = end + 1
                        type_ = resolve(word[1], line)
                        if type_[0] != "bool":
                            raise TemplateError(f"{path}:{line}: `{{#if {word[1]}}}` needs a bool")
                        before = state.copy()
                        then, tag = parse_nodes({"#else", "#end"})
                        after_then = state.copy()
                        other = []
                        if tag == "#else":
                            state.__dict__.update(before.__dict__)
                            other, tag = parse_nodes({"#end"})
                        else:
                            state.__dict__.update(before.__dict__)
                        if tag != "#end":
                            raise TemplateError(f"{path}:{line}: `{{#if}}` has no `{{#end}}`")
                        if state.key() != after_then.key():
                            raise TemplateError(f"{path}:{line}: the two sides of this `{{#if}}` leave the {template.kind} in different places (an open tag or string); close it in both")
                        nodes.append(If(word[1], then, other, line))
                    else:
                        raise TemplateError(f"{path}:{line}: unknown `{{{inside}}}`")
                else:
                    flush()
                    position = end + 1
                    expression, _, filter_ = inside.partition("|")
                    expression, filter_ = expression.strip(), filter_.strip()
                    type_ = resolve(expression, line)
                    if filter_ not in ("", "money", "raw"):
                        raise TemplateError(f"{path}:{line}: unknown filter `{filter_}` (the filters are `money` and `raw`)")
                    if filter_ == "raw" and type_[0] not in ("bytes", "ascii"):
                        raise TemplateError(f"{path}:{line}: `raw` writes text as it is, and `{expression}` is not text")
                    if filter_ == "money" and type_[0] != "long":
                        raise TemplateError(f"{path}:{line}: `money` writes a long number of cents")
                    where = f"{path}:{line}"
                    if template.kind == "html":
                        context = html_context(state, where)
                        if filter_ == "raw" and context != "html_text":
                            raise TemplateError(f"{where}: `raw` is only allowed in HTML text, not inside a tag or attribute")
                    else:
                        context = "json_string" if state.in_string else "json_value"
                    nodes.append(Hole(expression, type_, filter_, context, line))
            else:
                char = text[position]
                if ord(char) > 126 or (ord(char) < 32 and char not in "\n\t"):
                    raise TemplateError(f"{path}:{line_at(position)}: template text must be ASCII (write non-ASCII characters as entities or \\u escapes)")
                literal += char
                position += 1
        flush()
        return nodes, None

    nodes, tag = parse_nodes(set())
    return nodes, params


# ---------------------------------------------------------------- sizes

def hole_size(hole):
    kind, limit = hole.type
    if hole.filter == "money":
        return 22
    if hole.filter == "raw":
        return hole.type[1]
    if kind == "long":
        return 20
    if kind == "int":
        return 11
    if kind == "bool":
        return 5
    if hole.context == "html_text" or hole.context == "html_attr":
        return limit * 6
    if hole.context == "html_url":
        return limit * 3
    if hole.context == "json_string":
        return limit * 6
    return limit * 6 + 2  # a JSON value: quotes around the escaped text


def max_size(nodes):
    total = 0
    for node in nodes:
        if isinstance(node, Lit):
            total += len(node.text)
        elif isinstance(node, Hole):
            total += hole_size(node)
        elif isinstance(node, For):
            total += node.count * max_size(node.body)
        else:
            total += max(max_size(node.then), max_size(node.other))
    return total


# ---------------------------------------------------------------- code

def nl_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


class Emitter:
    def __init__(self):
        self.helpers = {}   # name -> source, in creation order

    def helper(self, name, source):
        if name not in self.helpers:
            self.helpers[name] = source
        return name

    def literal(self, size):
        return self.helper(f"tpl_lit_{size}", f"""fn tpl_lit_{size}(out: grow Bytes max {size}, text: Ascii max {ASCII_LIMIT}) {{
    discard out.try_append(text.bytes())
}}
""")

    def number(self, size):
        return self.helper(f"tpl_num_{size}", f"""fn tpl_num_{size}(out: grow Bytes max {size}, value: long) {{
    var rest = value
    if rest < 0L {{
        discard out.push((byte)45)
        rest = 0L - rest
    }}
    var digits: list<long, 20> = list {{}}
    for step in 0L..20L {{
        discard digits.push(rest % 10L)
        rest = rest / 10L
        if rest == 0L {{ break }}
    }}
    var index = digits.count()
    for position in 0L..digits.count() {{
        index -= 1L
        discard out.push((byte)(48L + digits[index]))
    }}
}}
""")

    def money(self, size):
        number = self.number(size)
        return self.helper(f"tpl_money_{size}", f"""fn tpl_money_{size}(out: grow Bytes max {size}, cents: long) {{
    {number}(out, cents / 100L)
    discard out.push((byte)46)
    let rest = cents % 100L
    discard out.push((byte)(48L + rest / 10L))
    discard out.push((byte)(48L + rest % 10L))
}}
""")

    def boolean(self, size):
        lit = self.literal(size)
        return self.helper(f"tpl_bool_{size}", f"""fn tpl_bool_{size}(out: grow Bytes max {size}, value: bool) {{
    if value {{ {lit}(out, "true") }} else {{ {lit}(out, "false") }}
}}
""")

    def hex_digit(self, size):
        return self.helper(f"tpl_hex_{size}", f"""fn tpl_hex_{size}(out: grow Bytes max {size}, digit: long) {{
    if digit < 10L {{ discard out.push((byte)(48L + digit)) }} else {{ discard out.push((byte)(55L + digit)) }}
}}
""")

    def escape(self, context, kind, limit, size):
        """A function writing Bytes or Ascii text of at most `limit` bytes, escaped for the context."""
        type_name = "Bytes" if kind == "bytes" else "Ascii"
        lit = self.literal(size)
        hexd = self.hex_digit(size)
        if kind == "bytes":
            count, get = "value.count()", "value[index]"
        else:
            count, get = "value.len()", "value.bytes()[index]"
        if context in ("html_text", "html_attr"):
            body = f"""        if c == 60L {{ {lit}(out, "&lt;") }}
        else if c == 62L {{ {lit}(out, "&gt;") }}
        else if c == 38L {{ {lit}(out, "&amp;") }}
        else if c == 34L {{ {lit}(out, "&quot;") }}
        else if c == 39L {{ {lit}(out, "&#39;") }}
        else {{ discard out.push({get}) }}"""
        elif context in ("json_string", "json_value"):
            body = f"""        if c == 34L {{ {lit}(out, "\\\\\\"") }}
        else if c == 92L {{ {lit}(out, "\\\\\\\\") }}
        else if c == 10L {{ {lit}(out, "\\\\n") }}
        else if c < 32L {{
            {lit}(out, "\\\\u00")
            {hexd}(out, c / 16L)
            {hexd}(out, c % 16L)
        }}
        else {{ discard out.push({get}) }}"""
        else:  # html_url
            body = f"""        let unreserved = (c >= 48L && c <= 57L) || (c >= 65L && c <= 90L) || (c >= 97L && c <= 122L) || c == 45L || c == 46L || c == 95L || c == 126L
        if unreserved {{ discard out.push({get}) }}
        else {{
            discard out.push((byte)37)
            {hexd}(out, c / 16L)
            {hexd}(out, c % 16L)
        }}"""
        name = f"tpl_{context}_{kind}_{limit}_{size}"
        if context == "json_value":
            name = f"tpl_json_quoted_{kind}_{limit}_{size}"
            quote = "        discard out.push((byte)34)\n"
            return self.helper(name, f"""fn {name}(out: grow Bytes max {size}, value: {type_name} max {limit}) {{
    discard out.push((byte)34)
    for index in 0L..{count} {{
        let c = {get}.to_long()
{body}
    }}
    discard out.push((byte)34)
}}
""")
        return self.helper(name, f"""fn {name}(out: grow Bytes max {size}, value: {type_name} max {limit}) {{
    for index in 0L..{count} {{
        let c = {get}.to_long()
{body}
    }}
}}
""")

    def write_nodes(self, nodes, size, indent, lines):
        pad = "    " * indent
        for node in nodes:
            if isinstance(node, Lit):
                text = node.text
                for start in range(0, len(text), ASCII_LIMIT):
                    lines.append(f"{pad}{self.literal(size)}(out, {nl_string(text[start:start + ASCII_LIMIT])})")
            elif isinstance(node, Hole):
                kind, limit = node.type
                expression = node.path
                if node.filter == "money":
                    lines.append(f"{pad}{self.money(size)}(out, {expression})")
                elif node.filter == "raw":
                    lines.append(f"{pad}discard out.try_append({expression}{'.bytes()' if kind == 'ascii' else ''})")
                elif kind == "long":
                    lines.append(f"{pad}{self.number(size)}(out, {expression})")
                elif kind == "int":
                    lines.append(f"{pad}{self.number(size)}(out, {expression}.to_long())")
                elif kind == "bool":
                    lines.append(f"{pad}{self.boolean(size)}(out, {expression})")
                else:
                    lines.append(f"{pad}{self.escape(node.context, kind, limit, size)}(out, {expression})")
            elif isinstance(node, For):
                lines.append(f"{pad}for {node.name} in {node.path} {{")
                self.write_nodes(node.body, size, indent + 1, lines)
                lines.append(f"{pad}}}")
            else:
                lines.append(f"{pad}if {node.path} {{")
                self.write_nodes(node.then, size, indent + 1, lines)
                if node.other:
                    lines.append(f"{pad}}} else {{")
                    self.write_nodes(node.other, size, indent + 1, lines)
                lines.append(f"{pad}}}")


def compile_package(directory):
    structs = read_structs(directory)
    sources = [name for name in sorted(os.listdir(directory)) if name.endswith(".tpl")]
    if not sources:
        return None
    emitter = Emitter()
    functions = []
    seen = set()
    for name in sources:
        path = os.path.join(directory, name)
        for template in read_templates(path):
            if template.name in seen:
                raise TemplateError(f"{path}:{template.line}: template {template.name} is defined twice")
            seen.add(template.name)
            nodes, params = parse_body(template, structs, path)
            largest = max_size(nodes)
            if largest > template.size:
                raise TemplateError(f"{path}:{template.line}: template {template.name} can write up to {largest} bytes but its buffer holds {template.size}; make `max` at least {largest} or shorten the template")
            lines = []
            emitter.write_nodes(nodes, template.size, 1, lines)
            parameter_text = ", ".join(f"{pname}: {ptype}" for pname, ptype in template.params)
            signature = f"fn render_{template.name}(out: grow Bytes max {template.size}" + (", " + parameter_text if parameter_text else "") + ")"
            functions.append(f"// {template.kind} template {template.name}: writes at most {largest} bytes\n{signature} {{\n" + "\n".join(lines) + "\n}\n")
    output = "// Generated by tools/tmpl.py from the package's .tpl files; do not edit.\n\n"
    output += "\n".join(emitter.helpers.values()) + "\n" + "\n".join(functions)
    target = os.path.join(directory, "templates.gen.nl")
    previous = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if previous != output:
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(output)
    return target


def main(argv):
    if len(argv) != 2:
        print("usage: tmpl.py <package-dir>", file=sys.stderr)
        return 2
    try:
        compile_package(argv[1])
    except TemplateError as error:
        print(f"nlc: template error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
