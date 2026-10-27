test "an error result fails with its value" (env: Env) {
    var byte_values: list<byte, 1> = list {}
    env.fs.read("missing", byte_values)
}
