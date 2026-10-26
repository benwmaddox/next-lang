global values: list<long, 600> = [1L]

fn update_list(values: write list<long, 600>) -> int {
    values[0L] = 9L
    0
}

fn read_list(values: list<long, 600>, marker: int) {
    print(values[0L])
    print(marker)
}

fn main() {
    read_list(values, update_list(values))
    print(values[0L])
}
