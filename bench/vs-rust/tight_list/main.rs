fn main() {
    let mut values: Vec<i64> = Vec::with_capacity(100000);
    let mut seed: i64 = 1;

    for _index in 0..100000 {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        values.push(seed);
    }

    let mut checksum: i64 = 0;
    for round in 0..10000i64 {
        for index in 0..100000 {
            let v = values[index] + round;
            if v % 2 == 0 {
                checksum += v;
            } else {
                checksum -= v;
            }
        }
    }

    println!("{}", checksum);
    println!("{}", values[0]);
    println!("{}", values[99999]);
}
