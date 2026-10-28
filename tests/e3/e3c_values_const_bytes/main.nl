const SIGNATURE: Ascii max 4 = "HEAD"

fn main() {
    let raw = SIGNATURE.bytes()
    print(raw.len())
}
