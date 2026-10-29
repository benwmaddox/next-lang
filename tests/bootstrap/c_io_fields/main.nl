struct Prefix {
    code: int,
    sequence: long,
}

struct Record {
    prefix: Prefix,
    active: bool,
    name: Bytes max 16,
}

fn write_record(out: Out, value: Record) {
    match out.write(value.name) {
        ok(_) => (),
        err(_) => return,
    }
}

fn write_second(out: Out, values: list<Record, 3>) {
    match out.write(values[2L].name) {
        ok(_) => (),
        err(_) => return,
    }
}

fn main(env: Env) {
    let out = env.out
    let local = Record { prefix: Prefix { code: 7, sequence: 70L }, active: true, name: b"local\n" }
    write_record(out, local)
    write_record(out, Record { prefix: Prefix { code: 8, sequence: 80L }, active: false, name: b"param\n" })

    let values: list<Record, 3> = [
        Record { prefix: Prefix { code: 9, sequence: 90L }, active: false, name: b"x\n" },
        Record { prefix: Prefix { code: 10, sequence: 100L }, active: true, name: b"indexed\n" },
        Record { prefix: Prefix { code: 11, sequence: 110L }, active: false, name: b"third\n" },
    ]
    match out.write(values[1L].name) {
        ok(_) => (),
        err(_) => return,
    }
    write_second(out, values)
}
