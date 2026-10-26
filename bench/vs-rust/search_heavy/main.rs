fn main() {
    let mut values: Vec<i64> = Vec::with_capacity(10000);
    let mut seed: i64 = 1;

    for _index in 0..10000 {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        values.push(seed);
    }

    values.sort_unstable();

    let mut checksum: i64 = 0;
    let mut seed2: i64 = 42;
    for _round in 0..1000 {
        seed2 = (seed2.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let target = seed2 % 2147483648;
        let found = match values.binary_search(&target) {
            Ok(idx) => idx as i64,
            Err(_) => -1,
        };
        checksum += found;
    }

    println!("{}", checksum);
    println!("{}", values[0]);
    println!("{}", values[9999]);
}
