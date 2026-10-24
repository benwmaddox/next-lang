enum Failure { Missing, Full }
fn widen(input: Result<int, Failure>) -> Result<long, Failure> {
    for outer in 0..2 {
        for inner in 0..2 {
            let value = input?
            if inner == 0 { continue }
            return ok(value.to_long())
        }
    }
    ok(0L)
}
fn option_question(input: Option<int>) -> Option<int> { some(input?) }
fn take_or(input: Result<Option<int>, Failure>) -> Result<int, Failure> {
    ok(input? ?? 0)
}
fn ensure(input: Option<int>) -> int { input ?? return 7 }
fn nested_return(input: Option<int>) -> int {
    for i in 0..2 {
        for j in 0..2 {
            let value = input ?? return 9
            if j == 1 { return value }
        }
    }
    0
}
fn result_fallback(input: Result<int, Failure>) -> Result<int, Failure> {
    ok(input.ok() ?? return err(Failure.Full))
}
fn default_value() -> int { print(77); 7 }
fn with_default(input: Option<int>) -> int { input ?? default_value() }
fn continue_sum() -> int {
    var total: int = 0
    for i in 0..5 {
        let candidate: Option<int> = if i == 2 { none } else { some(i) }
        let value = candidate ?? continue
        total += value
    }
    total
}
fn nested_break() -> int {
    var total: int = 0
    for i in 0..3 {
        for j in 0..3 {
            let candidate: Option<int> = if j == 1 { none } else { some(j) }
            let value = candidate ?? break
            total += value
        }
        total += 10
    }
    total
}
fn nested_continue() -> int {
    var total: int = 0
    for i in 0..2 {
        for j in 0..3 {
            let candidate: Option<int> = if j == 1 { none } else { some(j) }
            let value = candidate ?? continue
            total += value
        }
    }
    total
}
fn main() {
    print(widen(ok(6)))
    print(widen(err(Failure.Missing)))
    print(option_question(some(3)))
    print(option_question(none))
    print(take_or(ok(some(5))))
    print(take_or(ok(none)))
    print(take_or(err(Failure.Missing)))
    print(ensure(some(8)))
    print(ensure(none))
    print(nested_return(some(6)))
    print(nested_return(none))
    print(with_default(some(4)))
    print(with_default(none))
    print(result_fallback(ok(5)))
    print(result_fallback(err(Failure.Missing)))
    print(continue_sum())
    print(nested_break())
    print(nested_continue())
}
