test "exit only fails this test process" (env: Env) {
    env.exit(17)
}

test "runner continues after an exit" {
    expect true
}
