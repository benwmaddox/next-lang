test "an error result fails with its value" (env: Env) {
    var bytes: list<byte, 1> = list {}
    env.fs.read("missing", bytes)
}
