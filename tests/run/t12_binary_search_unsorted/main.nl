fn main() {
    var values: long[3] = fill(0L)
    values[0L] = 2L
    values[1L] = 1L
    values[2L] = 3L
    print(binary_search(values, 2L))
}
