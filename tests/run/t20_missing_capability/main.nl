fn read_file() {
    var buffer: list<byte, 8> = list {}
    discard fs.read("file", buffer)
}

fn main() {
    read_file()
}
