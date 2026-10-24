struct State { score: int }
struct Actions { bump: fn(write int) effects writes app.score }

global app: State = State { score: 0 }

fn bump(value: write int) {
    value += 1
    app.score += value
}

fn main() {
    let actions = Actions { bump: bump }
    var callbacks: list<fn(write int) effects writes app.score, 2> = list {}
    callbacks.push(bump).unwrap()
    var value = 0
    callbacks[0L](value)
    actions.bump(value)
    print(value)
    print(app.score)
}
