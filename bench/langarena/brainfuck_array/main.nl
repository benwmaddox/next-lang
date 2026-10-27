// Brainfuck::Array: compile the program to a command array with a jump table, then interpret it.
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

const OP_INC: int = 1
const OP_DEC: int = 2
const OP_NEXT: int = 3
const OP_PREV: int = 4
const OP_OPEN: int = 5
const OP_CLOSE: int = 6
const OP_PRINT: int = 7

struct Program {
    commands: list<int, 1024>
    jumps: int[1024]
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// The command codes of a program text, or none for unbalanced brackets or a ',' command.
fn compile(source: Ascii max 512) -> Option<Program> {
    var program = Program { commands: list {}, jumps: fill(0) }
    var open: list<int, 1024> = list {}
    for i: long in 0L..source.len() {
        let code = match source.bytes()[i] {
            43 => OP_INC,
            45 => OP_DEC,
            62 => OP_NEXT,
            60 => OP_PREV,
            91 => OP_OPEN,
            93 => OP_CLOSE,
            46 => OP_PRINT,
            44 => -1,
            _ => 0
        }
        if code == -1 { return none }
        if code != 0 {
            let at = (int)program.commands.count()
            program.commands.push(code).unwrap()
            if code == OP_OPEN {
                open.push(at).unwrap()
            } else if code == OP_CLOSE {
                let start = open.pop() ?? return none
                program.jumps[start.to_long()] = at
                program.jumps[at.to_long()] = start
            } else {}
        }
    }
    if program.commands.count() == 0L { return none }
    if open.count() != 0L { return none }
    some(program)
}

fn execute(program: Program) -> long {
    var tape: int[100000] = fill(0)
    var pos = 0L
    var pc = 0L
    var result = 0L
    let count_value = program.commands.count()
    for _step: long in 0L..STEP_LIMIT {
        if pc >= count_value { break }
        let command = program.commands[pc]
        if command == OP_INC {
            tape[pos] = (tape[pos] + 1) % 256
        } else if command == OP_DEC {
            tape[pos] = (tape[pos] + 255) % 256
        } else if command == OP_NEXT {
            pos += 1L
        } else if command == OP_PREV {
            if pos > 0L { pos -= 1L }
        } else if command == OP_OPEN {
            if tape[pos] == 0 { pc = program.jumps[pc].to_long() }
        } else if command == OP_CLOSE {
            if tape[pos] != 0 { pc = program.jumps[pc].to_long() }
        } else {
            result = (result * 4L + tape[pos].to_long()) % MODULUS
        }
        pc += 1L
    }
    result
}

fn run_program(source: Ascii max 512) -> Option<long> {
    let program = compile(source)?
    some(execute(program))
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let program: Ascii max 512 = if run { RUN_PROGRAM } else { TEST_PROGRAM }
    let warmup_program: Ascii max 512 = if run { RUN_WARMUP_PROGRAM } else { TEST_WARMUP_PROGRAM }
    let warmup = if run { RUN_WARMUP_ITERATIONS } else { TEST_WARMUP_ITERATIONS }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    for _w: long in 0L..warmup {
        match run_program(warmup_program) {
            some(_) => {},
            none => {}
        }
    }
    var checksum = 0L
    for _i: long in 0L..iterations {
        match run_program(program) {
            some(result) => { checksum = (checksum + result) % MODULUS },
            none => {}
        }
    }
    print(checksum)
}
