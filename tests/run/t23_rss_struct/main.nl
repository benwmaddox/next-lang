struct Holder { values: list<long, 6000000> = list {} }

fn main() {
    var holder: Holder = Holder {}
    discard holder.values.push(24L)
    print(holder.values[0L])
}
