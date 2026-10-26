fn format_record(id: i64, value: i64, name: i64) -> String {
    format!("{}:{}={}", id, value, name)
}

fn main() {
    let mut checksum: i64 = 0;
    let mut seed: i64 = 1;

    for _batch in 0..400 {
    let mut output = String::new();
    for _i in 0..100000 {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let id = seed;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let value = seed % 10000;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let name = seed % 1000;

        let line = format_record(id, value, name);
        output.push_str(&line);
        output.push(',');

        let line_len = line.len() as i64;
        checksum = (checksum.wrapping_mul(31).wrapping_add(line_len)) % 1000000007;
        checksum = (checksum.wrapping_mul(31).wrapping_add(value)) % 1000000007;
        checksum = (checksum.wrapping_mul(31).wrapping_add(name)) % 1000000007;
    }
    checksum = (checksum.wrapping_mul(31).wrapping_add(output.len() as i64)) % 1000000007;
    }

    println!("{}", checksum);
}
