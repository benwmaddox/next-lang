use std::collections::HashMap;

use crate::ast::*;
use crate::typed::*;

#[derive(Clone, Debug)]
pub struct CheckError {
    pub span: Span,
    pub message: String,
}

#[derive(Clone)]
struct Signature {
    id: usize,
    params: Vec<Ty>,
    result: Ty,
}

#[derive(Clone)]
struct Binding {
    id: usize,
    name: String,
    ty: Ty,
    mutable: bool,
    span: Span,
}

#[derive(Clone, Copy)]
struct Edge {
    from: usize,
    to: usize,
    span: Span,
}

pub fn check(programs: Vec<Program>, files: Vec<String>) -> Result<TProgram, CheckError> {
    Checker::new(programs, files).run()
}

struct Checker {
    programs: Vec<Program>,
    files: Vec<String>,
    signatures: HashMap<String, Signature>,
    ast_functions: Vec<Function>,
    edges: Vec<Edge>,
    locals: Vec<HashMap<String, Binding>>,
    scope_ids: Vec<usize>,
    next_scope: usize,
    next_local: usize,
    current_function: usize,
    current_return: Ty,
}

impl Checker {
    fn new(programs: Vec<Program>, files: Vec<String>) -> Self {
        Self {
            programs,
            files,
            signatures: HashMap::new(),
            ast_functions: Vec::new(),
            edges: Vec::new(),
            locals: Vec::new(),
            scope_ids: Vec::new(),
            next_scope: 0,
            next_local: 0,
            current_function: 0,
            current_return: Ty::Unit,
        }
    }

    fn run(mut self) -> Result<TProgram, CheckError> {
        for p in self.programs.clone() {
            for function in p.functions {
                let id = self.ast_functions.len();
                if function.name == "print" {
                    return Err(CheckError {
                        span: function.span,
                        message: "'print' is a built-in function name and cannot be redeclared"
                            .to_owned(),
                    });
                }
                if self.signatures.contains_key(&function.name) {
                    return Err(CheckError {
                        span: function.span,
                        message: format!("function '{}' is declared more than once", function.name),
                    });
                }
                let params = function
                    .params
                    .iter()
                    .map(|p| parse_ty(&p.ty))
                    .collect::<Result<Vec<_>, _>>()?;
                let result = function
                    .result
                    .as_ref()
                    .map(parse_ty)
                    .transpose()?
                    .unwrap_or(Ty::Unit);
                self.signatures
                    .insert(function.name.clone(), Signature { id, params, result });
                self.ast_functions.push(function);
            }
        }
        self.check_entry()?;
        let mut functions = Vec::with_capacity(self.ast_functions.len());
        for id in 0..self.ast_functions.len() {
            functions.push(self.check_function(id)?);
        }
        self.check_recursion()?;
        let mut call_graph = vec![Vec::new(); functions.len()];
        for edge in self.edges {
            call_graph[edge.from].push(TCallEdge {
                target: edge.to,
                span: edge.span,
            });
        }
        Ok(TProgram {
            functions,
            files: self.files,
            call_graph,
        })
    }

    fn check_entry(&self) -> Result<(), CheckError> {
        let Some(sig) = self.signatures.get("main") else {
            return Err(CheckError {
                span: Span { file: 0, line: 1, col: 1 },
                message: "package must define 'fn main()'; add an entry point that takes no arguments and returns ()".to_owned(),
            });
        };
        let function = &self.ast_functions[sig.id];
        if !sig.params.is_empty() || sig.result != Ty::Unit {
            return Err(CheckError { span: function.span, message: "'main' must take no arguments and return (); change its signature to 'fn main()'".to_owned() });
        }
        Ok(())
    }

