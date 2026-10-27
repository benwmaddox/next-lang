fn token_kind_name(kind: TokenKind) -> Ascii max 20 {
    match kind {
        TokenKind.Ident => "Ident",
        TokenKind.Number => "Number",
        TokenKind.String => "String",
        TokenKind.Newline => "Newline",
        TokenKind.LParen => "LParen",
        TokenKind.RParen => "RParen",
        TokenKind.LBrace => "LBrace",
        TokenKind.RBrace => "RBrace",
        TokenKind.LBracket => "LBracket",
        TokenKind.RBracket => "RBracket",
        TokenKind.Comma => "Comma",
        TokenKind.Colon => "Colon",
        TokenKind.Semicolon => "Semicolon",
        TokenKind.Dot => "Dot",
        TokenKind.Question => "Question",
        TokenKind.QuestionDot => "QuestionDot",
        TokenKind.QuestionQuestion => "QuestionQuestion",
        TokenKind.Range => "Range",
        TokenKind.RangeInclusive => "RangeInclusive",
        TokenKind.Arrow => "Arrow",
        TokenKind.FatArrow => "FatArrow",
        TokenKind.Plus => "Plus",
        TokenKind.Minus => "Minus",
        TokenKind.Star => "Star",
        TokenKind.Slash => "Slash",
        TokenKind.Percent => "Percent",
        TokenKind.WrapPlus => "WrapPlus",
        TokenKind.WrapMinus => "WrapMinus",
        TokenKind.WrapStar => "WrapStar",
        TokenKind.PlusEq => "PlusEq",
        TokenKind.MinusEq => "MinusEq",
        TokenKind.StarEq => "StarEq",
        TokenKind.SlashEq => "SlashEq",
        TokenKind.PercentEq => "PercentEq",
        TokenKind.ShrEq => "ShrEq",
        TokenKind.ShlEq => "ShlEq",
        TokenKind.AndEq => "AndEq",
        TokenKind.OrEq => "OrEq",
        TokenKind.CaretEq => "CaretEq",
        TokenKind.Eq => "Eq",
        TokenKind.EqEq => "EqEq",
        TokenKind.Bang => "Bang",
        TokenKind.BangEq => "BangEq",
        TokenKind.Tilde => "Tilde",
        TokenKind.Lt => "Lt",
        TokenKind.Le => "Le",
        TokenKind.Gt => "Gt",
        TokenKind.Ge => "Ge",
        TokenKind.And => "And",
        TokenKind.AndAnd => "AndAnd",
        TokenKind.Or => "Or",
        TokenKind.OrOr => "OrOr",
        TokenKind.Caret => "Caret",
        TokenKind.Shl => "Shl",
        TokenKind.Shr => "Shr",
        TokenKind.Eof => "Eof",
    }
}

