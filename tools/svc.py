#!/usr/bin/env python3
"""Service compiler (prototype of docs/design/job-modules.md): turns the *.svc files of a package into next-lang code.

    python3 tools/svc.py <package-dir>      writes <package-dir>/services.gen.nl

A service is state plus one handler per inbound message type. Its handlers run to completion and never wait.

    service Cache
    config db: Sender<DbRequest>
    state slots: list<Row, 4096> = list {}
    state hits: long = 0L
    mailbox 256

    init {
        ...statements; `state` and `config` are in scope...
    }

    on Get(key: long) -> Row {         // `-> Row` declares a reply; `reply(value)` answers the caller
        ...
    }
    on Fill(row: Row) {
        ...
    }

The generated code, for a service named Cache:
- `struct Cache { inbox: Sender<CacheMessage> }`, the handle others hold; `CacheMessage`, an enum with one variant per
  handler (and `Stop`); a state struct and a config struct.
- `Cache_start(<config>) -> Cache`: makes the mailbox and spawns the service's job.
- For each handler (also callable as `service.get(key)`): `Cache_get(service, key) -> Option<Row>` (sends and waits for the reply; a task calls it) or, for a
  handler with no reply, `Cache_fill(service, row) -> bool` (send, false when the mailbox is full), and `Cache_stop`.
- Handlers see `state` (write), `config`, `me` (the service's own handle), their parameters, and `reply` when they declare one.
Config fields must be numbers, bools, `Env` or mailbox handles (what `spawn` accepts).
"""

import os
import re
import sys


class ServiceError(Exception):
    pass


def split_top(text, separator=","):
    parts, depth, current = [], 0, ""
    for char in text:
        if char in "<(":
            depth += 1
        elif char in ">)":
            depth -= 1
        if char == separator and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current)
    return [part.strip() for part in parts]


