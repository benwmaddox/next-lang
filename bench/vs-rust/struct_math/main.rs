#[derive(Clone, Copy)]
struct Vec3 {
    x: i64,
    y: i64,
    z: i64,
}

fn add(a: Vec3, b: Vec3) -> Vec3 {
    Vec3 { x: (a.x + b.x) % 1000003, y: (a.y + b.y) % 1000003, z: (a.z + b.z) % 1000003 }
}

fn scale(a: Vec3, k: i64) -> Vec3 {
    Vec3 { x: (a.x * k) % 1000003, y: (a.y * k) % 1000003, z: (a.z * k) % 1000003 }
}

fn dot(a: Vec3, b: Vec3) -> i64 {
    (a.x * b.x + a.y * b.y + a.z * b.z) % 1000000007
}

fn main() {
    let mut p = Vec3 { x: 1, y: 2, z: 3 };
    let mut v = Vec3 { x: 7, y: 11, z: 13 };
    let mut seed: i64 = 1;
    let mut checksum: i64 = 0;
    for _step in 0..30000000 {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        let k = seed % 97 + 1;
        v = add(v, scale(p, k));
        p = add(p, v);
        checksum = (checksum * 31 + dot(p, v)) % 1000000007;
    }
    println!("{}", checksum);
    println!("{}", p.x);
    println!("{}", v.z);
}
