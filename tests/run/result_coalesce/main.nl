enum Failure { Bad }
fn text_or_default(value: Result<Ascii max 4, Failure>) -> Ascii max 10 {
    value ?? "fallback"
}
fn main() {
    print(text_or_default(ok("one")))
}
