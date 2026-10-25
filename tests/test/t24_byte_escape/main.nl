test "byte hex escape survives a file round trip" (env: Env) {
    let fs = env.fs
    fs.write("byte.bin", b"\xff").unwrap()
    var bytes: list<byte, 1> = list {}
    fs.read("byte.bin", bytes).unwrap()
    expect bytes.count() == 1
    expect bytes[0] == 255
}
