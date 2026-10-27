fn fail_after_write(value: write int) -> Result<(), Full> {
    value += 1
    var no_room: list<int, 0> = list {}
    no_room.push(8)?
    value += 100
    ok(())
}

fn return_after_write(value: write int) -> int {
    value += 2
    let absent: Option<int> = none
    let selected = absent ?? return 8
    value += selected
    0
}

fn main() {
    var value: int = 3
    print(fail_after_write(value))
    print(value)
    print(return_after_write(value))
    print(value)
}
