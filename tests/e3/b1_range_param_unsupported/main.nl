type Slot = long 0..=512

fn show(s: Slot) -> long {
    s
}

fn main() {
    print(show((Slot)(4L)))
}
