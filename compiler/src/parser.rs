use crate::ast::*;
use crate::lexer::{Token, TokenKind};

#[derive(Clone, Debug)]
pub struct ParseError {
    pub span: Span,
    pub message: String,
}

pub fn parse(tokens: Vec<Token>, source: &str) -> Result<Program, ParseError> {
    Parser {
        tokens,
        pos: 0,
        source,
    }
    .program()
}

struct Parser<'a> {
    tokens: Vec<Token>,
    pos: usize,
    source: &'a str,
}

impl Parser<'_> {
    fn program(mut self) -> Result<Program, ParseError> {
        let mut functions = Vec::new();
        let mut tests = Vec::new();
        self.skip_separators();
        while !self.at(&TokenKind::Eof) {
            if self.word_is("test") {
                tests.push(self.test()?);
            } else {
                functions.push(self.function()?);
            }
            self.require_separator_or_eof()?;
            self.skip_separators();
        }
        Ok(Program { functions, tests })
    }

    fn test(&mut self) -> Result<Test, ParseError> {
        let start = self.expect_word("test", "expected 'test'")?.span;
        let token = self.next().clone();
        let name = if let TokenKind::String(name) = token.kind {
            name
        } else {
            return Err(ParseError {
                span: token.span,
                message: "expected a quoted test name after 'test'".to_owned(),
            });
        };
        self.skip_newlines();
        let body = self.block()?;
        Ok(Test {
            name,
            body,
            span: start,
        })
    }

    fn function(&mut self) -> Result<Function, ParseError> {
        let start = self
            .expect_word("fn", "expected a function declaration starting with 'fn'")?
            .span;
        let (name, _) = self.expect_ident("expected a function name after 'fn'")?;
        self.expect(&TokenKind::LParen, "expected '(' after the function name")?;
        let mut params = Vec::new();
        self.skip_newlines();
        if !self.at(&TokenKind::RParen) {
            loop {
                self.skip_newlines();
                let (param_name, pspan) = self.expect_ident("expected a parameter name")?;
                self.expect(&TokenKind::Colon, "expected ':' after the parameter name")?;
                let ty = self.type_name()?;
                params.push(Param {
                    name: param_name,
                    ty,
                    span: pspan,
                });
                self.skip_newlines();
                if !self.take(&TokenKind::Comma) {
                    break;
                }
                self.skip_newlines();
                if self.at(&TokenKind::RParen) {
                    break;
                }
            }
        }
        self.expect(&TokenKind::RParen, "expected ')' after the parameters")?;
        self.skip_newlines();
        let result = if self.take(&TokenKind::Arrow) {
            self.skip_newlines();
            Some(self.type_name()?)
        } else {
            None
        };
        self.skip_newlines();
        let body = self.block()?;
        Ok(Function {
            name,
            params,
            result,
            body,
            span: start,
        })
    }

    fn type_name(&mut self) -> Result<TypeAst, ParseError> {
        let (name, span) = self.expect_ident("expected a type name")?;
        if !matches!(name.as_str(), "int" | "long" | "bool") {
            return Err(ParseError {
                span,
                message: format!(
                    "unknown type '{}'; use int, long, or bool in this task",
                    name
                ),
            });
        }
        Ok(TypeAst { name, span })
    }

    fn block(&mut self) -> Result<Block, ParseError> {
        let start = self
            .expect(&TokenKind::LBrace, "expected '{' to start a block")?
            .span;
        let mut statements = Vec::new();
        let mut tail = None;
        self.skip_separators();
        while !self.at(&TokenKind::RBrace) && !self.at(&TokenKind::Eof) {
            let parsed = self.statement_candidate()?;
            match parsed {
                Candidate::Statement(stmt) => statements.push(stmt),
                Candidate::Expression(expr) => {
                    let had_separator = self.skip_separators() > 0;
                    if self.at(&TokenKind::RBrace) {
                        tail = Some(Box::new(expr));
                        break;
                    }
                    if !had_separator {
                        return Err(self.error_here("expected a newline or ';' between statements"));
                    }
                    statements.push(Stmt {
                        span: expr.span,
                        kind: StmtKind::Expr(expr),
                    });
                    continue;
                }
            }
            let had_separator = self.skip_separators() > 0;
            if !self.at(&TokenKind::RBrace) && !had_separator {
                return Err(self.error_here("expected a newline or ';' between statements"));
            }
        }
        self.expect(&TokenKind::RBrace, "expected '}' to close this block")?;
        Ok(Block {
            statements,
            tail,
            span: start,
        })
    }

    fn statement_candidate(&mut self) -> Result<Candidate, ParseError> {
        if self.word_is("for") {
            return Ok(Candidate::Statement(self.for_statement()?));
        }
        if self.word_is("break") || self.word_is("continue") {
            let token = self.next().clone();
            return Ok(Candidate::Statement(Stmt {
                span: token.span,
                kind: if matches!(&token.kind, TokenKind::Ident(word) if word == "break") {
                    StmtKind::Break
                } else {
                    StmtKind::Continue
                },
            }));
        }
        if self.word_is("expect") {
            let start = self.next().clone();
            if self.at(&TokenKind::Newline) || self.at(&TokenKind::Semicolon) {
                return Err(self.error_here("expected a bool expression after 'expect'"));
            }
            let first = self.pos;
            let value = self.expression(0)?;
            let end = self.tokens[self.pos.saturating_sub(1)].end_offset;
            let begin = self.tokens[first].start_offset;
            let expression_source = self.source.get(begin..end).unwrap_or("").trim_start();
            return Ok(Candidate::Statement(Stmt {
                span: start.span,
                kind: StmtKind::Expect {
                    value,
                    source: format!("expect {expression_source}"),
                },
            }));
        }
        if self.at(&TokenKind::LBrace) {
            return Ok(Candidate::Statement(Stmt {
                span: self.peek().span,
                kind: StmtKind::Block(self.block()?),
            }));
        }
        if self.word_is("let") || self.word_is("var") {
            let mutable = self.word_is("var");
            let start = self.next().span;
            let (name, _) = self.expect_ident("expected a binding name after 'let' or 'var'")?;
            let annotation = if self.take(&TokenKind::Colon) {
                Some(self.type_name()?)
            } else {
                None
            };
            self.expect(
                &TokenKind::Eq,
                "expected '=' and an initial value for this binding",
            )?;
            let value = self.expression(0)?;
            return Ok(Candidate::Statement(Stmt {
                span: start,
                kind: StmtKind::Let {
                    mutable,
                    name,
                    annotation,
                    value,
                },
            }));
        }
        if self.word_is("return") {
            let start = self.next().span;
            let value = if self.at(&TokenKind::Newline)
                || self.at(&TokenKind::Semicolon)
                || self.at(&TokenKind::RBrace)
            {
                None
            } else {
                Some(self.expression(0)?)
            };
            return Ok(Candidate::Statement(Stmt {
                span: start,
                kind: StmtKind::Return(value),
            }));
        }

        let expression = self.expression(0)?;
        let assignment = match self.peek().kind {
            TokenKind::Eq => Some(AssignOp::Set),
            TokenKind::PlusEq => Some(AssignOp::Add),
            TokenKind::MinusEq => Some(AssignOp::Sub),
            TokenKind::StarEq => Some(AssignOp::Mul),
            TokenKind::SlashEq => Some(AssignOp::Div),
            TokenKind::PercentEq => Some(AssignOp::Rem),
            _ => None,
        };
        if let Some(op) = assignment {
            let span = expression.span;
            let name = match expression.kind {
                ExprKind::Name(name) => name,
                _ => {
                    return Err(ParseError {
                        span,
                        message: "the left side of an assignment must be a variable name"
                            .to_owned(),
                    });
                }
            };
            let operator_span = self.next().span;
            let value = self.expression(0)?;
            return Ok(Candidate::Statement(Stmt {
                span,
                kind: StmtKind::Assign {
                    name,
                    op,
                    operator_span,
                    value,
                },
            }));
        }
        if matches!(
            &expression.kind,
            ExprKind::If {
                else_block: None,
                ..
            }
        ) {
            let span = expression.span;
            return Ok(Candidate::Statement(Stmt {
                span,
                kind: StmtKind::Expr(expression),
            }));
        }
        Ok(Candidate::Expression(expression))
    }

    fn for_statement(&mut self) -> Result<Stmt, ParseError> {
        let start = self.expect_word("for", "expected 'for'")?.span;
        let (name, _) = self.expect_ident("expected a counter name after 'for'")?;
        let annotation = if self.take(&TokenKind::Colon) {
            Some(self.type_name()?)
        } else {
            None
        };
        self.expect_word("in", "expected 'in' after the loop counter")?;
        let first = self.expression(0)?;
        let inclusive = if self.take(&TokenKind::RangeInclusive) {
            true
        } else if self.take(&TokenKind::Range) {
            false
        } else {
            return Err(self.error_here("expected '..' or '..=' after the loop start"));
        };
        let end = self.expression(0)?;
        self.skip_newlines();
        let body = self.block()?;
        Ok(Stmt {
            kind: StmtKind::For {
                name,
                annotation,
                start: first,
                end,
                inclusive,
                body,
            },
            span: start,
        })
    }

    fn expression(&mut self, min_precedence: u8) -> Result<Expr, ParseError> {
        let mut left = self.prefix()?;
        loop {
            let Some((op, precedence)) = binary_op(&self.peek().kind) else {
                break;
            };
            if precedence < min_precedence {
                break;
            }
            let op_span = self.next().span;
            let right = self.expression(precedence + 1)?;
            left = Expr {
                kind: ExprKind::Binary {
                    op,
                    operator_span: op_span,
                    left: Box::new(left),
                    right: Box::new(right),
                },
                span: op_span,
            };
        }
        Ok(left)
    }

    fn prefix(&mut self) -> Result<Expr, ParseError> {
        self.skip_newlines();
        let token = self.next().clone();
        let span = token.span;
        let mut expr = match token.kind {
            TokenKind::Number(raw) => self.integer(raw, span, false)?,
            TokenKind::Minus => {
                if let TokenKind::Number(raw) = self.peek().kind.clone() {
                    let number_span = self.next().span;
                    self.integer(raw, span, true).map(|mut e| {
                        e.span = Span {
                            file: span.file,
                            line: span.line,
                            col: span.col,
                        };
                        let _ = number_span;
                        e
                    })?
                } else {
                    let value = self.expression(11)?;
                    Expr {
                        kind: ExprKind::Unary {
                            op: UnaryOp::Neg,
                            operator_span: span,
                            value: Box::new(value),
                        },
                        span,
                    }
                }
            }
            TokenKind::Bang => {
                let value = self.expression(11)?;
                Expr {
                    kind: ExprKind::Unary {
                        op: UnaryOp::Not,
                        operator_span: span,
                        value: Box::new(value),
                    },
                    span,
                }
            }
            TokenKind::LParen => {
                let cast_name = match (&self.peek().kind, &self.peek_n(1).kind) {
                    (TokenKind::Ident(name), TokenKind::RParen)
                        if matches!(name.as_str(), "int" | "long" | "bool") =>
                    {
                        Some(name.clone())
                    }
                    _ => None,
                };
                if let Some(name) = cast_name {
                    let ty_token = self.next().clone();
                    self.next();
                    let ty = TypeAst {
                        name,
                        span: ty_token.span,
                    };
                    self.skip_newlines();
                    let value = self.prefix()?;
                    Expr {
                        kind: ExprKind::Cast {
                            ty,
                            cast_span: span,
                            value: Box::new(value),
                        },
                        span,
                    }
                } else {
                    let inner = self.expression(0)?;
                    self.expect(&TokenKind::RParen, "expected ')' after this expression")?;
                    Expr { span, ..inner }
                }
            }
            TokenKind::Ident(name) if name == "true" => Expr {
                kind: ExprKind::Bool(true),
                span,
            },
            TokenKind::Ident(name) if name == "false" => Expr {
                kind: ExprKind::Bool(false),
                span,
            },
            TokenKind::Ident(name) if name == "if" => self.if_expression(span)?,
            TokenKind::Ident(name) => Expr {
                kind: ExprKind::Name(name),
                span,
            },
            _ => {
                return Err(ParseError {
                    span,
                    message: "expected a value, a function call, or an if expression".to_owned(),
                });
            }
        };

        loop {
            if self.take(&TokenKind::LParen) {
                let name = match expr.kind {
                    ExprKind::Name(name) => name,
                    _ => {
                        return Err(ParseError {
                            span: expr.span,
                            message: "only a named function can be called".to_owned(),
                        });
                    }
                };
                let mut args = Vec::new();
                self.skip_newlines();
                if !self.at(&TokenKind::RParen) {
                    loop {
                        args.push(self.expression(0)?);
                        self.skip_newlines();
                        if !self.take(&TokenKind::Comma) {
                            break;
                        }
                        self.skip_newlines();
                        if self.at(&TokenKind::RParen) {
                            break;
                        }
                    }
                }
                self.expect(&TokenKind::RParen, "expected ')' after the arguments")?;
                expr = Expr {
                    kind: ExprKind::Call {
                        name,
                        call_span: expr.span,
                        args,
                    },
                    span: expr.span,
                };
                continue;
            }
            if self.take(&TokenKind::Dot) {
                let (method, method_span) =
                    self.expect_ident("expected a method name after '.'")?;
                if method != "to_long" {
                    return Err(ParseError {
                        span: method_span,
                        message: format!("unknown method '{}'; did you mean 'to_long'?", method),
                    });
                }
                self.expect(&TokenKind::LParen, "expected '()' after to_long")?;
                self.expect(&TokenKind::RParen, "expected '()' after to_long")?;
                expr = Expr {
                    kind: ExprKind::ToLong {
                        value: Box::new(expr.clone()),
                        method_span,
                    },
                    span: expr.span,
                };
                continue;
            }
            break;
        }
        Ok(expr)
    }

    fn if_expression(&mut self, span: Span) -> Result<Expr, ParseError> {
        let condition = self.expression(0)?;
        let then_block = self.block()?;
        let saved = self.pos;
        self.skip_newlines();
        let else_block = if self.word_is("else") {
            self.next();
            self.skip_newlines();
            if self.at(&TokenKind::LBrace) {
                Some(self.block()?)
            } else if self.word_is("if") {
                let if_span = self.next().span;
                let nested = self.if_expression(if_span)?;
                Some(Block {
                    statements: Vec::new(),
                    tail: Some(Box::new(nested)),
                    span: if_span,
                })
            } else {
                return Err(self.error_here("expected a block or another 'if' after 'else'"));
            }
        } else {
            self.pos = saved;
            None
        };
        Ok(Expr {
            kind: ExprKind::If {
                condition: Box::new(condition),
                then_block,
                else_block,
            },
            span,
        })
    }

    fn integer(&self, raw: String, span: Span, negative: bool) -> Result<Expr, ParseError> {
        let long_suffix = raw.ends_with('L') || raw.ends_with('l');
        let mut digits = raw.as_str();
        if long_suffix {
            digits = &digits[..digits.len() - 1];
        }
        let cleaned: String = digits.chars().filter(|c| *c != '_').collect();
        let (base, payload) = if cleaned.starts_with("0x") || cleaned.starts_with("0X") {
            (16, &cleaned[2..])
        } else if cleaned.starts_with("0b") || cleaned.starts_with("0B") {
            (2, &cleaned[2..])
        } else {
            (10, cleaned.as_str())
        };
        let magnitude = u128::from_str_radix(payload, base).map_err(|_| ParseError {
            span,
            message: "integer literal is too large to represent; use a smaller value".to_owned(),
        })?;
        Ok(Expr {
            kind: ExprKind::Integer {
                magnitude,
                negative,
                long_suffix,
            },
            span,
        })
    }

    fn skip_newlines(&mut self) {
        while self.at(&TokenKind::Newline) {
            self.pos += 1;
        }
    }

    fn skip_separators(&mut self) -> usize {
        let mut n = 0;
        while self.at(&TokenKind::Newline) || self.at(&TokenKind::Semicolon) {
            self.pos += 1;
            n += 1;
        }
        n
    }

    fn require_separator_or_eof(&self) -> Result<(), ParseError> {
        if self.at(&TokenKind::Newline)
            || self.at(&TokenKind::Semicolon)
            || self.at(&TokenKind::Eof)
        {
            Ok(())
        } else {
            Err(self.error_here("expected a newline or ';' after the function"))
        }
    }

    fn expect_word(&mut self, word: &str, message: &str) -> Result<Token, ParseError> {
        if self.word_is(word) {
            Ok(self.next().clone())
        } else {
            Err(self.error_here(message))
        }
    }

    fn expect_ident(&mut self, message: &str) -> Result<(String, Span), ParseError> {
        let token = self.next().clone();
        if let TokenKind::Ident(name) = token.kind {
            Ok((name, token.span))
        } else {
            Err(ParseError {
                span: token.span,
                message: message.to_owned(),
            })
        }
    }

    fn expect(&mut self, kind: &TokenKind, message: &str) -> Result<Token, ParseError> {
        if self.at(kind) {
            Ok(self.next().clone())
        } else {
            Err(self.error_here(message))
        }
    }

    fn take(&mut self, kind: &TokenKind) -> bool {
        if self.at(kind) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn at(&self, kind: &TokenKind) -> bool {
        &self.peek().kind == kind
    }

    fn word_is(&self, word: &str) -> bool {
        matches!(&self.peek().kind, TokenKind::Ident(actual) if actual == word)
    }

    fn next(&mut self) -> &Token {
        let i = self.pos.min(self.tokens.len() - 1);
        self.pos = (self.pos + 1).min(self.tokens.len() - 1);
        &self.tokens[i]
    }

    fn peek(&self) -> &Token {
        self.peek_n(0)
    }

    fn peek_n(&self, n: usize) -> &Token {
        &self.tokens[(self.pos + n).min(self.tokens.len() - 1)]
    }

    fn error_here(&self, message: &str) -> ParseError {
        ParseError {
            span: self.peek().span,
            message: message.to_owned(),
        }
    }
}