fn output_token_dump(
    out: Out,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
) -> Result<(), IoError> {
    var buffer: Bytes max OUTPUT_BUFFER_BYTES = Bytes.empty()
    for file_index in 0L..files.count() {
        let file = files[file_index]
        if buffer.count() > OUTPUT_BUFFER_BYTES - 64L {
            out.write(buffer)?
            buffer = Bytes.empty()
        }
        let header = b"file "
        for header_index in 0L..header.count() { buffer.push(header[header_index]).unwrap() }
        if buffer.count() >= OUTPUT_BUFFER_BYTES { out.write(buffer)?; buffer = Bytes.empty() }
        buffer.push(34).unwrap()
        for name_index in 0L..file.name.count() {
            let byte_value = file.name[name_index]
            if byte_value == 34 || byte_value == 92 || byte_value == 10 || byte_value == 13 || byte_value == 9 || byte_value < 32 {
                if buffer.count() > OUTPUT_BUFFER_BYTES - 12L {
                    out.write(buffer)?
                    buffer = Bytes.empty()
                }
                if byte_value == 34 { buffer.push(92).unwrap(); buffer.push(34).unwrap() }
                else if byte_value == 92 { buffer.push(92).unwrap(); buffer.push(92).unwrap() }
                else if byte_value == 10 { buffer.push(92).unwrap(); buffer.push(110).unwrap() }
                else if byte_value == 13 { buffer.push(92).unwrap(); buffer.push(114).unwrap() }
                else if byte_value == 9 { buffer.push(92).unwrap(); buffer.push(116).unwrap() }
                else {
                    buffer.push(92).unwrap()
                    buffer.push(117).unwrap()
                    buffer.push(48).unwrap()
                    buffer.push(48).unwrap()
                    if byte_value < 16 { buffer.push(48).unwrap() }
                    let digits = str_hex(byte_value)
                    for digit_index in 0L..digits.len() { buffer.push(digits.bytes()[digit_index]).unwrap() }
                }
            } else {
                if buffer.count() >= OUTPUT_BUFFER_BYTES {
                    out.write(buffer)?
                    buffer = Bytes.empty()
                }
                buffer.push(byte_value).unwrap()
            }
        }
        if buffer.count() > OUTPUT_BUFFER_BYTES - 8L { out.write(buffer)?; buffer = Bytes.empty() }
        buffer.push(34).unwrap()
        buffer.push(10).unwrap()

        var source_cursor = 0L
        var line = 1L
        var col = 1L
        for token_index in 0L..file.token_count {
            let token = tokens[file.first_token + token_index]
            if token.kind == TokenKind.Eof {
                line = file.end_line
                col = file.end_col
            } else {
                for offset in source_cursor..token.start {
                    if source[file.base + offset] == 10 {
                        line += 1L
                        col = 1L
                    } else {
                        col += 1L
                    }
                }
            }
            source_cursor = token.start
            if buffer.count() > OUTPUT_BUFFER_BYTES - 256L {
                out.write(buffer)?
                buffer = Bytes.empty()
            }
            let kind_name = token_kind_name(token.kind)
            for name_index in 0L..kind_name.len() { buffer.push(kind_name.bytes()[name_index]).unwrap() }
            buffer.push(32).unwrap()
            let start_text = str(token.start)
            for number_index in 0L..start_text.len() { buffer.push(start_text.bytes()[number_index]).unwrap() }
            buffer.push(32).unwrap()
            let length_text = str(token.length)
            for number_index in 0L..length_text.len() { buffer.push(length_text.bytes()[number_index]).unwrap() }
            buffer.push(32).unwrap()
            let line_text = str(line)
            for number_index in 0L..line_text.len() { buffer.push(line_text.bytes()[number_index]).unwrap() }
            buffer.push(32).unwrap()
            let col_text = str(col)
            for number_index in 0L..col_text.len() { buffer.push(col_text.bytes()[number_index]).unwrap() }
            buffer.push(32).unwrap()
            buffer.push(34).unwrap()
            for source_index in file.base + token.start..file.base + token.start + token.length {
                let byte_value = source[source_index]
                if byte_value == 34 || byte_value == 92 || byte_value == 10 || byte_value == 13 || byte_value == 9 || byte_value < 32 {
                    if buffer.count() > OUTPUT_BUFFER_BYTES - 12L {
                        out.write(buffer)?
                        buffer = Bytes.empty()
                    }
                    if byte_value == 34 { buffer.push(92).unwrap(); buffer.push(34).unwrap() }
                    else if byte_value == 92 { buffer.push(92).unwrap(); buffer.push(92).unwrap() }
                    else if byte_value == 10 { buffer.push(92).unwrap(); buffer.push(110).unwrap() }
                    else if byte_value == 13 { buffer.push(92).unwrap(); buffer.push(114).unwrap() }
                    else if byte_value == 9 { buffer.push(92).unwrap(); buffer.push(116).unwrap() }
                    else {
                        buffer.push(92).unwrap()
                        buffer.push(117).unwrap()
                        buffer.push(48).unwrap()
                        buffer.push(48).unwrap()
                        if byte_value < 16 { buffer.push(48).unwrap() }
                        let digits = str_hex(byte_value)
                        for digit_index in 0L..digits.len() { buffer.push(digits.bytes()[digit_index]).unwrap() }
                    }
                } else {
                    if buffer.count() >= OUTPUT_BUFFER_BYTES {
                        out.write(buffer)?
                        buffer = Bytes.empty()
                    }
                    buffer.push(byte_value).unwrap()
                }
            }
            if buffer.count() > OUTPUT_BUFFER_BYTES - 8L { out.write(buffer)?; buffer = Bytes.empty() }
            buffer.push(34).unwrap()
            buffer.push(10).unwrap()
            for offset in token.start..token.start + token.length {
                if source[file.base + offset] == 10 {
                    line += 1L
                    col = 1L
                } else {
                    col += 1L
                }
            }
            source_cursor = token.start + token.length
        }
    }
    if buffer.count() > 0L { out.write(buffer)? }
    ok(())
}
