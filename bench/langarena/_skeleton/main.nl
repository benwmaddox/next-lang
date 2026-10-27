fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn main(env: Env) {
    let n = if is_run_mode(env) { 1000L } else { 10L }
    var total = 0L
    for i: long in 0L..n {
        total = (total + i * i) % 4294967296L
    }
    print(total)
}
