struct Vec3 {
    x: long,
    y: long,
    z: long
}

fn add(a: Vec3, b: Vec3) -> Vec3 {
    Vec3 { x: (a.x + b.x) % 1000003L, y: (a.y + b.y) % 1000003L, z: (a.z + b.z) % 1000003L }
}

fn scale(a: Vec3, k: long) -> Vec3 {
    Vec3 { x: (a.x * k) % 1000003L, y: (a.y * k) % 1000003L, z: (a.z * k) % 1000003L }
}

fn dot(a: Vec3, b: Vec3) -> long {
    (a.x * b.x + a.y * b.y + a.z * b.z) % 1000000007L
}

fn main() {
    var p = Vec3 { x: 1L, y: 2L, z: 3L }
    var v = Vec3 { x: 7L, y: 11L, z: 13L }
    var seed = 1L
    var checksum = 0L
    for step: long in 0L..30000000L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let k = seed % 97L + 1L
        v = add(v, scale(p, k))
        p = add(p, v)
        checksum = (checksum * 31L + dot(p, v)) % 1000000007L
    }
    print(checksum)
    print(p.x)
    print(v.z)
}
