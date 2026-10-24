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
    loop_counter: bool,
}

#[derive(Clone, Copy)]
struct Edge {
    from: usize,
    to: usize,
    span: Span,
}

pub fn check_package(
    programs: Vec<Program>,
    files: Vec<String>,
    require_main: bool,
) -> Result<TProgram, CheckError> {
    Checker::new(programs, files, require_main).run()
}

struct Checker {
    programs: Vec<Program>,
    files: Vec<String>,
    require_main: bool,
    signatures: HashMap<String, Signature>,
    ast_functions: Vec<Function>,
    ast_tests: Vec<Test>,
    edges: Vec<Edge>,
    locals: Vec<HashMap<String, Binding>>,
    scope_ids: Vec<usize>,
    next_scope: usize,
    next_local: usize,
    current_function: usize,
    current_return: Ty,
    current_is_test: bool,
    loop_depth: usize,
}

impl Checker {
    fn new(programs: Vec<Program>, files: Vec<String>, require_main: bool) -> Self {
        Self {
            programs,
            files,
            require_main,
            signatures: HashMap::new(),
            ast_functions: Vec::new(),
            ast_tests: Vec::new(),
            edges: Vec::new(),
            locals: Vec::new(),
            scope_ids: Vec::new(),
            next_scope: 0,
            next_local: 0,
            current_function: 0,
            current_return: Ty::Unit,
            current_is_test: false,
            loop_depth: 0,
        }
    }

