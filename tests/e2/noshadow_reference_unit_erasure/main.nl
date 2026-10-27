enum Wrap { Unit(()) }

fn bump(value: write int) { value += 1 }
fn sink(value: ()) {}

fn main() {
    var counter = 0
    sink(bump(counter))
    print(counter)

    let unit_value = bump(counter)
    sink(unit_value)
    print(counter)

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
