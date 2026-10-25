fn main() {
    var output: Ascii max 24000000 = Ascii.empty()
    for index: long in 0L..3000000L {
        output += str(index) + ","
    }
    print(output.len())
}