    fn check_function(&mut self, id: usize) -> Result<TFunction, CheckError> {
        let function = self.ast_functions[id].clone();
        let signature = self.signatures[&function.name].clone();
        self.current_function = id;
        self.current_return = signature.result;
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.next_scope = 1;
        self.scope_ids.clear();
        self.scope_ids.push(0);
        let mut params = Vec::new();
        for (i, param) in function.params.iter().enumerate() {
            let ty = signature.params[i];
            let binding = self.declare(&param.name, ty, false, param.span)?;
            params.push(TParam {
                id: binding.id,
                name: binding.name,
                ty,
                span: param.span,
            });
        }
        let body = self.check_block(&function.body, false, Some(signature.result))?;
        if signature.result != Ty::Unit && body.falls_through && body.tail.is_none() {
            return Err(CheckError {
                span: function.body.span,
                message: format!(
                    "function '{}' can reach the end without a {}; return a value on every path",
                    function.name,
                    signature.result.name()
                ),
            });
        }
        if signature.result == Ty::Unit {
            if body.falls_through {
                if let Some(tail) = &body.tail {
                    if tail.ty != Ty::Unit && tail.ty != Ty::Never {
                        return Err(CheckError {
                            span: tail.span,
                            message: format!(
                                "function '{}' returns (), but its last expression has type {}; remove it or return ()",
                                function.name,
                                tail.ty.name()
                            ),
                        });
                    }
                }
            }
        }
        self.locals.clear();
        Ok(TFunction {
            id,
            name: function.name,
            params,
            result: signature.result,
            body,
            span: function.span,
        })
    }

    fn check_block(
        &mut self,
        block: &Block,
        nested_scope: bool,
        expected: Option<Ty>,
    ) -> Result<TBlock, CheckError> {
        if nested_scope {
            self.locals.push(HashMap::new());
            self.scope_ids.push(self.next_scope);
            self.next_scope += 1;
        }
        let scope_id = *self.scope_ids.last().expect("function scope exists");
        let mut statements = Vec::new();
        let mut can_reach = true;
        for stmt in &block.statements {
            let typed = self.check_statement(stmt)?;
            let stmt_falls = statement_falls_through(&typed.kind);
            statements.push(typed);
            if can_reach {
                can_reach = stmt_falls;
            }
        }
        let tail = if let Some(expr) = &block.tail {
            Some(Box::new(self.check_expr(expr, expected)?))
        } else {
            None
        };
        let falls_through = if !can_reach {
            false
        } else if let Some(tail) = &tail {
            tail.ty != Ty::Never
        } else {
            true
        };
        if nested_scope {
            self.locals.pop();
            self.scope_ids.pop();
        }
        Ok(TBlock {
            statements,
            tail,
            falls_through,
            scope_id,
            span: block.span,
        })
    }

    fn check_statement(&mut self, stmt: &Stmt) -> Result<TStmt, CheckError> {
        let kind = match &stmt.kind {
            StmtKind::Let {
                mutable,
                name,
                annotation,
                value,
            } => {
                let annotated = annotation.as_ref().map(parse_ty).transpose()?;
                let typed_value = self.check_expr(value, annotated)?;
                if typed_value.ty == Ty::Unit || typed_value.ty == Ty::Never {
                    return Err(CheckError { span: value.span, message: "a binding needs a value; functions and if expressions used here must return int, long, or bool".to_owned() });
                }
                let ty = annotated.unwrap_or(typed_value.ty);
                let binding = self.declare(name, ty, *mutable, stmt.span)?;
                TStmtKind::Let {
                    id: binding.id,
                    name: name.clone(),
                    ty,
                    mutable: *mutable,
                    value: typed_value,
                }
            }
            StmtKind::Assign {
                name,
                op,
                operator_span,
                value,
            } => {
                let binding = self
                    .find_binding(name)
                    .ok_or_else(|| self.unknown_local(name, stmt.span))?;
                if !binding.mutable {
                    return Err(CheckError {
                        span: stmt.span,
                        message: format!(
                            "cannot assign to immutable 'let' binding '{}'; declare it with 'var'",
                            name
                        ),
                    });
                }
                let typed_value = self.check_expr(value, Some(binding.ty))?;
                if *op != AssignOp::Set {
                    let bop = assign_binary(*op);
                    self.check_binary_types(bop, binding.ty, typed_value.ty, *operator_span)?;
                    if !binding.ty.is_numeric() {
                        return Err(CheckError {
                            span: stmt.span,
                            message: format!(
                                "'{}=' requires int or long; '{}' is {}",
                                assign_spelling(*op),
                                name,
                                binding.ty.name()
                            ),
                        });
                    }
                }
                TStmtKind::Assign {
                    id: binding.id,
                    ty: binding.ty,
                    op: *op,
                    operator_span: *operator_span,
                    value: typed_value,
                }
            }
            StmtKind::Return(value) => {
                let result = match value {
                    Some(expr) => {
                        if self.current_return == Ty::Unit {
                            return Err(CheckError {
                                span: expr.span,
                                message: "this function returns (); remove the value from 'return'"
                                    .to_owned(),
                            });
                        }
                        Some(self.check_expr(expr, Some(self.current_return))?)
                    }
                    None => {
                        if self.current_return != Ty::Unit {
                            return Err(CheckError {
                                span: stmt.span,
                                message: format!(
                                    "this function must return {}; add a value after 'return'",
                                    self.current_return.name()
                                ),
                            });
                        }
                        None
                    }
                };
                TStmtKind::Return(result)
            }
            StmtKind::Expr(expr) => {
                if let ExprKind::If {
                    condition,
                    then_block,
                    else_block,
                } = &expr.kind
                {
                    let typed = self.check_if(
                        condition,
                        then_block,
                        else_block.as_ref(),
                        None,
                        false,
                        expr.span,
                    )?;
                    let TExprKind::If {
                        condition,
                        then_block,
                        else_block,
                    } = typed.kind
                    else {
                        unreachable!()
                    };
                    TStmtKind::If {
                        condition: *condition,
                        then_block,
                        else_block,
                    }
                } else {
                    TStmtKind::Expr(self.check_expr(expr, None)?)
                }
            }
        };
        Ok(TStmt {
            kind,
            span: stmt.span,
        })
    }