    fn run(mut self) -> Result<TProgram, CheckError> {
        let mut test_names = HashMap::<String, Span>::new();
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
            for test in p.tests {
                if let Some(previous) = test_names.get(&test.name) {
                    return Err(CheckError {
                        span: test.span,
                        message: format!(
                            "test '{}' is declared more than once (first declared on line {}); choose a unique name",
                            test.name, previous.line
                        ),
                    });
                }
                test_names.insert(test.name.clone(), test.span);
                self.ast_tests.push(test);
            }
        }
        if self.require_main || self.signatures.contains_key("main") {
            self.check_entry()?;
        }
        let mut functions = Vec::with_capacity(self.ast_functions.len() + self.ast_tests.len());
        for id in 0..self.ast_functions.len() {
            functions.push(self.check_function(id)?);
        }
        let mut tests = Vec::with_capacity(self.ast_tests.len());
        for index in 0..self.ast_tests.len() {
            let (function, test) = self.check_test(index)?;
            tests.push(test);
            functions.push(function);
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
            tests,
            files: self.files,
            call_graph,
        })
    }

    fn check_entry(&self) -> Result<(), CheckError> {
        let Some(sig) = self.signatures.get("main") else {
            if !self.require_main {
                return Ok(());
            }
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
        self.current_is_test = false;
        self.loop_depth = 0;
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.next_scope = 1;
        self.scope_ids.clear();
        self.scope_ids.push(0);
        let mut params = Vec::new();
        for (i, param) in function.params.iter().enumerate() {
            let ty = signature.params[i];
            let binding = self.declare(&param.name, ty, false, param.span, false)?;
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
            is_test: false,
        })
    }

    fn check_test(&mut self, index: usize) -> Result<(TFunction, TTest), CheckError> {
        let test = self.ast_tests[index].clone();
        let id = self.ast_functions.len() + index;
        self.current_function = id;
        self.current_return = Ty::Unit;
        self.current_is_test = true;
        self.loop_depth = 0;
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.next_scope = 1;
        self.scope_ids.clear();
        self.scope_ids.push(0);
        let body = self.check_block(&test.body, false, None)?;
        if body.falls_through {
            if let Some(tail) = &body.tail {
                if tail.ty != Ty::Unit && tail.ty != Ty::Never {
                    return Err(CheckError {
                        span: tail.span,
                        message: format!(
                            "test '{}' ends with {}; remove the value or use it in a statement",
                            test.name,
                            tail.ty.name()
                        ),
                    });
                }
            }
        }
        self.locals.clear();
        self.current_is_test = false;
        Ok((
            TFunction {
                id,
                name: format!("__nl_test_{index}"),
                params: Vec::new(),
                result: Ty::Unit,
                body,
                span: test.span,
                is_test: true,
            },
            TTest {
                name: test.name,
                function_id: id,
                span: test.span,
            },
        ))
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
                let binding = self.declare(name, ty, *mutable, stmt.span, false)?;
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
                        message: if binding.loop_counter {
                            format!(
                                "cannot assign to loop counter '{}'; loop counters are immutable",
                                name
                            )
                        } else {
                            format!(
                                "cannot assign to immutable 'let' binding '{}'; declare it with 'var'",
                                name
                            )
                        },
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
                if self.current_is_test {
                    return Err(CheckError {
                        span: stmt.span,
                        message:
                            "a test cannot return; let the test finish so all expectations run"
                                .to_owned(),
                    });
                }
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
            StmtKind::For {
                name,
                annotation,
                start,
                end,
                inclusive,
                body,
            } => {
                let ty =
                    self.infer_loop_type(name, annotation.as_ref(), start, end, body, stmt.span)?;
                let typed_start = self.check_expr(start, Some(ty))?;
                let typed_end = self.check_expr(end, Some(ty))?;
                self.locals.push(HashMap::new());
                self.scope_ids.push(self.next_scope);
                self.next_scope += 1;
                let counter = self.declare(name, ty, false, stmt.span, true)?;
                self.loop_depth += 1;
                let typed_body = self.check_block(body, true, None)?;
                self.loop_depth -= 1;
                self.locals.pop();
                self.scope_ids.pop();
                TStmtKind::For {
                    id: counter.id,
                    ty,
                    start: typed_start,
                    end: typed_end,
                    inclusive: *inclusive,
                    body: typed_body,
                }
            }
            StmtKind::Break => {
                if self.loop_depth == 0 {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "'break' is only valid inside a loop; move it into a for body"
                            .to_owned(),
                    });
                }
                TStmtKind::Break
            }
            StmtKind::Continue => {
                if self.loop_depth == 0 {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "'continue' is only valid inside a loop; move it into a for body"
                            .to_owned(),
                    });
                }
                TStmtKind::Continue
            }
            StmtKind::Expect { value, source } => {
                if !self.current_is_test {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "'expect' is only valid inside a test block".to_owned(),
                    });
                }
                let typed = self.check_expr(value, Some(Ty::Bool))?;
                let kind = if let ExprKind::Binary { op, .. } = &value.kind {
                    if is_comparison(*op) {
                        if let TExprKind::Binary { left, right, .. } = typed.kind {
                            TExpectKind::Compare {
                                op: *op,
                                left: *left,
                                right: *right,
                            }
                        } else {
                            unreachable!("comparison expression typechecks as binary")
                        }
                    } else {
                        TExpectKind::Bool(typed)
                    }
                } else {
                    TExpectKind::Bool(typed)
                };
                TStmtKind::Expect {
                    source: source.clone(),
                    kind,
                }
            }
            StmtKind::Block(block) => TStmtKind::Block(self.check_block(block, true, None)?),
        };
        Ok(TStmt {
            kind,
            span: stmt.span,
        })
    }

    fn infer_loop_type(
        &self,
        counter: &str,
        annotation: Option<&TypeAst>,
        start: &Expr,
        end: &Expr,
        body: &Block,
        span: Span,
    ) -> Result<Ty, CheckError> {
        let mut constraints = Vec::new();
        if let Some(annotation) = annotation {
            let ty = parse_ty(annotation)?;
            if !ty.is_numeric() {
                return Err(CheckError {
                    span: annotation.span,
                    message: "a loop counter must be int or long; use one of those types"
                        .to_owned(),
                });
            }
            constraints.push(ty);
        }
        for bound in [start, end] {
            if let Some(ty) = self.natural_expr_type(bound) {
                if !ty.is_numeric() {
                    return Err(CheckError {
                        span: bound.span,
                        message: format!("a range bound must be int or long, found {}", ty.name()),
                    });
                }
                constraints.push(ty);
            }
        }
        for statement in &body.statements {
            self.collect_loop_constraints_stmt(statement, counter, &mut constraints);
        }
        if let Some(tail) = &body.tail {
            self.collect_loop_constraints_expr(tail, counter, None, &mut constraints);
        }
        let ty = constraints.first().copied().unwrap_or(Ty::Int);
        if let Some(other) = constraints.iter().copied().find(|other| *other != ty) {
            return Err(CheckError {
                span,
                message: format!(
                    "loop counter and range uses conflict between {} and {}; cast a bound or use explicitly typed values of one type",
                    ty.name(),
                    other.name()
                ),
            });
        }
        Ok(ty)
    }

    fn natural_expr_type(&self, expr: &Expr) -> Option<Ty> {
        self.natural_expr_type_inner(expr, None)
    }

    fn natural_expr_type_inner(&self, expr: &Expr, shadowed_counter: Option<&str>) -> Option<Ty> {
        match &expr.kind {
            ExprKind::Integer {
                long_suffix: true, ..
            } => Some(Ty::Long),
            ExprKind::Integer { .. } => None,
            ExprKind::Bool(_) => Some(Ty::Bool),
            ExprKind::Name(name) if shadowed_counter == Some(name.as_str()) => None,
            ExprKind::Name(name) => self.find_binding(name).map(|binding| binding.ty),
            ExprKind::Call { name, .. } => {
                if name == "print" {
                    Some(Ty::Unit)
                } else {
                    self.signatures.get(name).map(|signature| signature.result)
                }
            }
            ExprKind::ToLong { .. } => Some(Ty::Long),
            ExprKind::Cast { ty, .. } => parse_ty(ty).ok(),
            ExprKind::Unary { op, value, .. } => match op {
                UnaryOp::Not => Some(Ty::Bool),
                UnaryOp::Neg => self.natural_expr_type_inner(value, shadowed_counter),
            },
            ExprKind::Binary {
                op, left, right, ..
            } => {
                if matches!(
                    op,
                    BinaryOp::Eq
                        | BinaryOp::Ne
                        | BinaryOp::Lt
                        | BinaryOp::Le
                        | BinaryOp::Gt
                        | BinaryOp::Ge
                        | BinaryOp::And
                        | BinaryOp::Or
                ) {
                    Some(Ty::Bool)
                } else {
                    let left = self.natural_expr_type_inner(left, shadowed_counter);
                    let right = self.natural_expr_type_inner(right, shadowed_counter);
                    match (left, right) {
                        (Some(left), Some(right)) if left == right => Some(left),
                        (Some(left), None) if left.is_numeric() => Some(left),
                        (None, Some(right)) if right.is_numeric() => Some(right),
                        _ => None,
                    }
                }
            }
            ExprKind::If {
                then_block,
                else_block,
                ..
            } => {
                let left = then_block
                    .tail
                    .as_deref()
                    .and_then(|tail| self.natural_expr_type_inner(tail, shadowed_counter));
                let right = else_block
                    .as_ref()
                    .and_then(|block| block.tail.as_deref())
                    .and_then(|tail| self.natural_expr_type_inner(tail, shadowed_counter));
                if left == right { left } else { None }
            }
        }
    }

    fn collect_loop_constraints_stmt(&self, stmt: &Stmt, counter: &str, constraints: &mut Vec<Ty>) {
        match &stmt.kind {
            StmtKind::Let {
                annotation, value, ..
            } => {
                self.collect_loop_constraints_expr(
                    value,
                    counter,
                    annotation.as_ref().and_then(|ty| parse_ty(ty).ok()),
                    constraints,
                );
            }
            StmtKind::Assign { name, value, .. } => {
                let expected = self.find_binding(name).map(|binding| binding.ty);
                self.collect_loop_constraints_expr(value, counter, expected, constraints);
            }
            StmtKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_loop_constraints_expr(
                        value,
                        counter,
                        Some(self.current_return),
                        constraints,
                    );
                }
            }
            StmtKind::Expr(expr) => {
                self.collect_loop_constraints_expr(expr, counter, None, constraints)
            }
            StmtKind::For {
                name,
                start,
                end,
                body,
                ..
            } => {
                self.collect_loop_constraints_expr(start, counter, None, constraints);
                self.collect_loop_constraints_expr(end, counter, None, constraints);
                if name != counter {
                    self.collect_loop_constraints_block(body, counter, constraints);
                }
            }
            StmtKind::Expect { value, .. } => {
                self.collect_loop_constraints_expr(value, counter, Some(Ty::Bool), constraints);
            }
            StmtKind::Block(block) => {
                self.collect_loop_constraints_block(block, counter, constraints)
            }
            StmtKind::Break | StmtKind::Continue => {}
        }
    }

    fn collect_loop_constraints_block(
        &self,
        block: &Block,
        counter: &str,
        constraints: &mut Vec<Ty>,
    ) {
        for statement in &block.statements {
            self.collect_loop_constraints_stmt(statement, counter, constraints);
        }
        if let Some(tail) = &block.tail {
            self.collect_loop_constraints_expr(tail, counter, None, constraints);
        }
    }

    fn collect_loop_constraints_expr(
        &self,
        expr: &Expr,
        counter: &str,
        expected: Option<Ty>,
        constraints: &mut Vec<Ty>,
    ) {
        match &expr.kind {
            ExprKind::Name(name) if name == counter => {
                if let Some(ty) = expected.filter(|ty| ty.is_numeric()) {
                    constraints.push(ty);
                }
            }
            ExprKind::Name(_) | ExprKind::Integer { .. } | ExprKind::Bool(_) => {}
            ExprKind::Call { name, args, .. } => {
                let parameters = self.signatures.get(name).map(|sig| sig.params.clone());
                for (index, arg) in args.iter().enumerate() {
                    let want = parameters
                        .as_ref()
                        .and_then(|params| params.get(index))
                        .copied();
                    self.collect_loop_constraints_expr(arg, counter, want, constraints);
                }
            }
            ExprKind::ToLong { value, .. } => {
                self.collect_loop_constraints_expr(value, counter, Some(Ty::Int), constraints);
            }
            ExprKind::Cast { ty, value, .. } => {
                self.collect_loop_constraints_expr(value, counter, parse_ty(ty).ok(), constraints);
            }
            ExprKind::Unary { op, value, .. } => {
                let want = match op {
                    UnaryOp::Neg => expected.filter(|ty| ty.is_numeric()),
                    UnaryOp::Not => Some(Ty::Bool),
                };
                self.collect_loop_constraints_expr(value, counter, want, constraints);
            }
            ExprKind::Binary {
                op, left, right, ..
            } => {
                let (left_want, right_want) = if matches!(op, BinaryOp::And | BinaryOp::Or) {
                    (Some(Ty::Bool), Some(Ty::Bool))
                } else {
                    let contextual = if matches!(
                        op,
                        BinaryOp::Add
                            | BinaryOp::Sub
                            | BinaryOp::Mul
                            | BinaryOp::Div
                            | BinaryOp::Rem
                            | BinaryOp::WrapAdd
                            | BinaryOp::WrapSub
                            | BinaryOp::WrapMul
                            | BinaryOp::BitAnd
                            | BinaryOp::BitOr
                            | BinaryOp::BitXor
                            | BinaryOp::Shl
                            | BinaryOp::Shr
                    ) {
                        expected.filter(|ty| ty.is_numeric())
                    } else {
                        None
                    };
                    let left_natural = self
                        .natural_expr_type_inner(left, Some(counter))
                        .filter(|ty| ty.is_numeric());
                    let right_natural = self
                        .natural_expr_type_inner(right, Some(counter))
                        .filter(|ty| ty.is_numeric());
                    (contextual.or(right_natural), contextual.or(left_natural))
                };
                self.collect_loop_constraints_expr(left, counter, left_want, constraints);
                self.collect_loop_constraints_expr(right, counter, right_want, constraints);
            }
            ExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                self.collect_loop_constraints_expr(condition, counter, Some(Ty::Bool), constraints);
                for block in std::iter::once(then_block).chain(else_block.iter()) {
                    if let Some(tail) = &block.tail {
                        self.collect_loop_constraints_expr(tail, counter, expected, constraints);
                    }
                    for statement in &block.statements {
                        self.collect_loop_constraints_stmt(statement, counter, constraints);
                    }
                }
            }
        }
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
            ExprKind::ToLong { value, method_span } => {
                let typed = self.check_expr(value, None)?;
                if typed.ty != Ty::Int {
                    return Err(CheckError {
                        span: *method_span,
                        message: format!(
                            "no method 'to_long' on {}; 'to_long' is available on int",
                            typed.ty.name()
                        ),
                    });
                }
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
        loop_counter: bool,
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
            loop_counter,
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
        let n = self.ast_functions.len() + self.ast_tests.len();
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
        let mut names = self
            .ast_functions
            .iter()
            .map(|f| f.name.clone())
            .collect::<Vec<_>>();
        names.extend(
            (0..self.ast_tests.len()).map(|index| format!("test {}", self.ast_tests[index].name)),
        );
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
        TStmtKind::For { .. } | TStmtKind::Expect { .. } => true,
        TStmtKind::Break | TStmtKind::Continue => false,
        TStmtKind::Block(block) => block.falls_through,
    }
}

fn is_comparison(op: BinaryOp) -> bool {
    matches!(
        op,
        BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge
    )
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
