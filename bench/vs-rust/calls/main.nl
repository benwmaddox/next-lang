fn bump_field(data: write long) {
    data += 1L
}

fn process_value(v: long) -> long {
    v * 2L + 1L
}

struct Data {
    a: long,
    b: long,
    c: long,
    d: long
}

fn main() {
    var items: list<Data, 1024> = list {}
    var seed = 1L

    for index: long in 0L..1024L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let a = seed
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let b = seed
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let c = seed
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let d = seed
        discard items.push(Data { a, b, c, d })
    }

    var checksum = 0L
    for round: long in 0L..100L {
        for index: long in 0L..1024L {
            bump_field(items[index].a)
            bump_field(items[index].b)
            bump_field(items[index].c)
            bump_field(items[index].d)
            checksum += process_value(items[index].a)
            checksum += process_value(items[index].b)
        }
    }

    print(checksum)
    print(items[0L].a)
    print(items[1023L].d)
}
