enum Label { Short, Longer }

fn label(value: Label) -> Ascii max 16 {
    match value {
        Label.Short => "tiny",
        Label.Longer => "a longer label",
    }
}

fn main() {
    print(label(Label.Short))
    print(label(Label.Longer))
}