    fn check_expr(&mut self, expr: &Expr, expected: Option<Ty>) -> Result<TExpr, CheckError> {
        let (kind, ty) = match &expr.kind {
            ExprKind::Integer {
                magnitude,
                negative,
                long_suffix,
            } => {
                let ty = if *long_suffix {
                    Ty::Long
                } else {
                    expected.filter(|t| t.is_numeric()).unwrap_or(Ty::Int)
                };
                if *long_suffix && expected.is_some_and(|t| t != Ty::Long) {
                    self.type_mismatch(Ty::Long, expected.unwrap(), expr.span)?;
                }
                let limit = match (ty, *negative) {
                    (Ty::Int, true) => (i32::MAX as u128) + 1,
                    (Ty::Int, false) => i32::MAX as u128,
                    (Ty::Long, true) => (i64::MAX as u128) + 1,
                    (Ty::Long, false) => i64::MAX as u128,
                    _ => unreachable!(),
                };
                if *magnitude > limit {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!(
                            "integer literal does not fit {}; add 'L' for long or give it a long context",
                            ty.name()
                        ),
                    });
                }
                let value = if *negative {
                    -(*magnitude as i128)
                } else {
                    *magnitude as i128
                };
                (TExprKind::Integer(value), ty)
            }
            ExprKind::Bool(value) => {
                if let Some(want) = expected {
                    self.type_mismatch(Ty::Bool, want, expr.span)?;
                }
                (TExprKind::Bool(*value), Ty::Bool)
            }
            ExprKind::Name(name) => {
                if let Some(binding) = self.find_binding(name) {
                    if let Some(want) = expected {
                        self.type_mismatch(binding.ty, want, expr.span)?;
                    }
                    (TExprKind::Local(binding.id), binding.ty)
                } else {
                    return Err(self.unknown_local(name, expr.span));
                }
            }
            ExprKind::Call {
                name,
                call_span,
                args,
            } => {
                if name == "print" {
                    if args.len() != 1 {
                        return Err(CheckError {
                            span: *call_span,
                            message: format!(
                                "print takes one argument, but got {}; call print(value)",
                                args.len()
                            ),
                        });
                    }
                    let arg = self.check_expr(&args[0], None)?;
                    if !matches!(arg.ty, Ty::Int | Ty::Long | Ty::Bool) {
                        return Err(CheckError {
                            span: args[0].span,
                            message: "print supports int, long, and bool values".to_owned(),
                        });
                    }
                    if let Some(want) = expected {
                        self.type_mismatch(Ty::Unit, want, *call_span)?;
                    }
                    (
                        TExprKind::Call {
                            target: CallTarget::Print,
                            args: vec![arg],
                            effect: Effect::Observable,
                        },
                        Ty::Unit,
                    )
                } else {
                    let Some(signature) = self.signatures.get(name).cloned() else {
                        return Err(self.unknown_function(name, *call_span));
                    };
                    if args.len() != signature.params.len() {
                        return Err(CheckError {
                            span: *call_span,
                            message: format!(
                                "function '{}' takes {} argument(s), but got {}",
                                name,
                                signature.params.len(),
                                args.len()
                            ),
                        });
                    }
                    let mut typed_args = Vec::new();
                    for (arg, ty) in args.iter().zip(signature.params.iter().copied()) {
                        typed_args.push(self.check_expr(arg, Some(ty))?);
                    }
                    if let Some(want) = expected {
                        self.type_mismatch(signature.result, want, *call_span)?;
                    }
                    self.edges.push(Edge {
                        from: self.current_function,
                        to: signature.id,
                        span: *call_span,
                    });
                    (
                        TExprKind::Call {
                            target: CallTarget::Function(signature.id),
                            args: typed_args,
                            effect: Effect::None,
                        },
                        signature.result,
                    )
                }
            }
            ExprKind::ToLong(value) => {
                let typed = self.check_expr(value, Some(Ty::Int))?;
                if let Some(want) = expected {
                    self.type_mismatch(Ty::Long, want, expr.span)?;
                }
                (TExprKind::ToLong(Box::new(typed)), Ty::Long)
            }
            ExprKind::Cast {
                ty,
                cast_span,
                value,
            } => {
                let target = parse_ty(ty)?;
                if !target.is_numeric() {
                    return Err(CheckError {
                        span: ty.span,
                        message: "casts in this task are between int and long".to_owned(),
                    });
                }
                let source = self.check_expr(value, None)?;
                if !source.ty.is_numeric() {
                    return Err(CheckError {
                        span: value.span,
                        message: format!(
                            "cannot cast {} to {}; casts are between int and long",
                            source.ty.name(),
                            target.name()
                        ),
                    });
                }
                if let Some(want) = expected {
                    self.type_mismatch(target, want, expr.span)?;
                }
                (
                    TExprKind::Cast {
                        cast_span: *cast_span,
                        value: Box::new(source),
                    },
                    target,
                )
            }
            ExprKind::Unary {
                op,
                operator_span,
                value,
            } => {
                let typed = self.check_expr(
                    value,
                    match op {
                        UnaryOp::Not => Some(Ty::Bool),
                        UnaryOp::Neg => expected.filter(|t| t.is_numeric()),
                    },
                )?;
                match op {
                    UnaryOp::Not if typed.ty != Ty::Bool => {
                        return Err(CheckError {
                            span: value.span,
                            message: "'!' requires a bool".to_owned(),
                        });
                    }
                    UnaryOp::Neg if !typed.ty.is_numeric() => {
                        return Err(CheckError {
                            span: value.span,
                            message: "unary '-' requires int or long".to_owned(),
                        });
                    }
                    _ => {}
                }
                (
                    TExprKind::Unary {
                        op: *op,
                        operator_span: *operator_span,
                        value: Box::new(typed.clone()),
                    },
                    typed.ty,
                )
            }
            ExprKind::Binary {
                op,
                operator_span,
                left,
                right,
            } => self.check_binary_expr(*op, left, right, expected, *operator_span)?,
            ExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                let typed = self.check_if(
                    condition,
                    then_block,
                    else_block.as_ref(),
                    expected,
                    true,
                    expr.span,
                )?;
                let ty = typed.ty;
                (typed.kind, ty)
            }
        };
        if let Some(want) = expected {
            if ty != Ty::Never {
                self.type_mismatch(ty, want, expr.span)?;
            }
        }
        Ok(TExpr {
            kind,
            ty,
            span: expr.span,
        })
    }

    fn check_binary_expr(
        &mut self,
        op: BinaryOp,
        left: &Expr,
        right: &Expr,
        expected: Option<Ty>,
        span: Span,
    ) -> Result<(TExprKind, Ty), CheckError> {
        if matches!(op, BinaryOp::And | BinaryOp::Or) {
            let l = self.check_expr(left, Some(Ty::Bool))?;
            let r = self.check_expr(right, Some(Ty::Bool))?;
            return Ok((
                TExprKind::Binary {
                    op,
                    operator_span: span,
                    left: Box::new(l),
                    right: Box::new(r),
                },
                Ty::Bool,
            ));
        }
        let (l, r) = if matches!(op, BinaryOp::Eq | BinaryOp::Ne) {
            let (l, r) =
                self.check_operand_pair(left, right, expected.filter(|t| t.is_numeric()))?;
            if l.ty != r.ty {
                return Err(self.mixed_types_error(l.ty, r.ty, span));
            }
            if matches!(l.ty, Ty::Unit | Ty::Never) {
                return Err(CheckError {
                    span,
                    message: "equality requires int, long, or bool values".to_owned(),
                });
            }
            return Ok((
                TExprKind::Binary {
                    op,
                    operator_span: span,
                    left: Box::new(l),
                    right: Box::new(r),
                },
                Ty::Bool,
            ));
        } else if matches!(
            op,
            BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge
        ) {
            let (l, r) =
                self.check_operand_pair(left, right, expected.filter(|t| t.is_numeric()))?;
            if l.ty != r.ty {
                return Err(self.mixed_types_error(l.ty, r.ty, span));
            }
            if !l.ty.is_numeric() {
                return Err(CheckError {
                    span,
                    message: "ordered comparisons require int or long values".to_owned(),
                });
            }
            return Ok((
                TExprKind::Binary {
                    op,
                    operator_span: span,
                    left: Box::new(l),
                    right: Box::new(r),
                },
                Ty::Bool,
            ));
        } else {
            self.check_operand_pair(left, right, expected.filter(|t| t.is_numeric()))?
        };
        if l.ty != r.ty {
            return Err(self.mixed_types_error(l.ty, r.ty, span));
        }
        if !l.ty.is_numeric() {
            return Err(CheckError {
                span,
                message: format!(
                    "operator '{}' requires int or long values",
                    binary_spelling(op)
                ),
            });
        }
        if matches!(
            op,
            BinaryOp::BitAnd | BinaryOp::BitOr | BinaryOp::BitXor | BinaryOp::Shl | BinaryOp::Shr
        ) || matches!(
            op,
            BinaryOp::Add
                | BinaryOp::Sub
                | BinaryOp::Mul
                | BinaryOp::Div
                | BinaryOp::Rem
                | BinaryOp::WrapAdd
                | BinaryOp::WrapSub
                | BinaryOp::WrapMul
        ) {
            Ok((
                TExprKind::Binary {
                    op,
                    operator_span: span,
                    left: Box::new(l.clone()),
                    right: Box::new(r),
                },
                l.ty,
            ))
        } else {
            unreachable!()
        }
    }

    fn check_operand_pair(
        &mut self,
        left: &Expr,
        right: &Expr,
        context: Option<Ty>,
    ) -> Result<(TExpr, TExpr), CheckError> {
        let left_lit = is_unsuffixed_integer(left);
        let right_lit = is_unsuffixed_integer(right);
        if context.is_some() {
            let ty = context.unwrap();
            return Ok((
                self.check_expr(left, Some(ty))?,
                self.check_expr(right, Some(ty))?,
            ));
        }
        if left_lit && !right_lit {
            let r = self.check_expr(right, None)?;
            let l = self.check_expr(left, Some(r.ty))?;
            Ok((l, r))
        } else if right_lit && !left_lit {
            let l = self.check_expr(left, None)?;
            let r = self.check_expr(right, Some(l.ty))?;
            Ok((l, r))
        } else if !left_lit && !right_lit {
            let l = self.check_expr(left, None)?;
            let r = self.check_expr(right, None)?;
            Ok((l, r))
        } else {
            let l = self.check_expr(left, None)?;
            let r = self.check_expr(right, Some(l.ty))?;
            Ok((l, r))
        }
    }

    fn check_binary_types(
        &self,
        op: BinaryOp,
        left: Ty,
        right: Ty,
        span: Span,
    ) -> Result<(), CheckError> {
        if left != right {
            return Err(self.mixed_types_error(left, right, span));
        }
        if !left.is_numeric() {
            return Err(CheckError {
                span,
                message: format!(
                    "operator '{}' requires int or long values",
                    binary_spelling(op)
                ),
            });
        }
        Ok(())
    }

    fn check_if(
        &mut self,
        condition: &Expr,
        then_ast: &Block,
        else_ast: Option<&Block>,
        expected: Option<Ty>,
        value_context: bool,
        span: Span,
    ) -> Result<TExpr, CheckError> {
        let condition = self.check_expr(condition, Some(Ty::Bool))?;
        if value_context && else_ast.is_none() {
            return Err(CheckError {
                span,
                message: "an if expression needs an else branch; add 'else { ... }'".to_owned(),
            });
        }
        let then_block =
            self.check_block(then_ast, true, if value_context { expected } else { None })?;
        let else_block = else_ast
            .map(|b| self.check_block(b, true, if value_context { expected } else { None }))
            .transpose()?;
        let ty = if !value_context {
            Ty::Unit
        } else {
            let then_ty = block_value_ty(&then_block);
            let else_ty = block_value_ty(else_block.as_ref().unwrap());
            let result = if then_ty == Ty::Never {
                else_ty
            } else if else_ty == Ty::Never {
                then_ty
            } else if then_ty == else_ty {
                then_ty
            } else {
                return Err(CheckError {
                    span,
                    message: format!(
                        "if branches have different types: {} and {}; make both branches return the same type",
                        then_ty.name(),
                        else_ty.name()
                    ),
                });
            };
            if let Some(want) = expected {
                self.type_mismatch(result, want, span)?;
            }
            result
        };
        Ok(TExpr {
            kind: TExprKind::If {
                condition: Box::new(condition),
                then_block,
                else_block,
            },
            ty,
            span,
        })
    }

    fn declare(
        &mut self,
        name: &str,
        ty: Ty,
        mutable: bool,
        span: Span,
    ) -> Result<Binding, CheckError> {
        let scope = self.locals.last_mut().expect("function scope exists");
        if let Some(previous) = scope.get(name) {
            return Err(CheckError {
                span,
                message: format!(
                    "'{}' is already declared in this scope (first declared on line {}); choose another name",
                    name, previous.span.line
                ),
            });
        }
        let binding = Binding {
            id: self.next_local,
            name: name.to_owned(),
            ty,
            mutable,
            span,
        };
        self.next_local += 1;
        scope.insert(name.to_owned(), binding.clone());
        Ok(binding)
    }

    fn find_binding(&self, name: &str) -> Option<Binding> {
        self.locals
            .iter()
            .rev()
            .find_map(|scope| scope.get(name).cloned())
    }

    fn unknown_local(&self, name: &str, span: Span) -> CheckError {
        let mut candidates = self
            .locals
            .iter()
            .flat_map(|s| s.keys().cloned())
            .collect::<Vec<_>>();
        candidates.extend(self.signatures.keys().cloned());
        if let Some(suggestion) = close_name(name, &candidates) {
            CheckError {
                span,
                message: format!("unknown name '{}'; did you mean '{}'", name, suggestion),
            }
        } else {
            CheckError {
                span,
                message: format!("unknown name '{}'; declare it with let or var", name),
            }
        }
    }

    fn unknown_function(&self, name: &str, span: Span) -> CheckError {
        let mut candidates = self.signatures.keys().cloned().collect::<Vec<_>>();
        candidates.push("print".to_owned());
        if let Some(suggestion) = close_name(name, &candidates) {
            CheckError {
                span,
                message: format!("unknown function '{}'; did you mean '{}'", name, suggestion),
            }
        } else {
            CheckError {
                span,
                message: format!("unknown function '{}'; declare it with fn", name),
            }
        }
    }

    fn type_mismatch(&self, actual: Ty, expected: Ty, span: Span) -> Result<(), CheckError> {
        if actual == expected || actual == Ty::Never {
            Ok(())
        } else {
            Err(CheckError {
                span,
                message: format!(
                    "expected {}, found {}; cast explicitly with ({} )value",
                    expected.name(),
                    actual.name(),
                    expected.name()
                )
                .replace(" )", ")"),
            })
        }
    }

    fn mixed_types_error(&self, left: Ty, right: Ty, span: Span) -> CheckError {
        CheckError {
            span,
            message: format!(
                "cannot combine {} and {}; cast the left value to {} or the right value to {}",
                left.name(),
                right.name(),
                right.name(),
                left.name()
            ),
        }
    }

    fn check_recursion(&self) -> Result<(), CheckError> {
        let n = self.ast_functions.len();
        let mut graph = vec![Vec::<Edge>::new(); n];
        for edge in &self.edges {
            graph[edge.from].push(*edge);
        }
        let mut state = vec![0u8; n];
        fn visit(
            v: usize,
            graph: &[Vec<Edge>],
            state: &mut [u8],
            names: &[String],
        ) -> Result<(), CheckError> {
            state[v] = 1;
            for edge in &graph[v] {
                if state[edge.to] == 1 {
                    return Err(CheckError {
                        span: edge.span,
                        message: format!(
                            "call cycle detected at '{}'; recursion is opt-in with 'recursive' and is not supported yet",
                            names[edge.to]
                        ),
                    });
                }
                if state[edge.to] == 0 {
                    visit(edge.to, graph, state, names)?;
                }
            }
            state[v] = 2;
            Ok(())
        }
        let names = self
            .ast_functions
            .iter()
            .map(|f| f.name.clone())
            .collect::<Vec<_>>();
        for v in 0..n {
            if state[v] == 0 {
                visit(v, &graph, &mut state, &names)?;
            }
        }
        Ok(())
    }
}

