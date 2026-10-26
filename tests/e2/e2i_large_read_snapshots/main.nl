struct Small { value: int = 0 }
struct Large { values: long[600] }

fn update_small(value: write Small) -> int {
    value.value = 9
    0
}

fn read_small(value: Small, marker: int) {
    print(value.value)
    print(marker)
}

fn update_large(value: write Large) -> int {
    value.values[0L] = 9L
    0
}

fn read_large(value: Large, marker: int) {
    print(value.values[0L])
    print(marker)
}

fn main() {
    var small = Small { value: 1 }
    read_small(small, update_small(small))
    print(small.value)

    var large: Large
    large.values[0L] = 1L
    read_large(large, update_large(large))
    print(large.values[0L])

}
