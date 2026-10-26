enum Wrap { Unit(()) }

fn bump(value: write int) { value += 1 }
fn sink(value: ()) {}

fn main() {
    var count = 0
    sink(bump(count))
    print(count)

    let unit_value = bump(count)
    sink(unit_value)
    print(count)

    let wrapped = Wrap.Unit(())
    print(Wrap.Unit(()))
    print(wrapped)

    let optional: Option<()> = some(())
    print(optional)
    match optional {
        some(value) => sink(value)
        none => ()
    }
    match optional {
        some(_) => print(true)
        none => print(false)
    }
}
