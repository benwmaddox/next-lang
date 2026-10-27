enum Failure { Bad }

fn main() {
    let absent: Option<int> = none()
    let present = some(7)
    print(absent)
    print(present)
    print(absent.is_none())
    print(present.is_some())

    let failure: Result<int, Failure> = err(Failure.Bad)
    let success: Result<int, Failure> = ok(9)
    print(failure)
    print(success)
    print(failure.is_err())
    print(success.is_ok())
    print(failure.ok())
    print(success.ok())
    print(success.unwrap())

    let nested: Option<Result<int, Failure>> = some(failure)
    print(nested)
    print(nested == some(err(Failure.Bad)))
    print(match nested {
        Option.some(value) => value.is_err(),
        Option.none => false
    })
    print(match success {
        Result.ok(value) => value,
        Result.err(_) => 0
    })

    let unit_some: Option<()> = some(())
    let unit_none: Option<()> = none
    let unit_ok: Result<(), ()> = ok(())
    let unit_err: Result<(), ()> = err(())
    print(unit_some)
    print(unit_none)
    print(unit_ok)
    print(unit_err)
}
