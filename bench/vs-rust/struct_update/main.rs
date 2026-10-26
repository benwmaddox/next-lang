#[derive(Clone, Copy)]
struct Particle {
    x: i64,
    y: i64,
    vx: i64,
    vy: i64,
}

fn main() {
    let mut particles: Vec<Particle> = Vec::with_capacity(4096);
    let mut seed: i64 = 1;

    for _index in 0..4096 {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let x = seed;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let y = seed;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let vx = (seed % 100) - 50;
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
        let vy = (seed % 100) - 50;
        particles.push(Particle { x, y, vx, vy });
    }

    let mut checksum: i64 = 0;
    for _round in 0..300000 {
        for index in 0..4096 {
            particles[index].x += particles[index].vx;
            particles[index].y += particles[index].vy;
            checksum += particles[index].x + particles[index].y;
        }
    }

    println!("{}", checksum);
    println!("{}", particles[0].x);
    println!("{}", particles[4095].y);
}
