struct Unit { hp: int = 0 }

fn update(hp: write int) -> int {
    hp = 9
    0
}

fn observe(unit: write Unit, marker: int) {
    print(unit.hp)
    print(marker)
}

fn main() {
    var units: list<Unit, 1> = list {}
    discard units.push(Unit { hp: 1 })
    observe(units[0L], update(units[0L].hp))
    print(units[0L].hp)
}
