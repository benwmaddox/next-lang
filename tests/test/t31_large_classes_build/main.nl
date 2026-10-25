global values: list<Ascii max 8_388_608, 1> = list {}

test "an 8 MB collection layout with many size classes builds" {
    expect values.count() == 0L
}

fn main() {}
