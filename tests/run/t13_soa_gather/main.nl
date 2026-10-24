struct Big { xs: long[1000], n: int }
struct Exact { xs: long[512] }
struct Over { xs: long[512], n: long }
struct Holder { value: Big }

fn first(b: Big) -> long { b.xs[0] + b.n.to_long() }

fn bump(b: write Big) { b.n += 1 }

fn bump_then_fail(b: write Big) -> Option<int> {
    b.n += 1
    let missing: Option<int> = none
    let value = missing?
    some(value)
}

fn pick(c: bool, a: Big, b: Big) -> Big {
    if c { a } else { b }
}

fn mk(v: long) -> Big { Big { xs: fill(v), n: 0 } }

fn exact_first(value: Exact) -> long { value.xs[511] }
fn over_first(value: Over) -> long { value.xs[511] + value.n }
fn list_element(values: list<Big, 1>) -> Big { values[0] }
fn forward_element(values: list<Big, 1>) -> long { first(values[0]) }
fn inner_count(values: list<long, 600>) -> long { values.count() }
fn optional_first(value: Option<Big>) -> Option<long> { value?.first() }
fn match_first(values: list<Option<Big>, 1>) -> long {
    match values[0] {
        some(value) => first(value),
        none => -1L
    }
}

fn main() {
    var read_list: list<Big, 3> = list {}
    discard read_list.push(mk(4L))
    print(first(read_list[0]))

    var write_list: list<Big, 3> = list {}
    discard write_list.push(mk(8L))
    bump(write_list[0])
    print(write_list[0].n)

    var loop_list: list<Big, 3> = list {}
    discard loop_list.push(mk(5L))
    for b in loop_list { print(first(b)) }

    var arr: Big[3] = fill(mk(7L))
    let d = mk(3L)
    arr[1] = pick(true, arr[0], d)
    print(first(arr[1]))

    var pool_values: pool<Big, 1> = pool {}
    discard pool_values.add(mk(11L))
    for value, id in pool_values { print(first(value)) }

    var map_values: map<int, Big, 1> = map {}
    map_values.set(1, mk(13L)).unwrap()
    for value, key in map_values { print(first(value)) }

    var write_loop: list<Big, 2> = list {}
    discard write_loop.push(mk(20L))
    discard write_loop.push(mk(30L))
    for b in write_loop { bump(b) }
    print(write_loop[0].n)
    print(write_loop[1].n)

    var failed_write: list<Big, 1> = list {}
    discard failed_write.push(mk(40L))
    let failed = bump_then_fail(failed_write[0])
    print(failed.is_none())
    print(failed_write[0].n)

    var exact_values: list<Exact, 1> = list {}
    discard exact_values.push(Exact { xs: fill(6L) })
    print(exact_first(exact_values[0]))

    var over_values: list<Over, 1> = list {}
    discard over_values.push(Over { xs: fill(9L), n: 2L })
    print(over_first(over_values[0]))
    print(over_values[0])

    var return_values: list<Big, 1> = list {}
    discard return_values.push(mk(17L))
    let returned = list_element(return_values)
    print(returned.xs[999])
    print(forward_element(return_values))

    let holder = Holder { value: return_values[0] }
    print(holder.value.xs[1])
    var copied_values: list<Big, 1> = list {}
    discard copied_values.push(return_values[0])
    print(copied_values[0].xs[2])
    print(return_values[0] == copied_values[0])

    var optional_values: list<Option<Big>, 1> = list {}
    discard optional_values.push(some(mk(24L)))
    print(optional_first(optional_values[0]))
    print(match_first(optional_values))

    var queue_values: queue<Big, 2> = queue {}
    discard queue_values.push(mk(21L))
    for value in queue_values { print(first(value)) }

    var ring_values: ring<Big, 2> = ring {}
    ring_values.push(mk(22L))
    for value in ring_values { print(first(value)) }

    var grid_values: grid<Big, 1, 1> = fill(mk(23L))
    for value, x, y in grid_values { print(first(value)) }

    var nested_values: list<list<long, 600>, 2> = list {}
    var inner: list<long, 600> = list {}
    discard inner.push(73L)
    discard nested_values.push(inner)
    print(inner_count(nested_values[0]))
    print(nested_values[0][0])
}
