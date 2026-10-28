fn through_parameter(value: byte) -> byte {
    value
}

fn main() {
    let low: byte = (byte)0
    let high: byte = (byte)255
    let wrapped_low: byte = unchecked((byte)256)
    let wrapped_high: byte = unchecked((byte)511)
    print(through_parameter(low))
    print(through_parameter(high))
    print(wrapped_low)
    print(wrapped_high)
}
