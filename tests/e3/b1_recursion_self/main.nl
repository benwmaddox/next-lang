struct Receipt {
    frames: long,
    label_len: long,
    marker: long,
}

fn force_arena_growth() {
    let scratch: list<bool, 300000> = list {}
    print(scratch.count())
}

recursive fn marked_leaf(value: long) -> long {
    value + 1L
}

recursive fn walk(
    depth: long,
    fail: bool,
    label: Ascii max 8,
    calls: write long,
    output: grow Ascii max 5000,
) -> Result<Receipt, Full> {
    calls += 1L
    force_arena_growth()
    if depth == 0L {
        print(label)
        if fail {
            var no_room: list<int, 0> = list {}
            no_room.push(7)?
        }
        ok(Receipt { frames: 1L, label_len: label.len(), marker: marked_leaf(depth) })
    } else {
        output.try_append("a")?
        let child = walk(depth - 1L, fail, label, calls, output)?
        output.try_append("b")?
        if depth == 2L {
            return ok(Receipt { frames: child.frames + 1L, label_len: child.label_len, marker: child.marker })
        }
        ok(Receipt { frames: child.frames + 1L, label_len: child.label_len, marker: child.marker })
    }
}

fn main() {
    print(marked_leaf(8L))

    let label: Ascii max 8 = "read"
    var calls: long = 0L
    var output: Ascii max 5000 = ""
    match walk(2L, false, label, calls, output) {
        Result.ok(receipt) => {
            print(receipt.frames)
            print(receipt.label_len)
            print(receipt.marker)
        },
        Result.err(_) => print("unexpected error"),
    }
    print(calls)
    print(output)

    var failed_calls: long = 0L
    var failed_output: Ascii max 5000 = ""
    match walk(2L, true, label, failed_calls, failed_output) {
        Result.ok(_) => print("unexpected success"),
        Result.err(error) => print(error),
    }
    print(failed_calls)
    print(failed_output)
}
