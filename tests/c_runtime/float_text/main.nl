fn fixed(x: double, digits: int) {
    print(str_fixed(x, digits))
}

fn show(text: Ascii max 40) {
    match text.parse_double() {
        some(v) => print(str_fixed(v, 6)),
        none => print("none"),
    }
}

fn main() {
    fixed(0.0, 3)
    fixed(-0.0, 2)
    fixed(1.5, 0)
    fixed(2.5, 0)
    fixed(0.5, 0)
    fixed(3.14159, 3)
    fixed(0.1, 17)
    fixed(0.1 + 0.2, 17)
    fixed(123456789.123456789, 9)
    fixed(-0.00000001, 7)
    fixed(0.000001, 5)
    fixed(1.0e18, 2)
    fixed(999999.9999999, 3)
    fixed(0.045, 2)
    fixed(0.055, 2)
    fixed(5.0e-324, 19)
    fixed(2.0e-6, 6)
    fixed(1234567.5, 0)
    fixed(7.0, 10)
    fixed(-12.375, 2)
    show("0")
    show("1.5")
    show("-2.25")
    show("+7")
    show("1e3")
    show("1.5e-3")
    show("123456.789")
    show("0.1")
    show(".5")
    show("5.")
    show("0.000001")
    show("12345678901234.5")
    show("1e15")
    show("100000000000000000")
    show("-0")
    show("abc")
    show("")
    show("1.2.3")
    show("-")
    show("1e")
    show("1e+")
    show("0x10")
    show("1 ")
}