fn parse_ty(ty: &TypeAst) -> Result<Ty, CheckError> {
    match ty.name.as_str() {
        "int" => Ok(Ty::Int),
        "long" => Ok(Ty::Long),
        "bool" => Ok(Ty::Bool),
        _ => Err(CheckError {
            span: ty.span,
            message: format!("unknown type '{}'; use int, long, or bool", ty.name),
        }),
    }
}

fn block_value_ty(block: &TBlock) -> Ty {
    if !block.falls_through {
        Ty::Never
    } else if let Some(tail) = &block.tail {
        tail.ty
    } else {
        Ty::Unit
    }
}

fn statement_falls_through(stmt: &TStmtKind) -> bool {
    match stmt {
        TStmtKind::Return(_) => false,
        TStmtKind::Let { value, .. } => value.ty != Ty::Never,
        TStmtKind::Assign { value, .. } => value.ty != Ty::Never,
        TStmtKind::Expr(expr) => expr.ty != Ty::Never,
        TStmtKind::If {
            then_block,
            else_block,
            ..
        } => match else_block {
            None => true,
            Some(other) => then_block.falls_through || other.falls_through,
        },
    }
}

fn is_unsuffixed_integer(expr: &Expr) -> bool {
    matches!(
        expr.kind,
        ExprKind::Integer {
            long_suffix: false,
            ..
        }
    )
}

