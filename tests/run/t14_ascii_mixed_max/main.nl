enum TextValue { Value(Ascii max 4) }

struct TextRecord { value: Ascii max 4 }

fn label(n: int 0..=999) -> Ascii max 10 { "#" + str(n) }

fn narrow_result() -> Ascii max 10 { "callback" }

fn option_result() -> Option<Ascii max 4> { some("ab") }

fn wide_result() -> Ascii max 20 { narrow_result() }

fn via_callback(callback: fn() -> Ascii max 20) -> Ascii max 20 {
    callback()
}

fn read_wide(value: Ascii max 20) -> Ascii max 20 { value }

fn main() {
    let x: Ascii max 10 = "ab"
    let y: Ascii max 20 = "ab"
    let z: Ascii max 30 = "ac"

    print(x == "ab")
    print(label(4) == "#4")
    print(x == y)
    print(x != y)
    print(x < z)
    print(x <= y)
    print(z > x)
    print(y >= x)
    print(label(42) == "#42")

    print(read_wide(x))
    print(via_callback(narrow_result))

    let chosen = if true { x } else { y }
    print(chosen)
    var target: Ascii max 20 = "before"
    target = x
    print(target)
    print(x + y)

    let maybe_small: Option<Ascii max 10> = some("ab")
    let maybe_wide: Option<Ascii max 20> = some("ab")
    print(maybe_small == maybe_wide)
    print(maybe_small != maybe_wide)
    match maybe_small {
        some(value) => print(value == y),
        none => print(false)
    }

    let o = option_result()
    let tiny: Ascii max 2 = "ab"
    print(o == some("ab"))
    print(o != some("cd"))
    print(some("ab") == o)
    print(some("cd") != o)
    print(o == some(tiny))
    print(o == none)
    let r: Result<Ascii max 4, int> = ok("ab")
    print(r == ok("ab"))
    print(r == ok(tiny))
    print(r == err(3))
    let text: TextValue = TextValue.Value("ab")
    print(text == TextValue.Value("ab"))
    print(text == TextValue.Value(tiny))
    let record = TextRecord { value: "ab" }
    print(TextRecord { value: "ab" } == record)
    let nested: Option<Option<Ascii max 4> > = some(some("ab"))
    print(nested == some(some("ab")))

    var indexed: map<Ascii max 20, int, 2> = map {}
    indexed.set("ab", 1).unwrap()
    let short_key: Ascii max 10 = "ab"
    print(indexed.contains(short_key))
    indexed.set(short_key, 2).unwrap()
    print(indexed.get("ab"))
    indexed.set("bc", 3).unwrap()
    indexed.remove(short_key)
    indexed.set("cd", 4).unwrap()
    print(indexed.get("bc"))
    print(indexed.get("cd"))

    var stable: map<Ascii max 20, int, 1> = map {}
    var mutable_key: Ascii max 10 = "keep"
    stable.set(mutable_key, 9).unwrap()
    mutable_key = "lost"
    print(stable.get("keep"))

    var names: set<Ascii max 20, 2> = set {}
    names.add("ab").unwrap()
    print(names.contains(short_key))
    names.add(short_key).unwrap()
    print(names.count())
    print(names.remove(short_key))
    print(names.count())
}
