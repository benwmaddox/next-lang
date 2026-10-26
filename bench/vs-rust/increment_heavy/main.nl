struct Inner {
    value: long
}

struct Middle {
    inner: Inner,
    count: long
}

struct Outer {
    middle: Middle,
    id: long
}

fn main() {
    var items: list<Outer, 512> = list {}
    var seed = 1L

    for index: long in 0L..512L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        discard items.push(Outer {
            id: seed,
            middle: Middle {
                count: seed * 2L,
                inner: Inner { value: seed * 3L }
            }
        })
    }

    var checksum = 0L
    for round: long in 0L..10000L {
        for index: long in 0L..512L {
            items[index].middle.inner.value += 1L
            items[index].middle.count += 1L
            items[index].id += 1L
            checksum += items[index].middle.inner.value
        }
    }

    print(checksum)
    print(items[0L].middle.inner.value)
    print(items[511L].id)
}
