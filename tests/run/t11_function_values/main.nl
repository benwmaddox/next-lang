struct Ops {
    add: fn(int, int) -> int,
    run: fn() -> int
}

struct OwnerNode<P> { value: long }
struct OwnerState<P> { nodes: pool<OwnerNode<P>, 1, P>, score: int }

global global_add: fn(int, int) -> int = add
global app: OwnerState<app.nodes> = OwnerState { nodes: pool {}, score: 0 }

fn add(a: int, b: int) -> int { a + b }
fn subtract(a: int, b: int) -> int { a - b }
fn increment(value: int) -> int { value + 1 }
fn zero() -> int { 77 }
fn announce(value: int) -> int {
    print(value)
    value
}
fn owner_value(id: Id<app.nodes>) -> long {
    app.nodes.get(id).unwrap().value
}
fn update_score(value: int) { app.score = value }

fn choose_add() -> fn(int, int) -> int { add }
fn apply(f: fn(int, int) -> int, a: int, b: int) -> int { f(a, b) }

fn main() {
    let local = add
    print(local(20, 22))
    print(apply(add, 3, 4))

    let returned = choose_add()
    print(returned(5, 6))

    let ops = Ops { add: add, run: zero }
    print(ops.add(7, 8))
    print(ops.run())

    let array: (fn(int, int) -> int)[2] = fill(add)
    print(array[0L](9, 10))

    var list: list<fn(int, int) -> int, 2> = list {}
    list.push(subtract).unwrap()
    print(list[0L](12, 5))

    var map: map<int, fn(int, int) -> int, 2> = map {}
    map.set(1, add).unwrap()
    let mapped = map.get(1) ?? subtract
    print(mapped(11, 12))

    print(global_add(13, 14))
    let print_allowed: fn(int) -> int effects print = increment
    print(print_allowed(14))

    let printer: fn(int) -> int effects print = announce
    print(printer(16))
    print(add == add)
    print(add == subtract)
    print(add)
    print(announce)

    let owner_callback: fn(Id<app.nodes>) -> long effects reads app = owner_value
    let owner_id: Id<app.nodes> = app.nodes.add(OwnerNode { value: 31L }).unwrap()
    print(owner_callback(owner_id))

    let writer: fn(int) -> () effects writes app.score = update_score
    writer(35)
    print(app.score)
}
