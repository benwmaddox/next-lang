fn write_cell(g: write grid<long, 2, 2>, x: long, y: long) {
    g[x, y] = 9L
}

fn main() {
    var g: grid<long, 2, 2> = fill(1L)
    write_cell(g, 0L, 2L)
    print(g)
}
