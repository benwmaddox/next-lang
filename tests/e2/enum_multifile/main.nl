fn transform(value: Wire) -> Wire {
    match value {
        Packet(packet) => Wire.Packet(Packet { accepted: packet.accepted, code: packet.code + 1 })
        Empty => Wire.Empty
    }
}

fn main() {
    let value = transform(Wire.Packet(Packet { accepted: true, code: 41 }))
    print(value)
    print(value == Wire.Packet(Packet { accepted: true, code: 42 }))
}
