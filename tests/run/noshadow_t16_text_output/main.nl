fn main(env: Env) -> Result<(), IoError> {
    let out = env.out
    let raw_bytes: Bytes max 8 = b"raw"
    let text: Text max 2 = "😀é"
    out.write(raw_bytes)?
    out.line(text)?
    out.write(text)?
    out.write(text.bytes())?
    out.line(raw_bytes)?
    ok(())
}