def snake(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


class Handler:
    def __init__(self, name, params, reply, body, line):
        self.name, self.params, self.reply, self.body, self.line = name, params, reply, body, line


class Service:
    def __init__(self, name, line):
        self.name, self.line = name, line
        self.config = []     # (name, type)
        self.state = []      # (name, type, initial)
        self.mailbox = 64
        self.init = ""
        self.tick_ms = 0
        self.tick_body = ""
        self.tick_line = 0
        self.idle_body = ""
        self.idle_line = 0
        self.handlers = []


def read_services(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    services = []
    service = None
    index = 0
    while index < len(lines):
        line = lines[index]
        number = index + 1
        index += 1
        if not line.strip() or line.startswith("//"):
            continue
        match = re.fullmatch(r"service\s+(\w+)\s*", line)
        if match:
            service = Service(match.group(1), number)
            services.append(service)
            continue
        if service is None:
            raise ServiceError(f"{path}:{number}: expected `service Name`")
        match = re.fullmatch(r"config\s+(\w+)\s*:\s*(.+)", line)
        if match:
            service.config.append((match.group(1), match.group(2).strip()))
            continue
        match = re.fullmatch(r"state\s+(\w+)\s*:\s*(.+?)\s*=\s*(.+)", line)
        if match:
            service.state.append((match.group(1), match.group(2).strip(), match.group(3).strip()))
            continue
        match = re.fullmatch(r"mailbox\s+(\d+)\s*", line)
        if match:
            service.mailbox = int(match.group(1))
            continue
        header = re.fullmatch(r"(init|idle|tick\s+every\s+(\d+)\s*(ms|s)|on\s+(\w+)\s*\((.*)\)(?:\s*->\s*(.+?))?)\s*\{\s*", line)
        if header:
            body = []
            while index < len(lines) and lines[index] != "}":
                body.append(lines[index])
                index += 1
            if index >= len(lines):
                raise ServiceError(f"{path}:{number}: this block is not closed by a `}}` at the start of a line")
            index += 1
            text = "\n".join(body)
            if header.group(1) == "init":
                service.init = text
            elif header.group(1) == "idle":
                service.idle_body = text
                service.idle_line = number
            elif header.group(1).startswith("tick"):
                service.tick_ms = int(header.group(2)) * (1000 if header.group(3) == "s" else 1)
                service.tick_body = text
                service.tick_line = number
            else:
                params = []
                for item in split_top(header.group(5)):
                    pname, _, ptype = item.partition(":")
                    params.append((pname.strip(), ptype.strip()))
                service.handlers.append(Handler(header.group(4), params, header.group(6).strip() if header.group(6) else None, text, number))
            continue
        raise ServiceError(f"{path}:{number}: unexpected `{line.strip()}`")
    return services


def indent(text, spaces):
    pad = " " * spaces
    return "\n".join((pad + line if line.strip() else line) for line in text.split("\n"))


def generate(service, path, known=()):
    name = service.name
    # a config field typed as another service is passed to the job as that service's raw sender
    def raw_type(type_):
        return f"Sender<{type_}Message>" if type_ in known else type_
    if not service.handlers:
        raise ServiceError(f"{path}:{service.line}: service {name} has no `on` handler")
    if service.tick_ms and ("env", "Env") not in service.config:
        raise ServiceError(f"{path}:{service.tick_line}: a service with `tick` needs `config env: Env` (the clock)")
    seen = set()
    for handler in service.handlers:
        if handler.name in seen or handler.name == "Stop":
            raise ServiceError(f"{path}:{handler.line}: handler {handler.name} is defined twice or is the reserved Stop")
        seen.add(handler.name)
    out = []
    message = f"{name}Message"
    out.append(f"// service {name} (generated from its .svc file)")
    out.append(f"struct {name} {{\n    inbox: Sender<{message}>\n}}\n")
    if service.state:
        out.append(f"struct {name}State {{\n" + "\n".join(f"    {n}: {t}" for n, t, _ in service.state) + "\n}\n")
    else:
        out.append(f"struct {name}State {{\n    unused: long\n}}\n")
    if service.config:
        out.append(f"struct {name}Config {{\n" + "\n".join(f"    {n}: {t}" for n, t in service.config) + "\n}\n")
    else:
        out.append(f"struct {name}Config {{\n    unused: long\n}}\n")
    variants = []
    for handler in service.handlers:
        fields = list(handler.params)
        if handler.reply:
            fields.append(("reply", f"Sender<{handler.reply}>"))
        if fields:
            out.append(f"struct {name}{handler.name}Args {{\n" + "\n".join(f"    {n}: {t}" for n, t in fields) + "\n}\n")
            variants.append(f"    {handler.name}({name}{handler.name}Args),")
        else:
            variants.append(f"    {handler.name},")
    variants.append("    Stop,")
    out.append(f"enum {message} {{\n" + "\n".join(variants) + "\n}\n")
    # handlers
    config_args = ", ".join(n for n, _ in service.config) if service.config else "0L"
    for handler in service.handlers:
        params = [("state", f"write {name}State"), ("config", f"{name}Config"), ("me", name)] + handler.params
        if handler.reply:
            params.append(("reply", f"Sender<{handler.reply}>"))
        body = handler.body
        if handler.reply:
            body = re.sub(r"\breply\(", f"{name}_answer_{snake(handler.name)}(reply, ", body)
            out.append(f"fn {name}_answer_{snake(handler.name)}(to: Sender<{handler.reply}>, value: {handler.reply}) {{\n"
                       f"    match to.send(value) {{\n        ok(_) => {{}},\n        err(_) => {{}},\n    }}\n}}\n")
        out.append(f"fn {name}_on_{snake(handler.name)}({', '.join(f'{n}: {t}' for n, t in params)}) {{\n{body}\n}}\n")
    if service.tick_ms:
        out.append(f"fn {name}_on_tick(state: write {name}State, config: {name}Config, me: {name}, missed: long) {{\n{service.tick_body}\n}}\n")
    if service.idle_body:
        out.append(f"// runs when the mailbox is empty; returns true when it has more to do\n"
                   f"fn {name}_on_idle(state: write {name}State, config: {name}Config, me: {name}) -> bool {{\n{service.idle_body}\n}}\n")
    # run loop
    run_params = [("inbox", f"Receiver<{message}>"), ("self_inbox", f"Sender<{message}>")] + [(n, raw_type(t)) for n, t in service.config]
    state_init = ", ".join(f"{n}: {i}" for n, _, i in service.state) if service.state else "unused: 0L"
    config_init = ", ".join((f"{n}: {t} {{ inbox: {n} }}" if t in known else f"{n}: {n}") for n, t in service.config) if service.config else "unused: 0L"
    arms = []
    for handler in service.handlers:
        call_args = ["state", "config", "me"] + [f"args.{n}" for n, _ in handler.params] + (["args.reply"] if handler.reply else [])
        has_fields = bool(handler.params or handler.reply)
        pattern = f"{message}.{handler.name}(args)" if has_fields else f"{message}.{handler.name}"
        arms.append(f"                    {pattern} => {{ {name}_on_{snake(handler.name)}({', '.join(call_args)}) }},")
    arms.append(f"                    {message}.Stop => {{ break }},")
    run = [f"fn {name}_run({', '.join(f'{n}: {t}' for n, t in run_params)}) {{",
           f"    var state = {name}State {{ {state_init} }}",
           f"    let config = {name}Config {{ {config_init} }}",
           f"    let me = {name} {{ inbox: self_inbox }}"]
    if service.init:
        run.append("    // init\n" + service.init)
    # The loop. `dispatch` is the match over message kinds. With `idle`, a turn first polls the mailbox; an empty mailbox
    # runs the idle step, and only when that has nothing more to do does the service wait. With `tick`, the wait is
    # limited to the next tick, and a due tick runs after the turn.
    def dispatch(pad, var="message"):
        return [f"{pad}match {var} {{"] + [pad + arm.strip().join(["    ", ""]) for arm in arms] + [f"{pad}}}"]

    idle_call = f"{name}_on_idle(state, config, me)"
    body = ["    for svc_turn in 0L..4000000000L {"]
    if service.tick_ms:
        period = service.tick_ms
        run.append(f"    var next_tick = config.env.now_ms() + {period}L")
    if service.idle_body:
        body += ["        var busy = false",
                 "        match inbox.recv() {",
                 "            some(message) => {",
                 "                busy = true"] + dispatch("                ") + [
                 "            },",
                 "            none => {",
                 "                if inbox.is_closed() { break }",
                 f"                busy = {idle_call}",
                 "            },",
                 "        }",
                 "        if !busy {"]
        pad = "            "
    else:
        pad = "        "
    if service.tick_ms:
        body += [f"{pad}var wait = next_tick - config.env.now_ms()",
                 f"{pad}if wait < 0L {{ wait = 0L }}",
                 f"{pad}match inbox.recv_for(wait) {{"]
    else:
        body += [f"{pad}match inbox.recv_wait() {{"]
    body += [f"{pad}    some(message) => {{"] + dispatch(pad + "        ") + [f"{pad}    }},"]
    body += [f"{pad}    none => {{ if inbox.is_closed() {{ break }} }},", f"{pad}}}"]
    if service.idle_body:
        body += ["        }"]
    if service.tick_ms:
        body += ["        let after = config.env.now_ms()",
                 "        if after >= next_tick {",
                 f"            let missed = (after - next_tick) / {period}L",
                 f"            {name}_on_tick(state, config, me, missed)",
                 f"            next_tick = next_tick + (missed + 1L) * {period}L",
                 "        }"]
    run += body + ["    }", "}\n"]
    out.append("\n".join(run))
    # start
    start_params = ", ".join(f"{n}: {t}" for n, t in service.config)
    start_args = ", ".join((f"{n}.inbox" if t in known else n) for n, t in service.config)
    out.append(f"fn {name}_start({start_params}) -> {name} {{\n"
               f"    var box: mailbox<{message}, {service.mailbox}> = mailbox {{}}\n"
               f"    spawn {name}_run(box.receiver(), box.sender()" + (", " + start_args if start_args else "") + ")\n"
               f"    {name} {{ inbox: box.sender() }}\n}}\n")
    # callers
    for handler in service.handlers:
        fn = f"{name}_{snake(handler.name)}"
        params = ", ".join(f"{n}: {t}" for n, t in handler.params)
        args = ", ".join(f"{n}: {n}" for n, _ in handler.params)
        has_fields = bool(handler.params or handler.reply)
        if handler.reply:
            fields = args + (", " if args else "") + "reply: replies_box.sender()"
            out.append(f"// sends {handler.name} and waits for the reply (none when the mailbox is full)\n"
                       f"fn {fn}(service: {name}{', ' + params if params else ''}) -> Option<{handler.reply}> {{\n"
                       f"    var replies_box: mailbox<{handler.reply}, 1> = mailbox {{}}\n"
                       f"    let replies = replies_box.receiver()\n"
                       f"    let message = {message}.{handler.name}({name}{handler.name}Args {{ {fields} }})\n"
                       f"    match service.inbox.send(message) {{\n"
                       f"        ok(_) => {{\n            let answer = replies.recv_wait()\n            replies_box.release()\n            answer\n        }},\n"
                       f"        err(_) => {{\n            replies_box.release()\n            none\n        }},\n    }}\n}}\n")
        else:
            payload = f"{message}.{handler.name}({name}{handler.name}Args {{ {args} }})" if has_fields else f"{message}.{handler.name}"
            out.append(f"// sends {handler.name}; false when the service's mailbox is full\n"
                       f"fn {fn}(service: {name}{', ' + params if params else ''}) -> bool {{\n"
                       f"    let message = {payload}\n"
                       f"    match service.inbox.send(message) {{\n        ok(_) => {{ true }},\n        err(_) => {{ false }},\n    }}\n}}\n")
    out.append(f"// asks the service to finish after the messages already queued\n"
               f"fn {name}_stop(service: {name}) -> bool {{\n    let message = {message}.Stop\n"
               f"    match service.inbox.send(message) {{\n        ok(_) => {{ true }},\n        err(_) => {{ false }},\n    }}\n}}\n")
    return "\n".join(out)


def check_services(parsed):
    """Whole-package checks: handlers never wait, replies are answered, and the message graph is printed on request."""
    services = {service.name: service for _, services in parsed for service in services}
    waits = {}   # sender function -> service, for calls that wait for a reply
    sends = {}   # sender function -> service, for fire-and-forget sends
    for service in services.values():
        for handler in service.handlers:
            function = f"{service.name}_{snake(handler.name)}"
            (waits if handler.reply else sends)[function] = service.name
    edges = []
    for path, found in parsed:
        for service in found:
            bodies = [(handler, handler.body, handler.line, f"{service.name}.{handler.name}") for handler in service.handlers]
            if service.tick_ms:
                bodies.append((None, service.tick_body, service.tick_line, f"{service.name}.tick"))
            if service.idle_body:
                bodies.append((None, service.idle_body, service.idle_line, f"{service.name}.idle"))
            for handler, handler_body, handler_line, label in bodies:
                handler = handler or Handler("tick", [], None, handler_body, handler_line)
                body = re.sub(r"//[^\n]*", "", handler.body)
                where = f"{path}:{handler.line}"
                # method syntax: `config.<field>.get(...)` or `me.get(...)` where the receiver is a service handle
                receivers = {"me": service.name}
                receivers.update({f"config.{field}": kind for field, kind in service.config if kind in services})
                method_calls = {}   # call text pattern -> (target service, sender function, waits)
                for receiver, target_name in receivers.items():
                    for target_handler in services[target_name].handlers:
                        method_calls[rf"\b{re.escape(receiver)}\.{snake(target_handler.name)}\s*\("] = (
                            target_name, f"{target_name}_{snake(target_handler.name)}", bool(target_handler.reply))
                for pattern, (target_name, function, waited) in method_calls.items():
                    if re.search(pattern, body):
                        if waited:
                            raise ServiceError(f"{where}: handler {service.name}.{handler.name} calls {function} and would wait for the answer; "
                                               f"a service handler never waits. Pass `reply` (or a sender) on to the other service instead")
                        edges.append((service.name, handler.name, target_name, function))
                for function, target in waits.items():
                    if re.search(rf"\b{function}\s*\(", body):
                        raise ServiceError(f"{where}: handler {service.name}.{handler.name} calls {function} and would wait for the answer; "
                                           f"a service handler never waits. Pass `reply` (or a sender) on to the other service instead")
                for function, target in list(sends.items()) + list(waits.items()):
                    if re.search(rf"\b{function}\s*\(", body):
                        edges.append((service.name, handler.name, target, function))
                if handler.reply:
                    answers = re.search(r"\breply\s*\(", body) or re.search(r"\breply\s*[,)]", body)
                    if not answers:
                        raise ServiceError(f"{where}: handler {service.name}.{handler.name} declares a reply (-> {handler.reply}) but never answers: "
                                           f"call reply(value), or pass `reply` on to another service")
                elif re.search(r"\breply\b", body):
                    raise ServiceError(f"{where}: handler {service.name}.{handler.name} uses `reply` but declares none; add `-> Type`")
    return edges


def graph_text(edges):
    return "\n".join(f"{source}.{handler} -> {target} ({function})" for source, handler, target, function in sorted(set(edges)))


def compile_package(directory):
    sources = [name for name in sorted(os.listdir(directory)) if name.endswith(".svc")]
    if not sources:
        return None
    pieces = ["// Generated by tools/svc.py from the package's .svc files; do not edit.\n"]
    parsed = [(os.path.join(directory, name), read_services(os.path.join(directory, name))) for name in sources]
    known = {service.name for _, services in parsed for service in services}
    edges = check_services(parsed)
    for path, services in parsed:
        for service in services:
            pieces.append(generate(service, path, known))
    output = "\n".join(pieces)
    if edges:
        output += "\n// message graph (service.handler -> target service):\n" + "\n".join("// " + line for line in graph_text(edges).split("\n")) + "\n"
    target = os.path.join(directory, "services.gen.nl")
    previous = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if previous != output:
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(output)
    return target


def main(argv):
    if len(argv) != 2:
        print("usage: svc.py <package-dir>", file=sys.stderr)
        return 2
    try:
        compile_package(argv[1])
    except ServiceError as error:
        print(f"nlc: service error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
