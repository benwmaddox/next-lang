// Brainfuck::Recursion: parse the program into nested loops, then interpret it recursively.
const TEST_PROGRAM: Ascii max 512 = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.>+.>."
const TEST_WARMUP_PROGRAM: Ascii max 512 = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.>+.>."
const TEST_WARMUP_ITERATIONS: long = 1L
const TEST_ITERATIONS: long = 2L
const RUN_PROGRAM: Ascii max 512 = ">++[<+++++++++++++>-]<[[>+>+<<-]>[<+>-]++++++++[>++++++++<-]>.[-]<<>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[-]<-]<-]<-]<-]<-]<-]<-]++++++++++."
const RUN_WARMUP_PROGRAM: Ascii max 512 = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.>+.>."
const RUN_WARMUP_ITERATIONS: long = 1000L
const RUN_ITERATIONS: long = 1L
const MODULUS: long = 4294967296L
const STEP_LIMIT: long = 1000000000000000L
// The tape is a fixed 30000 cells (Crystal's Tape starts at 30000 and grows; these programs never leave it).
const TAPE_CELLS: long = 30000L

const OP_DEC: int = 1
const OP_INC: int = 2
const OP_PREV: int = 3
const OP_NEXT: int = 4
const OP_PRINT: int = 5
const OP_LOOP: int = 6

// A loop's body is the ops that follow it, up to `end` (the index just past the body).
struct Op {
    kind: int
    end: long
}

struct Machine {
    tape: int[TAPE_CELLS]
    pos: long
    result: long
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

// Parses from `pos` until the matching ']' (consumed) or the end of the text.
recursive fn parse(source: Ascii max 512, pos: write long, ops: write list<Op, 1024>) {
    for _step: long in 0L..STEP_LIMIT {
        if pos >= source.len() { break }
        let byte = source.bytes()[pos]
        pos += 1L
        if byte == 93 { break }
        let kind = match byte {
            45 => OP_DEC,
            43 => OP_INC,
            60 => OP_PREV,
            62 => OP_NEXT,
            46 => OP_PRINT,
            91 => OP_LOOP,
            _ => 0
        }
        if kind == OP_LOOP {
            let at = ops.count()
            ops.push(Op { kind: kind, end: 0L }).unwrap()
            parse(source, pos, ops)
            ops[at].end = ops.count()
        } else if kind != 0 {
            ops.push(Op { kind: kind, end: 0L }).unwrap()
        } else {}
    }
}

recursive fn execute(ops: list<Op, 1024>, first: long, last: long, machine: write Machine) {
    var next = first
    for i: long in first..last {
        if i >= next {
            let op = ops[i]
            next = i + 1L
            if op.kind == OP_DEC {
                machine.tape[machine.pos] = (machine.tape[machine.pos] + 255) % 256
            } else if op.kind == OP_INC {
                machine.tape[machine.pos] = (machine.tape[machine.pos] + 1) % 256
            } else if op.kind == OP_PREV {
                if machine.pos > 0L { machine.pos -= 1L }
            } else if op.kind == OP_NEXT {
                machine.pos += 1L
            } else if op.kind == OP_PRINT {
                machine.result = (machine.result * 4L + machine.tape[machine.pos].to_long()) % MODULUS
            } else {
                for _turn: long in 0L..STEP_LIMIT {
                    if machine.tape[machine.pos] == 0 { break }
                    execute(ops, i + 1L, op.end, machine)
                }
                next = op.end
            }
        }
    }
}

fn run_program(source: Ascii max 512) -> long {
    var ops: list<Op, 1024> = list {}
    var pos = 0L
    parse(source, pos, ops)
    var machine = Machine { tape: fill(0), pos: 0L, result: 0L }
    execute(ops, 0L, ops.count(), machine)
    machine.result
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let prep = is_prep_mode(env)
    let program: Ascii max 512 = if run { RUN_PROGRAM } else { TEST_PROGRAM }
    let warmup_program: Ascii max 512 = if run { RUN_WARMUP_PROGRAM } else { TEST_WARMUP_PROGRAM }
    let warmup = if run { RUN_WARMUP_ITERATIONS } else { TEST_WARMUP_ITERATIONS }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    // Warmup results are not part of Crystal's checksum; prep mode prints them so the warmup work is observable.
    var sink = 0L
    for _w: long in 0L..warmup {
        sink = (sink + run_program(warmup_program)) % MODULUS
    }
    if prep {
        print(sink)
    } else {
        var checksum = 0L
        for _i: long in 0L..iterations {
            checksum = (checksum + run_program(program)) % MODULUS
        }
        print(checksum)
    }
}
