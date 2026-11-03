// A tour of the language as the self-hosted compiler accepts it today. docs/LANGUAGE.md explains each piece, and
// tests/py/test_docs.py builds and tests this package, so it stays true. Run it with: scripts/nlc run docs/examples/tour
const LIMIT: long = 3L                         // constants name their type; `L` makes a long literal

enum Kind { Low, High(int) }                   // cases may carry values
enum Oops { Negative, TooBig }

// Every field has a bound the compiler knows: `max 16` text, `list<long, 4>` at most four longs. Defaults let `Unit {}` work.
struct Unit {
    name: Ascii max 16 = "x"
    hp: int = 10
    items: list<long, 4> = list {}
}

// Interpolation builds the text in place; its maximum length is worked out at build time.
fn describe(u: Unit) -> Ascii max 64 {
    $"{u.name}: {u.hp} hp"
}

// A function changes only what it is given as `write`.
fn hurt(u: write Unit, amount: int) {
    u.hp = u.hp - amount
}

fn classify(n: int) -> Kind { if n > 5 { Kind.High(n) } else { Kind.Low } }

fn level(k: Kind) -> int {
    match k {                                  // a match must cover every case
        Low => 0
        High(n) => n
    }
}

// Result and `?`: the error is returned to the caller at once.
fn check(n: int) -> Result<int, Oops> {
    if n < 0 { return err(Oops.Negative) }
    if n > 100 { return err(Oops.TooBig) }
    ok(n)
}

fn doubled(n: int) -> Result<int, Oops> {
    let value = check(n)?
    ok(value * 2)
}

// Option and `??`: use the value, or the fallback (which may be a `return`, `break` or `continue`).
fn first_item(u: Unit) -> long {
    for item in u.items { return item }
    0L
}

fn or_zero(o: Option<int>) -> int { o ?? 0 }

fn total(u: Unit) -> long {
    var sum = 0L
    for item in u.items { sum += item }       // loops over a list borrow each element
    sum
}

fn main() {
    var u = Unit { name: "bob" }
    hurt(u, 3)
    print(describe(u))                         // bob: 7 hp
    discard u.items.push(7L)                   // push can fail with Full; `discard` says that is fine here
    discard u.items.push(LIMIT)
    print(total(u))                            // 10
    print(level(classify(9)))                  // 9
    print(doubled(4))                          // ok(8)
    print(doubled(-1))                         // err(Negative)
    print(or_zero(none))                       // 0
    var i = 0
    while i < 3 { i += 1 }
    for n in 0..3 { i += n }                   // 0..3 is 0, 1, 2; 0..=3 includes 3
    print(i)                                   // 6
    let word: Ascii max 8 = "a1"
    print(word[1] == "1")                      // true: word[i] is one character, an Ascii max 1
    print(word[1].to_byte())                   // 49: its byte
    let flags: uint = 4000000000u              // uint, ulong, ushort, short, sbyte: `5u` is a uint, `5UL` a ulong
    print(flags + 294967295u)                  // 4294967295; one more would fail, and so would 0u - 1u
    print(0u -% 1u)                            // 4294967295: `+%` `-%` `*%` wrap at the type's width
    print((ulong)flags * 4UL)                  // 16000000000: conversions are casts, checked when narrowing
    print(unchecked((uint)(0 - 1)))            // 4294967295: unchecked keeps the low bits
}

// Tests live in the same package; `scripts/nlc test <package>` runs each in its own process.
test "hurt lowers hp" {
    var u = Unit {}
    hurt(u, 4)
    expect u.hp == 6
}

test "a bad input is an error, not a crash" {
    expect doubled(-5) == err(Oops.Negative)
    expect doubled(500) == err(Oops.TooBig)
    expect doubled(5) == ok(10)
}
