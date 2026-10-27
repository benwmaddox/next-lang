test "byte hex escape survives a file round trip" (env: Env) {
    let fs = env.fs
    fs.write("byte.bin", b"\xff").unwrap()
    var byte_values: list<byte, 1> = list {}
    fs.read("byte.bin", byte_values).unwrap()
    expect byte_values.count() == 1
    expect byte_values[0] == 255
}
