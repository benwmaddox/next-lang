enum Kind { A, B, C }

fn main() {
    let k = Kind.A
    let v = match k {
        A | B => 1
    }
    print(v)
}
