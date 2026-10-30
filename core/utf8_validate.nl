// Boundary validator for UTF-8. Returns the byte utf8_cursor of the utf8_lead invalid
// sequence, or byte_count when the complete slice is well-formed.
fn utf8_error_offset(data: sys.Addr, byte_count: long) -> long {
    var utf8_cursor = 0L
    while utf8_cursor < byte_count {
        let utf8_lead = sys.load8(data, utf8_cursor)
        var utf8_width = 0L
        if utf8_lead <= 127 { utf8_width = 1L }
        else if utf8_lead >= 194 && utf8_lead <= 223 { utf8_width = 2L }
        else if utf8_lead >= 224 && utf8_lead <= 239 { utf8_width = 3L }
        else if utf8_lead >= 240 && utf8_lead <= 244 { utf8_width = 4L }
        else { return utf8_cursor }
        if byte_count - utf8_cursor < utf8_width { return utf8_cursor }
        if utf8_width >= 2L {
            let utf8_second = sys.load8(data, utf8_cursor + 1L)
            if utf8_second < 128 || utf8_second > 191 { return utf8_cursor }
            if utf8_lead == 224 && utf8_second < 160 { return utf8_cursor }
            if utf8_lead == 237 && utf8_second > 159 { return utf8_cursor }
            if utf8_lead == 240 && utf8_second < 144 { return utf8_cursor }
            if utf8_lead == 244 && utf8_second > 143 { return utf8_cursor }
        }
        if utf8_width >= 3L {
            let utf8_third = sys.load8(data, utf8_cursor + 2L)
            if utf8_third < 128 || utf8_third > 191 { return utf8_cursor }
        }
        if utf8_width == 4L {
            let utf8_fourth = sys.load8(data, utf8_cursor + 3L)
            if utf8_fourth < 128 || utf8_fourth > 191 { return utf8_cursor }
        }
        utf8_cursor += utf8_width
    }
    byte_count
}

fn non_ascii_offset(data: sys.Addr, byte_count: long) -> long {
    for utf8_cursor in 0L..byte_count {
        if sys.load8(data, utf8_cursor) >= 128 { return utf8_cursor }
    }
    byte_count
}
