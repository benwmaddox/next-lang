const FORWARD: int = BASE + 5
const MINIMUM: int = -2147483648
const MAXIMUM: int = 2147483647
const DIFFERENCE: int = FORWARD - BASE
const PRODUCT: int = BASE * 2
const QUOTIENT: int = -7 / 2
const REMAINDER: int = -7 % 2
const MIN_REMAINDER: int = MINIMUM % -1
const WIDE: long = 2147483648
const CAPACITY: int = 3

fn identity(value: int) -> int { value }
fn from_constant() -> int { FORWARD }

fn main() {
    print(MINIMUM)
    print(MAXIMUM)
    print(FORWARD)
    print(DIFFERENCE)
    print(PRODUCT)
    print(QUOTIENT)
    print(REMAINDER)
    print(MIN_REMAINDER)
    print(WIDE)
    print(identity(FORWARD))
    print(from_constant())

    let fixed: int[CAPACITY] = [BASE, FORWARD, MAXIMUM]
    print(fixed.len())
    print(fixed[1L])

    var growing: list<int, CAPACITY> = list {}
    discard growing.push(MINIMUM)
    discard growing.push(identity(BASE))
    print(growing.count())
    print(growing[1L])
}