enum Candidate {
    Statement(Stmt),
    Expression(Expr),
}

fn binary_op(kind: &TokenKind) -> Option<(BinaryOp, u8)> {
    Some(match kind {
        TokenKind::OrOr => (BinaryOp::Or, 1),
        TokenKind::AndAnd => (BinaryOp::And, 2),
        TokenKind::Or => (BinaryOp::BitOr, 3),
        TokenKind::Caret => (BinaryOp::BitXor, 4),
        TokenKind::And => (BinaryOp::BitAnd, 5),
        TokenKind::EqEq => (BinaryOp::Eq, 6),
        TokenKind::BangEq => (BinaryOp::Ne, 6),
        TokenKind::Lt => (BinaryOp::Lt, 7),
        TokenKind::Le => (BinaryOp::Le, 7),
        TokenKind::Gt => (BinaryOp::Gt, 7),
        TokenKind::Ge => (BinaryOp::Ge, 7),
        TokenKind::Shl => (BinaryOp::Shl, 8),
        TokenKind::Shr => (BinaryOp::Shr, 8),
        TokenKind::Plus => (BinaryOp::Add, 9),
        TokenKind::Minus => (BinaryOp::Sub, 9),
        TokenKind::WrapPlus => (BinaryOp::WrapAdd, 9),
        TokenKind::WrapMinus => (BinaryOp::WrapSub, 9),
        TokenKind::Star => (BinaryOp::Mul, 10),
        TokenKind::Slash => (BinaryOp::Div, 10),
        TokenKind::Percent => (BinaryOp::Rem, 10),
        TokenKind::WrapStar => (BinaryOp::WrapMul, 10),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lexer::lex;

    #[test]
    fn block_keeps_tail_expression_and_continued_operator() {
        let source = "fn value(a: int) -> int {\n let x = a +\n 2\n x\n}\nfn main() {}";
        let parsed = parse(lex(source, 0).unwrap(), source).unwrap();
        let body = &parsed.functions[0].body;
        assert_eq!(body.statements.len(), 1);
        assert!(body.tail.is_some());
        let StmtKind::Let { value, .. } = &body.statements[0].kind else {
            panic!("expected let statement")
        };
        assert!(matches!(
            value.kind,
            ExprKind::Binary {
                op: BinaryOp::Add,
                ..
            }
        ));
    }

    #[test]
    fn final_if_without_else_is_a_statement() {
        let source = "fn main() { if true { print(1) } }";
        let parsed = parse(lex(source, 0).unwrap(), source).unwrap();
        let body = &parsed.functions[0].body;
        assert!(body.tail.is_none());
        assert!(matches!(
            body.statements[0].kind,
            StmtKind::Expr(Expr {
                kind: ExprKind::If {
                    else_block: None,
                    ..
                },
                ..
            })
        ));
    }
}
