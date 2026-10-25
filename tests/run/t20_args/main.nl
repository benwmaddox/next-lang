fn show(args: Args, out: Out, index: long) -> Result<(), IoError> {
    match args.get(index) {
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
    let args = env.args()
    let out = env.out
    out.long(args.count())?
    out.line(b"")?
    show(args, out, 0L)?
    show(args, out, 1L)?
    show(args, out, 2L)?
    ok(())
}
