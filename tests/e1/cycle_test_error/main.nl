fn first() -> int { second() }
fn second() -> int { first() }
fn main() {}

test "body error precedes cycle" {
    print(missing_name)
}
