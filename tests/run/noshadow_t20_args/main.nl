fn show(arg_list: Args, out: Out, index: long) -> Result<(), IoError> {
    match arg_list.get(index) {
        some(argument) => {
            out.long(argument.count())?
            out.line(b"")?
            match argument.get(0L) {
                some(value) => {
                    out.int(value)?
                    out.line(b"")?
                    ()
                },
                none => {
                    out.line(b"empty")?
                    ()
                }
            }
            out.line(argument)?
            ok(())
        },
        none => ok(())
    }
}

fn main(env: Env) -> Result<(), IoError> {
    let arguments = env.args()
    let out = env.out
    out.long(arguments.count())?
    out.line(b"")?
    show(arguments, out, 0L)?
    show(arguments, out, 1L)?
    show(arguments, out, 2L)?
    ok(())
}
