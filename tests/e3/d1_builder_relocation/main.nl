struct Holder {
    snapshot: Ascii max 4,
    output: Ascii max 8,
    text: Text max 3 bytes max 12,
    bytes: Bytes max 5000,
    sibling: int,
}

fn force_arena_growth() {
    let scratch: list<bool, 300000> = list {}
    print(scratch.count())
}

fn make_piece_that_forces_growth() -> Ascii max 1 {
    let scratch: list<bool, 1200000> = list {}
    print(scratch.count())
    "x"
}

fn append_after_growth(
    snapshot: Ascii max 4,
    output: grow Ascii max 8,
    region: grow Ascii max 262120,
    text: grow Text max 3 bytes max 12,
    bytes: grow Bytes max 5000,
) {
    discard output.try_append("!")
    discard region.try_append("pre")
    discard text.try_append("猫")
    discard bytes.try_append(b"B")

    force_arena_growth()

    print(snapshot)
    discard output.try_append(snapshot)
    print(output.try_append(make_piece_that_forces_growth()))
    discard region.try_append("post")
    discard text.try_append("😀")
    discard bytes.try_append(b"C")

    print(output)
    print(region)
    print(text)
    print(text.len())
    print(text.byte_len())
    print(bytes.len())
    print(bytes[0L])
    print(bytes[1L])
    print(bytes[2L])
}

fn forward(
    snapshot: Ascii max 4,
    output: grow Ascii max 8,
    region: grow Ascii max 262120,
    text: grow Text max 3 bytes max 12,
    bytes: grow Bytes max 5000,
) {
    append_after_growth(snapshot, output, region, text, bytes)
}

fn main() {
    var holder = Holder {
        snapshot: "read",
        output: "",
        text: "é",
        bytes: b"A",
        sibling: 73,
    }
    var region: Ascii max 262120 = "seed"
    forward(holder.snapshot, holder.output, region, holder.text, holder.bytes)
    print(holder.snapshot)
    print(holder.output)
    print(region)
    print(holder.text.len())
    print(holder.text.byte_len())
    print(holder.bytes.len())
    print(holder.sibling)
}
