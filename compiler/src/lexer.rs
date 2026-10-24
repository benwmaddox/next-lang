use crate::ast::Span;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TokenKind {
    Ident(String),
    Number(String),
    Newline,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Colon,
    Semicolon,
    Dot,
    Arrow,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    WrapPlus,
    WrapMinus,
    WrapStar,
    PlusEq,
    MinusEq,
    StarEq,
    SlashEq,
    PercentEq,
    Eq,
    EqEq,
    Bang,
    BangEq,
    Lt,
    Le,
    Gt,
    Ge,
    And,
    AndAnd,
    Or,
    OrOr,
    Caret,
    Shl,
    Shr,
    Eof,
}

#[derive(Clone, Debug)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct LexError {
    pub span: Span,
    pub message: String,
}

pub fn lex(source: &str, file: usize) -> Result<Vec<Token>, LexError> {
    let bytes = source.as_bytes();
    let mut pos = 0;
    let mut line = 1;
    let mut col = 1;
    let mut parens = 0usize;
    let mut out = Vec::new();

    while pos < bytes.len() {
        let b = bytes[pos];
        if b == b' ' || b == b'\t' || b == b'\r' {
            pos += 1;
            col += 1;
            continue;
        }
        if b == b'\n' {
            let span = Span { file, line, col };
            pos += 1;
            line += 1;
            col = 1;
            if parens == 0 {
                push_newline(&mut out, span);
            }
            continue;
        }
        if b == b'/' && bytes.get(pos + 1) == Some(&b'/') {
            while pos < bytes.len() && bytes[pos] != b'\n' {
                pos += 1;
                col += 1;
            }
            continue;
        }
        let span = Span { file, line, col };
        if is_ident_start(b) {
            let start = pos;
            while pos < bytes.len() && is_ident_continue(bytes[pos]) {
                pos += 1;
                col += 1;
            }
            out.push(Token {
                kind: TokenKind::Ident(source[start..pos].to_owned()),
                span,
            });
            continue;
        }
        if b.is_ascii_digit() {
            let start = pos;
            pos += 1;
            col += 1;
            while pos < bytes.len() && (bytes[pos].is_ascii_alphanumeric() || bytes[pos] == b'_') {
                pos += 1;
                col += 1;
            }
            out.push(Token {
                kind: TokenKind::Number(source[start..pos].to_owned()),
                span,
            });
            continue;
        }

        let (kind, width) = match_two_or_one(bytes, pos).ok_or_else(|| LexError {
            span,
            message: format!(
                "unexpected character '{}'; remove it or use a supported operator",
                b as char
            ),
        })?;
        if matches!(kind, TokenKind::LParen) {
            parens += 1;
        } else if matches!(kind, TokenKind::RParen) {
            if parens == 0 {
                return Err(LexError {
                    span,
                    message: "unmatched ')'; add a matching '('".to_owned(),
                });
            }
            parens -= 1;
        }
        pos += width;
        col += width;
        out.push(Token { kind, span });
    }
    if parens != 0 {
        return Err(LexError {
            span: Span { file, line, col },
            message: "unclosed '('; add a matching ')'".to_owned(),
        });
    }
    out.push(Token {
        kind: TokenKind::Eof,
        span: Span { file, line, col },
    });
    Ok(out)
}

fn push_newline(out: &mut Vec<Token>, span: Span) {
    if !matches!(
        out.last().map(|t| &t.kind),
        Some(TokenKind::Newline | TokenKind::Semicolon)
    ) {
        out.push(Token {
            kind: TokenKind::Newline,
            span,
        });
    }
}

fn is_ident_start(b: u8) -> bool {
    b.is_ascii_alphabetic() || b == b'_'
}

fn is_ident_continue(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn match_two_or_one(b: &[u8], p: usize) -> Option<(TokenKind, usize)> {
    let two = b.get(p..p + 2);
    if let Some(pair) = two {
        let kind = match pair {
            b"->" => Some(TokenKind::Arrow),
            b"+%" => Some(TokenKind::WrapPlus),
            b"-%" => Some(TokenKind::WrapMinus),
            b"*%" => Some(TokenKind::WrapStar),
            b"+=" => Some(TokenKind::PlusEq),
            b"-=" => Some(TokenKind::MinusEq),
            b"*=" => Some(TokenKind::StarEq),
            b"/=" => Some(TokenKind::SlashEq),
            b"%=" => Some(TokenKind::PercentEq),
            b"==" => Some(TokenKind::EqEq),
            b"!=" => Some(TokenKind::BangEq),
            b"<=" => Some(TokenKind::Le),
            b">=" => Some(TokenKind::Ge),
            b"&&" => Some(TokenKind::AndAnd),
            b"||" => Some(TokenKind::OrOr),
            b"<<" => Some(TokenKind::Shl),
            b">>" => Some(TokenKind::Shr),
            _ => None,
        };
        if let Some(k) = kind {
            return Some((k, 2));
        }
    }
    let kind = match b[p] {
        b'(' => TokenKind::LParen,
        b')' => TokenKind::RParen,
        b'{' => TokenKind::LBrace,
        b'}' => TokenKind::RBrace,
        b',' => TokenKind::Comma,
        b':' => TokenKind::Colon,
        b';' => TokenKind::Semicolon,
        b'.' => TokenKind::Dot,
        b'+' => TokenKind::Plus,
        b'-' => TokenKind::Minus,
        b'*' => TokenKind::Star,
        b'/' => TokenKind::Slash,
        b'%' => TokenKind::Percent,
        b'=' => TokenKind::Eq,
        b'!' => TokenKind::Bang,
        b'<' => TokenKind::Lt,
        b'>' => TokenKind::Gt,
        b'&' => TokenKind::And,
        b'|' => TokenKind::Or,
        b'^' => TokenKind::Caret,
        _ => return None,
    };
    Some((kind, 1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newlines_continue_inside_parentheses() {
        let tokens = lex("fn f(\na: int,\nb: int\n) {\n a +\n b\n}", 0).unwrap();
        assert_eq!(
            tokens
                .iter()
                .filter(|t| t.kind == TokenKind::Newline)
                .count(),
            3
        );
    }

    #[test]
    fn comments_keep_the_line_ending() {
        let tokens = lex("let x = 1 // value\nprint(x)", 0).unwrap();
        assert!(tokens.iter().any(|t| t.kind == TokenKind::Newline));
    }
}
