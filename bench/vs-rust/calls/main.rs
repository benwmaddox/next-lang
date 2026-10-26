#[derive(Clone, Copy)]
struct Data {
    a: i64,
    b: i64,
    c: i64,
    d: i64,
}

fn bump_field(data: &mut i64) {
    *data += 1;
}

fn process_value(v: i64) -> i64 {
    v * 2 + 1
}

fn main() {
    let mut items: Vec<Data> = Vec::with_capacity(1024);
    let mut seed: i64 = 1;

    for _index in 0..1024 {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let a = seed;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let b = seed;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let c = seed;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let d = seed;
        items.push(Data { a, b, c, d });
    }

    let mut checksum: i64 = 0;
    for _round in 0..200000 {
        for index in 0..1024 {
            bump_field(&mut items[index].a);
            bump_field(&mut items[index].b);
            bump_field(&mut items[index].c);
            bump_field(&mut items[index].d);
            checksum += process_value(items[index].a);
            checksum += process_value(items[index].b);
        }
    }

    println!("{}", checksum);
    println!("{}", items[0].a);
    println!("{}", items[1023].d);
}
