struct Small { value: int = 0 }

fn shared(value: Small) -> bool { value == Small {} }

test "aggregate test entry stays below the frame budget" {
    let value = Small {}
    expect shared(value)
}
