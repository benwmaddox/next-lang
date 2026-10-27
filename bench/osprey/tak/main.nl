fn sub(a: long, b: long) -> long {
    a - b
}

recursive fn tak(x: long, y: long, z: long) -> long {
    if x > y {
        tak(tak(sub(x, 1L), y, z), tak(sub(y, 1L), z, x), tak(sub(z, 1L), x, y))
    } else {
        z
    }
}

fn main() {
    print(tak(32L, 16L, 8L))
}
