fn build_response(seed: i64) -> String {
    let count = (seed % 10) + 1;
    format!("{}|{}", count, seed % 100)
}

fn main() {
    let mut checksum: i64 = 0;
    let mut seed: i64 = 1;

    for _req_index in 0..1000000 {
        let mut items: Vec<i64> = Vec::new();
        let item_count = (seed % 256) + 1;

        for _i in 0..item_count {
            seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
            items.push(seed);
        }

        let mut req_checksum: i64 = 0;
        for item in items {
            req_checksum = (req_checksum.wrapping_mul(31).wrapping_add(item)) % 1000000007;
        }

        let resp = build_response(seed);
        checksum = (checksum.wrapping_mul(31).wrapping_add(req_checksum)) % 1000000007;
        checksum = (checksum.wrapping_mul(31).wrapping_add(resp.len() as i64)) % 1000000007;

        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
    }

    println!("{}", checksum);
}
