struct Snapshot {
    value: int,
}

test "aggregate equality uses evaluation snapshots" {
    var current = Snapshot { value: 1 }
    expect (current == if true {
        current.value = 9;
        Snapshot { value: 2 }
    } else {
        Snapshot { value: 2 }
    })
}
