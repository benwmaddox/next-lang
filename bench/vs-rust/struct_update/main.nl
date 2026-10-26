struct Particle {
    x: long,
    y: long,
    vx: long,
    vy: long
}

fn main() {
    var particles: list<Particle, 4096> = list {}
    var seed = 1L

    for index: long in 0L..4096L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let x = seed
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let y = seed
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let vx = (seed % 100L) - 50L
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let vy = (seed % 100L) - 50L
        discard particles.push(Particle { x, y, vx, vy })
    }

    var checksum = 0L
    for round: long in 0L..300000L {
        for index: long in 0L..4096L {
            particles[index].x += particles[index].vx
            particles[index].y += particles[index].vy
            checksum += particles[index].x + particles[index].y
        }
    }

    print(checksum)
    print(particles[0L].x)
    print(particles[4095L].y)
}