fn assign_binary(op: AssignOp) -> BinaryOp {
    match op {
        AssignOp::Add => BinaryOp::Add,
        AssignOp::Sub => BinaryOp::Sub,
        AssignOp::Mul => BinaryOp::Mul,
        AssignOp::Div => BinaryOp::Div,
        AssignOp::Rem => BinaryOp::Rem,
        AssignOp::Set => unreachable!(),
    }
}

fn assign_spelling(op: AssignOp) -> &'static str {
    match op {
        AssignOp::Set => "=",
        AssignOp::Add => "+",
        AssignOp::Sub => "-",
        AssignOp::Mul => "*",
        AssignOp::Div => "/",
        AssignOp::Rem => "%",
    }
}

fn binary_spelling(op: BinaryOp) -> &'static str {
    match op {
        BinaryOp::Add => "+",
        BinaryOp::Sub => "-",
        BinaryOp::Mul => "*",
        BinaryOp::Div => "/",
        BinaryOp::Rem => "%",
        BinaryOp::WrapAdd => "+%",
        BinaryOp::WrapSub => "-%",
        BinaryOp::WrapMul => "*%",
        BinaryOp::Eq => "==",
        BinaryOp::Ne => "!=",
        BinaryOp::Lt => "<",
        BinaryOp::Le => "<=",
        BinaryOp::Gt => ">",
        BinaryOp::Ge => ">=",
        BinaryOp::And => "&&",
        BinaryOp::Or => "||",
        BinaryOp::BitAnd => "&",
        BinaryOp::BitOr => "|",
        BinaryOp::BitXor => "^",
        BinaryOp::Shl => "<<",
        BinaryOp::Shr => ">>",
    }
}

fn close_name(name: &str, candidates: &[String]) -> Option<String> {
    candidates
        .iter()
        .filter_map(|candidate| {
            let distance = levenshtein(name, candidate);
            (distance <= 2 && distance <= name.len().max(candidate.len()) / 3 + 1)
                .then_some((distance, candidate))
        })
        .min_by_key(|(distance, candidate)| (*distance, candidate.len()))
        .map(|(_, value)| value.clone())
}

fn levenshtein(a: &str, b: &str) -> usize {
    let a = a.chars().collect::<Vec<_>>();
    let b = b.chars().collect::<Vec<_>>();
    let mut row = (0..=b.len()).collect::<Vec<_>>();
    for (i, ac) in a.iter().enumerate() {
        let mut previous = row[0];
        row[0] = i + 1;
        for (j, bc) in b.iter().enumerate() {
            let old = row[j + 1];
            row[j + 1] = (row[j] + 1)
                .min(row[j + 1] + 1)
                .min(previous + usize::from(ac != bc));
            previous = old;
        }
    }
    row[b.len()]
}
