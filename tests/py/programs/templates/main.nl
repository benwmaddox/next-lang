// Templates compile to straight-line appends into a bounded Bytes, escaping by context.
struct Row {
    key: long
    found: bool
    name: Bytes max 16
}

fn show_html(env: Env, body: Bytes max 400) {
    match env.out.write(body) {
        ok(_) => {},
        err(_) => {},
    }
    match env.out.write("\n") {
        ok(_) => {},
        err(_) => {},
    }
}

fn show_json(env: Env, body: Bytes max 300) {
    match env.out.write(body) {
        ok(_) => {},
        err(_) => {},
    }
    match env.out.write("\n") {
        ok(_) => {},
        err(_) => {},
    }
}

fn main(env: Env) {
    var name: Bytes max 16 = Bytes.empty()
    discard name.try_append("a<b>&\"c'\\ \n".bytes())
    let row = Row { key: 42L, found: true, name: name }
    var html: Bytes max 400 = Bytes.empty()
    render_page(html, row, 1234L)
    show_html(env, html)
    var gone: Bytes max 400 = Bytes.empty()
    render_page(gone, Row { key: -7L, found: false, name: Bytes.empty() }, 0L)
    show_html(env, gone)
    var json: Bytes max 300 = Bytes.empty()
    render_item(json, row)
    show_json(env, json)
}
