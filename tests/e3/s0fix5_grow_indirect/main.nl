fn fill(out: grow Ascii max 8) {
    discard out.try_append("x")
}

fn call(callback: fn(grow Ascii max 8), out: write Ascii max 2) {
    callback(out)
}

fn main() {
    let callback: fn(grow Ascii max 8) = fill
    var value: Ascii max 2 = ""
    call(callback, value)
}
