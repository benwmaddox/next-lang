fn main(env: Env) -> Result<(), IoError> {
    let out = env.out
    let bytes: Bytes max 8 = b"raw"
    let text: Text max 2 = "😀é"
    out.write(bytes)?
    out.line(text)?
    out.write(text)?
    out.write(text.bytes())?
    out.line(bytes)?
    ok(())
}
