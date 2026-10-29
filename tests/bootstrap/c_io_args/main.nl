fn write_data(env: Env, out: Out, data: Bytes max 32) {
    match out.write(data) {
        ok(_) => (),
        err(_) => env.exit(3),
    }
}

fn write_argument(env: Env, out: Out, argument: Arg) {
    write_data(env, out, b"arg=")
    match out.write(argument) {
        ok(_) => (),
        err(_) => env.exit(3),
    }
    write_data(env, out, b";bytes=")
    write_data(env, out, str(argument.count()).bytes())
    match argument.get(0L) {
        some(_) => write_data(env, out, b";first=some\n"),
        none => write_data(env, out, b";first=none\n"),
    }
}

fn main(env: Env) {
    let arguments = env.args()
    let out = env.out
    write_data(env, out, b"args=")
    write_data(env, out, str(arguments.count()).bytes())
    write_data(env, out, b"\n")
    for index in 0L..arguments.count() {
        match arguments.get(index) {
            some(argument) => write_argument(env, out, argument),
            none => env.exit(3),
        }
    }
    write_data(env, env.err, b"stderr=ready\n")
}
