fn compare(left: byte, right: byte) {
    print(left < right)
    print(left <= right)
    print(left > right)
    print(left >= right)
}

fn main() {
    let zero: byte = 0
    let low: byte = 127
    let high: byte = 128
    let max: byte = 255

    compare(zero, low)
    compare(low, low)
    compare(high, low)
    compare(max, high)

    print(zero < 127)
    print(0 < low)
    print(high > 127)
    print(max >= 255)
}
