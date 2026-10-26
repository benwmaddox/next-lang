enum Choice { Yes, No }

fn partial(choice: Choice) -> int {
    match choice {
        Yes => return 4
        No => 5
    }
}

fn all_never(choice: Choice) {
    match choice {
        Yes => return
        No => return
    }
}

fn main() {
    print(partial(Choice.Yes))
    print(partial(Choice.No))
    all_never(Choice.No)
    print(77)
}
