#[derive(Clone, Copy)]
struct Inner {
    value: i64,
}

#[derive(Clone, Copy)]
struct Middle {
    inner: Inner,
    count: i64,
}

#[derive(Clone, Copy)]
struct Outer {
    middle: Middle,
    id: i64,
}

fn main() {
    let mut items: Vec<Outer> = Vec::with_capacity(512);
    let mut seed: i64 = 1;

    for _index in 0..512 {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        items.push(Outer {
            id: seed,
            middle: Middle {
                count: seed * 2,
                inner: Inner { value: seed * 3 },
            },
        });
    }

    let mut checksum: i64 = 0;
    for _round in 0..2000000 {
        for index in 0..512 {
            items[index].middle.inner.value += 1;
            items[index].middle.count += 1;
            items[index].id += 1;
            checksum += items[index].middle.inner.value;
        }
    }

    println!("{}", checksum);
    println!("{}", items[0].middle.inner.value);
    println!("{}", items[511].id);
}
