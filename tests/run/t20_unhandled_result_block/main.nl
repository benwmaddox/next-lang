fn fail() -> Result<(), int> {
    err(3)
}

fn main() {
    { fail() }
}
