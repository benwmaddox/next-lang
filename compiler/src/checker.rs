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
    types: Vec<TType>,
    enum_ids: HashMap<String, Ty>,
    generic_ids: HashMap<(u8, Ty, Ty), Ty>,
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
            types: vec![
                TType {
                    name: "int".to_owned(),
                    kind: TTypeKind::Int,
                    span: Span::default(),
                },
                TType {
                    name: "long".to_owned(),
                    kind: TTypeKind::Long,
                    span: Span::default(),
                },
                TType {
                    name: "bool".to_owned(),
                    kind: TTypeKind::Bool,
                    span: Span::default(),
                },
                TType {
                    name: "()".to_owned(),
                    kind: TTypeKind::Unit,
                    span: Span::default(),
                },
                TType {
                    name: "never".to_owned(),
                    kind: TTypeKind::Never,
                    span: Span::default(),
                },
            ],
            enum_ids: HashMap::new(),
            generic_ids: HashMap::new(),
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
        self.register_enum_names()?;
        self.fill_enum_cases()?;
        self.check_recursive_value_types()?;
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
                    .map(|p| self.parse_type(&p.ty))
                    .collect::<Result<Vec<_>, _>>()?;
                let result = function
                    .result
                    .as_ref()
                    .map(|ty| self.parse_type(ty))
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
            types: self.types,
        })
    }

    fn register_enum_names(&mut self) -> Result<(), CheckError> {
        for program in &self.programs {
            for declaration in &program.enums {
                if matches!(
                    declaration.name.as_str(),
                    "int" | "long" | "bool" | "Option" | "Result"
                ) || self.enum_ids.contains_key(&declaration.name)
                {
                    return Err(CheckError {
                        span: declaration.span,
                        message: format!(
                            "type '{}' is declared more than once or shadows a built-in type",
                            declaration.name
                        ),
                    });
                }
                let ty = Ty(self.types.len());
                self.enum_ids.insert(declaration.name.clone(), ty);
                self.types.push(TType {
                    name: declaration.name.clone(),
                    kind: TTypeKind::Enum(Vec::new()),
                    span: declaration.span,
                });
            }
        }
        Ok(())
    }

    fn fill_enum_cases(&mut self) -> Result<(), CheckError> {
        let declarations = self
            .programs
            .iter()
            .flat_map(|p| p.enums.clone())
            .collect::<Vec<_>>();
        for declaration in declarations {
            let ty = self.enum_ids[&declaration.name];
            let mut names = HashMap::<String, Span>::new();
            let mut cases = Vec::new();
            for case in declaration.cases {
                if let Some(previous) = names.insert(case.name.clone(), case.span) {
                    return Err(CheckError {
                        span: case.span,
                        message: format!(
                            "case '{}.{}' is declared twice (first on line {})",
                            declaration.name, case.name, previous.line
                        ),
                    });
                }
                let payload = case
                    .payload
                    .iter()
                    .map(|t| self.parse_type(t))
                    .collect::<Result<Vec<_>, _>>()?;
                cases.push(TCase {
                    name: case.name,
                    payload,
                    span: case.span,
                });
            }
            self.types[ty.0].kind = TTypeKind::Enum(cases);
        }
        Ok(())
    }

    fn parse_type(&mut self, ty: &TypeAst) -> Result<Ty, CheckError> {
        if ty.name == "int" && ty.args.is_empty() {
            return Ok(Ty::Int);
        }
        if ty.name == "long" && ty.args.is_empty() {
            return Ok(Ty::Long);
        }
        if ty.name == "bool" && ty.args.is_empty() {
            return Ok(Ty::Bool);
        }
        if ty.name == "()" && ty.args.is_empty() {
            return Ok(Ty::Unit);
        }
        match ty.name.as_str() {
            "Option" if ty.args.len() == 1 => {
                let value = self.parse_type(&ty.args[0])?;
                Ok(self.intern_generic(
                    1,
                    value,
                    Ty::Unit,
                    format!("Option<{}>", self.type_name(value)),
                    ty.span,
                    TTypeKind::Option(value),
                ))
            }
            "Result" if ty.args.len() == 2 => {
                let ok = self.parse_type(&ty.args[0])?;
                let err = self.parse_type(&ty.args[1])?;
                Ok(self.intern_generic(
                    2,
                    ok,
                    err,
                    format!("Result<{}, {}>", self.type_name(ok), self.type_name(err)),
                    ty.span,
                    TTypeKind::Result(ok, err),
                ))
            }
            "Option" | "Result" => Err(CheckError {
                span: ty.span,
                message: format!(
                    "type '{}' has the wrong number of parameters; use Option<T> or Result<T, E>",
                    ty.name
                ),
            }),
            _ if !ty.args.is_empty() => Err(CheckError {
                span: ty.span,
                message: format!(
                    "'{}' is not a generic type; only Option<T> and Result<T, E> accept type arguments",
                    ty.name
                ),
            }),
            _ => self.enum_ids.get(&ty.name).copied().ok_or_else(|| {
                let mut names = self.enum_ids.keys().cloned().collect::<Vec<_>>();
                names.extend([
                    "int".to_owned(),
                    "long".to_owned(),
                    "bool".to_owned(),
                    "Option".to_owned(),
                    "Result".to_owned(),
                ]);
                if let Some(suggestion) = close_name(&ty.name, &names) {
                    CheckError {
                        span: ty.span,
                        message: format!(
                            "unknown type '{}'; did you mean '{}'",
                            ty.name, suggestion
                        ),
                    }
                } else {
                    CheckError {
                        span: ty.span,
                        message: format!("unknown type '{}'; declare it with enum", ty.name),
                    }
                }
            }),
        }
    }

    fn intern_generic(
        &mut self,
        kind: u8,
        first: Ty,
        second: Ty,
        name: String,
        span: Span,
        desc: TTypeKind,
    ) -> Ty {
        let key = (kind, first, second);
        if let Some(ty) = self.generic_ids.get(&key) {
            return *ty;
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name,
            kind: desc,
            span,
        });
        self.generic_ids.insert(key, ty);
        ty
    }

    fn type_name(&self, ty: Ty) -> String {
        self.types
            .get(ty.0)
            .map(|t| t.name.clone())
            .unwrap_or_else(|| ty.name().to_owned())
    }

    fn check_recursive_value_types(&self) -> Result<(), CheckError> {
        fn visit(
            id: usize,
            types: &[TType],
            state: &mut [u8],
            stack: &mut Vec<usize>,
        ) -> Option<usize> {
            if state[id] == 1 {
                return Some(id);
            }
            if state[id] == 2 {
                return None;
            }
            state[id] = 1;
            stack.push(id);
            let children = match &types[id].kind {
                TTypeKind::Enum(cases) => cases
                    .iter()
                    .flat_map(|c| c.payload.iter().copied())
                    .collect::<Vec<_>>(),
                TTypeKind::Option(t) => vec![*t],
                TTypeKind::Result(a, b) => vec![*a, *b],
                _ => Vec::new(),
            };
            for child in children {
                if let Some(cycle) = visit(child.0, types, state, stack) {
                    if types[cycle].name != "Option" && types[cycle].name != "Result" {
                        return Some(cycle);
                    }
                    return Some(cycle);
                }
            }
            stack.pop();
            state[id] = 2;
            None
        }
        let mut state = vec![0; self.types.len()];
        for id in 5..self.types.len() {
            let mut stack = Vec::new();
            if visit(id, &self.types, &mut state, &mut stack).is_some() {
                return Err(CheckError {
                    span: self.types[id].span,
                    message: format!(
                        "value type '{}' contains itself directly or through Option/Result and would have infinite size",
                        self.types[id].name
                    ),
                });
            }
        }
        Ok(())
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
                    self.type_name(signature.result)
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
                                self.type_name(tail.ty)
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
                            self.type_name(tail.ty)
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
                let annotated = annotation
                    .as_ref()
                    .map(|ty| self.parse_type(ty))
                    .transpose()?;
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
                                self.type_name(binding.ty)
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
                                    self.type_name(self.current_return)
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
        &mut self,
        counter: &str,
        annotation: Option<&TypeAst>,
        start: &Expr,
        end: &Expr,
        body: &Block,
        span: Span,
    ) -> Result<Ty, CheckError> {
        let mut constraints = Vec::new();
        if let Some(annotation) = annotation {
            let ty = self.parse_type(annotation)?;
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
                        message: format!(
                            "a range bound must be int or long, found {}",
                            self.type_name(ty)
                        ),
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
                    self.type_name(ty),
                    self.type_name(other)
                ),
            });
        }
        Ok(ty)
    }

    fn natural_expr_type(&mut self, expr: &Expr) -> Option<Ty> {
        self.natural_expr_type_inner(expr, None)
    }

    fn natural_expr_type_inner(
        &mut self,
        expr: &Expr,
        shadowed_counter: Option<&str>,
    ) -> Option<Ty> {
        match &expr.kind {
            ExprKind::Unit => Some(Ty::Unit),
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
            ExprKind::Cast { ty, .. } => self.parse_type(ty).ok(),
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
            ExprKind::QualifiedCase { enum_name, .. } => self.enum_ids.get(enum_name).copied(),
            ExprKind::MethodCall { receiver, name, .. } => {
                let receiver_ty = self.natural_expr_type_inner(receiver, shadowed_counter)?;
                match (self.types[receiver_ty.0].kind.clone(), name.as_str()) {
                    (TTypeKind::Option(_), "is_none" | "is_some")
                    | (TTypeKind::Result(..), "is_ok" | "is_err") => Some(Ty::Bool),
                    (TTypeKind::Option(value), "unwrap") => Some(value),
                    (TTypeKind::Result(ok, _), "unwrap") => Some(ok),
                    (TTypeKind::Result(ok, _), "ok") => Some(self.option_type(ok, expr.span)),
                    _ => None,
                }
            }
            ExprKind::OptionalCall { name, .. } => self.signatures.get(name).map(|sig| sig.result),
            ExprKind::Try(value) => {
                let receiver_ty = self.natural_expr_type_inner(value, shadowed_counter)?;
                match self.types[receiver_ty.0].kind {
                    TTypeKind::Option(inner) => Some(inner),
                    TTypeKind::Result(ok, _) => Some(ok),
                    _ => None,
                }
            }
            ExprKind::Return(_) | ExprKind::LoopExit(_) => Some(Ty::Never),
            ExprKind::Match { arms, .. } => arms
                .first()
                .and_then(|arm| arm.body.tail.as_deref())
                .and_then(|e| self.natural_expr_type_inner(e, shadowed_counter)),
        }
    }

    fn collect_loop_constraints_stmt(
        &mut self,
        stmt: &Stmt,
        counter: &str,
        constraints: &mut Vec<Ty>,
    ) {
        match &stmt.kind {
            StmtKind::Let {
                annotation, value, ..
            } => {
                let expected = annotation.as_ref().and_then(|ty| self.parse_type(ty).ok());
                self.collect_loop_constraints_expr(value, counter, expected, constraints);
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
        &mut self,
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
        &mut self,
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
            ExprKind::Name(_) | ExprKind::Integer { .. } | ExprKind::Bool(_) | ExprKind::Unit => {}
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
            ExprKind::QualifiedCase {
                args,
                enum_name,
                case_name,
                ..
            } => {
                let payload = self
                    .enum_ids
                    .get(enum_name)
                    .and_then(|ty| self.find_case_in_type(*ty, case_name))
                    .map(|(_, c)| c.payload);
                for (i, arg) in args.iter().enumerate() {
                    self.collect_loop_constraints_expr(
                        arg,
                        counter,
                        payload.as_ref().and_then(|p| p.get(i)).copied(),
                        constraints,
                    );
                }
            }
            ExprKind::MethodCall { receiver, args, .. }
            | ExprKind::OptionalCall { receiver, args, .. } => {
                self.collect_loop_constraints_expr(receiver, counter, None, constraints);
                for arg in args {
                    self.collect_loop_constraints_expr(arg, counter, None, constraints);
                }
            }
            ExprKind::Try(value) => {
                self.collect_loop_constraints_expr(value, counter, None, constraints)
            }
            ExprKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_loop_constraints_expr(
                        value,
                        counter,
                        Some(self.current_return),
                        constraints,
                    );
                }
            }
            ExprKind::LoopExit(_) => {}
            ExprKind::Match { scrutinee, arms } => {
                self.collect_loop_constraints_expr(scrutinee, counter, None, constraints);
                for arm in arms {
                    self.collect_loop_constraints_block(&arm.body, counter, constraints);
                }
            }
            ExprKind::ToLong { value, .. } => {
                self.collect_loop_constraints_expr(value, counter, Some(Ty::Int), constraints);
            }
            ExprKind::Cast { ty, value, .. } => {
                let expected = self.parse_type(ty).ok();
                self.collect_loop_constraints_expr(value, counter, expected, constraints);
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

    fn option_type(&mut self, value: Ty, span: Span) -> Ty {
        self.intern_generic(
            1,
            value,
            Ty::Unit,
            format!("Option<{}>", self.type_name(value)),
            span,
            TTypeKind::Option(value),
        )
    }

    fn case_def(&self, ty: Ty, index: usize) -> TCase {
        self.types[ty.0].cases()[index].clone()
    }

    fn find_case_in_type(&self, ty: Ty, name: &str) -> Option<(usize, TCase)> {
        self.types[ty.0]
            .cases()
            .into_iter()
            .enumerate()
            .find(|(_, case)| case.name == name)
    }

    fn unknown_case(&self, name: &str, span: Span) -> CheckError {
        let candidates = self
            .types
            .iter()
            .flat_map(|ty| ty.cases())
            .map(|c| c.name)
            .collect::<Vec<_>>();
        if let Some(suggestion) = close_name(name, &candidates) {
            CheckError {
                span,
                message: format!(
                    "unknown enum case '{}'; did you mean '{}'",
                    name, suggestion
                ),
            }
        } else {
            CheckError {
                span,
                message: format!(
                    "unknown enum case '{}'; qualify it with its enum name",
                    name
                ),
            }
        }
    }

    fn check_constructor(
        &mut self,
        ty: Ty,
        case_index: usize,
        args: &[Expr],
        span: Span,
        expected: Option<Ty>,
    ) -> Result<(TExprKind, Ty), CheckError> {
        let case = self.case_def(ty, case_index);
        if args.len() != case.payload.len() {
            return Err(CheckError {
                span,
                message: format!(
                    "case '{}.{}' takes {} payload value(s), but got {}",
                    self.type_name(ty),
                    case.name,
                    case.payload.len(),
                    args.len()
                ),
            });
        }
        let mut values = Vec::new();
        for (arg, payload_ty) in args.iter().zip(case.payload) {
            values.push(self.check_expr(arg, Some(payload_ty))?);
        }
        if let Some(want) = expected {
            self.type_mismatch(ty, want, span)?;
        }
        Ok((
            TExprKind::Construct {
                case_index,
                args: values,
            },
            ty,
        ))
    }

    fn check_unqualified_constructor(
        &mut self,
        name: &str,
        args: &[Expr],
        span: Span,
        expected: Option<Ty>,
    ) -> Result<(TExprKind, Ty), CheckError> {
        if let Some(want) = expected {
            if self.types[want.0].is_sum() {
                if let Some((index, _)) = self.find_case_in_type(want, name) {
                    return self.check_constructor(want, index, args, span, Some(want));
                }
            }
        }
        let candidates = self
            .types
            .iter()
            .enumerate()
            .skip(5)
            .filter_map(|(id, def)| {
                if matches!(def.kind, TTypeKind::Enum(_)) {
                    def.cases()
                        .iter()
                        .position(|case| case.name == name)
                        .map(|index| (Ty(id), index))
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        match candidates.as_slice() {
            [(ty, index)] => self.check_constructor(*ty, *index, args, span, expected),
            [] => Err(self.unknown_case(name, span)),
            _ => Err(CheckError {
                span,
                message: format!(
                    "case '{}' belongs to more than one enum; qualify it with the enum name",
                    name
                ),
            }),
        }
    }

    fn check_builtin_constructor(
        &mut self,
        name: &str,
        args: &[Expr],
        span: Span,
        expected: Option<Ty>,
    ) -> Result<Option<(TExprKind, Ty)>, CheckError> {
        match name {
            "some" => {
                if args.len() != 1 {
                    return Err(CheckError {
                        span,
                        message: format!("some takes one value, but got {}", args.len()),
                    });
                }
                let expected_inner = expected.and_then(|ty| match self.types[ty.0].kind {
                    TTypeKind::Option(inner) => Some(inner),
                    _ => None,
                });
                if expected.is_some() && expected_inner.is_none() {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "some constructs Option<T>, but the expected type is {}",
                            self.type_name(expected.unwrap())
                        ),
                    });
                }
                let value = self.check_expr(&args[0], expected_inner)?;
                let ty = expected.unwrap_or_else(|| self.option_type(value.ty, span));
                Ok(Some((
                    TExprKind::Construct {
                        case_index: 0,
                        args: vec![value],
                    },
                    ty,
                )))
            }
            "none" => {
                if !args.is_empty() {
                    return Err(CheckError {
                        span,
                        message: "none takes no payload".to_owned(),
                    });
                }
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Option(_)))
                else {
                    return Err(CheckError { span, message: "cannot infer the type of 'none'; add an Option<T> type annotation or expected type".to_owned() });
                };
                Ok(Some((
                    TExprKind::Construct {
                        case_index: 1,
                        args: Vec::new(),
                    },
                    ty,
                )))
            }
            "ok" | "err" => {
                if args.len() != 1 {
                    return Err(CheckError {
                        span,
                        message: format!("{} takes one value, but got {}", name, args.len()),
                    });
                }
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Result(..)))
                else {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "cannot infer the missing type parameter for '{}'; add a Result<T, E> expected type",
                            name
                        ),
                    });
                };
                let index = if name == "ok" { 0 } else { 1 };
                let case = self.case_def(ty, index);
                let value = self.check_expr(&args[0], Some(case.payload[0]))?;
                Ok(Some((
                    TExprKind::Construct {
                        case_index: index,
                        args: vec![value],
                    },
                    ty,
                )))
            }
            _ => Ok(None),
        }
    }

    fn check_method_call(
        &mut self,
        receiver: &Expr,
        name: &str,
        method_span: Span,
        args: &[Expr],
        expected: Option<Ty>,
        span: Span,
    ) -> Result<(TExprKind, Ty), CheckError> {
        if !args.is_empty() {
            let receiver_ty = self.natural_expr_type(receiver).unwrap_or(Ty::Unit);
            return Err(CheckError {
                span: method_span,
                message: format!(
                    "method '{}.{}' takes no arguments",
                    self.type_name(receiver_ty),
                    name
                ),
            });
        }
        let typed = self.check_expr(receiver, None)?;
        let (kind, result) = match (self.types[typed.ty.0].kind.clone(), name) {
            (TTypeKind::Option(_), "is_none") => (MethodKind::IsNone, Ty::Bool),
            (TTypeKind::Option(_), "is_some") => (MethodKind::IsSome, Ty::Bool),
            (TTypeKind::Option(value), "unwrap") => (MethodKind::UnwrapOption, value),
            (TTypeKind::Result(_, _), "is_ok") => (MethodKind::IsOk, Ty::Bool),
            (TTypeKind::Result(_, _), "is_err") => (MethodKind::IsErr, Ty::Bool),
            (TTypeKind::Result(ok, _err), "ok") => {
                (MethodKind::ResultOk, self.option_type(ok, method_span))
            }
            (TTypeKind::Result(ok, _), "unwrap") => (MethodKind::UnwrapResult, ok),
            (kind, _) => {
                let available = match kind {
                    TTypeKind::Option(_) => "is_none(), is_some(), and unwrap()",
                    TTypeKind::Result(..) => "ok(), is_ok(), is_err(), and unwrap()",
                    _ => "no methods",
                };
                return Err(CheckError {
                    span: method_span,
                    message: format!(
                        "no method '{}' on {}; available methods: {}",
                        name,
                        self.type_name(typed.ty),
                        available
                    ),
                });
            }
        };
        if let Some(want) = expected {
            self.type_mismatch(result, want, span)?;
        }
        Ok((
            TExprKind::Method {
                kind,
                receiver: Box::new(typed),
            },
            result,
        ))
    }

    fn check_expr(&mut self, expr: &Expr, expected: Option<Ty>) -> Result<TExpr, CheckError> {
        let (kind, ty) = match &expr.kind {
            ExprKind::Unit => {
                if let Some(want) = expected {
                    self.type_mismatch(Ty::Unit, want, expr.span)?;
                }
                (TExprKind::Unit, Ty::Unit)
            }
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
                            self.type_name(ty)
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
                } else if let Some(want) = expected {
                    if self.types[want.0].is_sum() {
                        if let Some((index, _case)) = self.find_case_in_type(want, name) {
                            let built =
                                self.check_constructor(want, index, &[], expr.span, Some(want))?;
                            return self.finish_expr(expr, built, expected);
                        }
                    }
                    if name == "none" {
                        let built = self
                            .check_builtin_constructor(name, &[], expr.span, expected)?
                            .unwrap();
                        return self.finish_expr(expr, built, expected);
                    }
                    return Err(self.unknown_local(name, expr.span));
                } else {
                    if name == "none" {
                        return Err(CheckError { span: expr.span, message: "cannot infer the type of 'none'; add an Option<T> type annotation or expected type".to_owned() });
                    }
                    let cases = self
                        .types
                        .iter()
                        .enumerate()
                        .skip(5)
                        .filter_map(|(id, def)| {
                            if matches!(def.kind, TTypeKind::Enum(_)) {
                                def.cases().iter().position(|case| case.name == *name).map(
                                    |index| (Ty(id), index, def.cases()[index].payload.is_empty()),
                                )
                            } else {
                                None
                            }
                        })
                        .collect::<Vec<_>>();
                    match cases.as_slice() {
                        [(ty, index, _)] => {
                            self.check_constructor(*ty, *index, &[], expr.span, None)?
                        }
                        [] => return Err(self.unknown_local(name, expr.span)),
                        _ => {
                            return Err(CheckError {
                                span: expr.span,
                                message: format!(
                                    "case '{}' belongs to more than one enum; qualify it with the enum name",
                                    name
                                ),
                            });
                        }
                    }
                }
            }
            ExprKind::Call {
                name,
                call_span,
                args,
            } => {
                if matches!(name.as_str(), "some" | "none" | "ok" | "err") {
                    self.check_builtin_constructor(name, args, *call_span, expected)?
                        .unwrap()
                } else if expected.is_some_and(|want| {
                    self.types[want.0].is_sum() && self.find_case_in_type(want, name).is_some()
                }) {
                    let want = expected.unwrap();
                    let index = self.find_case_in_type(want, name).unwrap().0;
                    self.check_constructor(want, index, args, *call_span, Some(want))?
                } else if self.types.iter().skip(5).any(|ty| {
                    matches!(ty.kind, TTypeKind::Enum(_))
                        && ty.cases().iter().any(|case| case.name == *name)
                }) {
                    self.check_unqualified_constructor(name, args, *call_span, expected)?
                } else if name == "print" {
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
                    if !matches!(arg.ty, Ty::Int | Ty::Long | Ty::Bool)
                        && !self.types[arg.ty.0].is_sum()
                    {
                        return Err(CheckError {
                            span: args[0].span,
                            message: "print supports int, long, bool, and enum values".to_owned(),
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
            ExprKind::QualifiedCase {
                enum_name,
                case_name,
                case_span,
                args,
            } => {
                let Some(ty) = self.enum_ids.get(enum_name).copied() else {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!("unknown enum '{}'; declare it with enum", enum_name),
                    });
                };
                let Some((index, _)) = self.find_case_in_type(ty, case_name) else {
                    return Err(self.unknown_case(case_name, *case_span));
                };
                self.check_constructor(ty, index, args, *case_span, expected)?
            }
            ExprKind::MethodCall {
                receiver,
                name,
                method_span,
                args,
            } => self.check_method_call(receiver, name, *method_span, args, expected, expr.span)?,
            ExprKind::OptionalCall {
                receiver,
                name,
                method_span,
                args,
            } => {
                let typed_receiver = self.check_expr(receiver, None)?;
                let inner = match self.types[typed_receiver.ty.0].kind {
                    TTypeKind::Option(inner) => inner,
                    TTypeKind::Result(_, _) => return Err(CheckError {
                        span: *method_span,
                        message:
                            "optional chaining requires Option; convert a Result with .ok() first"
                                .to_owned(),
                    }),
                    _ => {
                        return Err(CheckError {
                            span: *method_span,
                            message: format!(
                                "optional chaining requires Option<T>, found {}",
                                self.type_name(typed_receiver.ty)
                            ),
                        });
                    }
                };
                let Some(signature) = self.signatures.get(name).cloned() else {
                    return Err(self.unknown_function(name, *method_span));
                };
                if signature.params.len() != args.len() + 1 {
                    return Err(CheckError {
                        span: *method_span,
                        message: format!(
                            "optional call '{}()' takes the receiver plus {} argument(s), but got {}",
                            name,
                            signature.params.len().saturating_sub(1),
                            args.len()
                        ),
                    });
                }
                self.type_mismatch(inner, signature.params[0], receiver.span)?;
                let mut typed_args = Vec::new();
                for (arg, ty) in args.iter().zip(signature.params.iter().copied().skip(1)) {
                    typed_args.push(self.check_expr(arg, Some(ty))?);
                }
                let (result_ty, wraps_result) =
                    if matches!(self.types[signature.result.0].kind, TTypeKind::Option(_)) {
                        (signature.result, false)
                    } else {
                        (self.option_type(signature.result, expr.span), true)
                    };
                if let Some(want) = expected {
                    self.type_mismatch(result_ty, want, expr.span)?;
                }
                self.edges.push(Edge {
                    from: self.current_function,
                    to: signature.id,
                    span: *method_span,
                });
                (
                    TExprKind::OptionalCall {
                        receiver: Box::new(typed_receiver),
                        function_id: signature.id,
                        args: typed_args,
                        wraps_result,
                    },
                    result_ty,
                )
            }
            ExprKind::Try(value) => {
                if self.current_is_test {
                    return Err(CheckError {
                        span: expr.span,
                        message:
                            "a test cannot use '?'; let the test finish so all expectations run"
                                .to_owned(),
                    });
                }
                let typed = self.check_expr(value, None)?;
                let (success_ty, error_ty) = match self.types[typed.ty.0].kind {
                    TTypeKind::Option(inner) => {
                        if !matches!(self.types[self.current_return.0].kind, TTypeKind::Option(_)) {
                            return Err(CheckError { span: expr.span, message: "'?' on Option requires the enclosing function to return Option; return an Option or use match".to_owned() });
                        }
                        (inner, None)
                    }
                    TTypeKind::Result(ok, err) => {
                        let Some((_, return_err)) = (match self.types[self.current_return.0].kind {
                            TTypeKind::Result(a, b) => Some((a, b)),
                            _ => None,
                        }) else {
                            return Err(CheckError { span: expr.span, message: "'?' on Result requires the enclosing function to return Result; return a Result or use match".to_owned() });
                        };
                        if err != return_err {
                            return Err(CheckError {
                                span: expr.span,
                                message: format!(
                                    "'?' error type {} does not match enclosing error type {}; convert it explicitly or use match",
                                    self.type_name(err),
                                    self.type_name(return_err)
                                ),
                            });
                        }
                        (ok, Some(err))
                    }
                    _ => {
                        return Err(CheckError {
                            span: expr.span,
                            message: format!(
                                "'?' requires Option or Result, found {}",
                                self.type_name(typed.ty)
                            ),
                        });
                    }
                };
                if let Some(want) = expected {
                    self.type_mismatch(success_ty, want, expr.span)?;
                }
                (
                    TExprKind::Try {
                        value: Box::new(typed),
                        success_ty,
                        error_ty,
                        propagated_ty: self.current_return,
                    },
                    success_ty,
                )
            }
            ExprKind::Return(value) => {
                if self.current_is_test {
                    return Err(CheckError {
                        span: expr.span,
                        message:
                            "a test cannot return; let the test finish so all expectations run"
                                .to_owned(),
                    });
                }
                let typed = match value {
                    Some(value) => {
                        if self.current_return == Ty::Unit {
                            return Err(CheckError {
                                span: value.span,
                                message: "this function returns (); remove the value from 'return'"
                                    .to_owned(),
                            });
                        }
                        Some(Box::new(self.check_expr(value, Some(self.current_return))?))
                    }
                    None if self.current_return == Ty::Unit => None,
                    None => {
                        return Err(CheckError {
                            span: expr.span,
                            message: format!(
                                "this function must return {}; add a value after 'return'",
                                self.type_name(self.current_return)
                            ),
                        });
                    }
                };
                (TExprKind::Return(typed), Ty::Never)
            }
            ExprKind::LoopExit(is_break) => {
                if self.loop_depth == 0 {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!(
                            "'{}' is only valid inside a loop",
                            if *is_break { "break" } else { "continue" }
                        ),
                    });
                }
                (TExprKind::LoopExit(*is_break), Ty::Never)
            }
            ExprKind::Match { scrutinee, arms } => {
                self.check_match(scrutinee, arms, expected, expr.span)?
            }
            ExprKind::ToLong { value, method_span } => {
                let typed = self.check_expr(value, None)?;
                if typed.ty != Ty::Int {
                    return Err(CheckError {
                        span: *method_span,
                        message: format!(
                            "no method 'to_long' on {}; 'to_long' is available on int",
                            self.type_name(typed.ty)
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
                let target = self.parse_type(ty)?;
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
                            self.type_name(source.ty),
                            self.type_name(target)
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

    fn finish_expr(
        &self,
        expr: &Expr,
        (kind, ty): (TExprKind, Ty),
        expected: Option<Ty>,
    ) -> Result<TExpr, CheckError> {
        if let Some(want) = expected {
            self.type_mismatch(ty, want, expr.span)?;
        }
        Ok(TExpr {
            kind,
            ty,
            span: expr.span,
        })
    }

    fn check_match(
        &mut self,
        scrutinee: &Expr,
        arms: &[MatchArm],
        expected: Option<Ty>,
        span: Span,
    ) -> Result<(TExprKind, Ty), CheckError> {
        let scrutinee = self.check_expr(scrutinee, None)?;
        let sum = self.types[scrutinee.ty.0].is_sum();
        if !sum && !matches!(scrutinee.ty, Ty::Int | Ty::Long | Ty::Bool) {
            return Err(CheckError {
                span,
                message: format!(
                    "match requires an enum, Option, Result, int, long, or bool; found {}",
                    self.type_name(scrutinee.ty)
                ),
            });
        }
        let mut covered_cases = Vec::<usize>::new();
        let mut covered_ints = Vec::<i128>::new();
        let mut covered_bools = Vec::<bool>::new();
        let mut has_wildcard = false;
        let mut typed_arms = Vec::new();
        let mut reachable_ty = None;

        for arm in arms {
            let (typed_pattern, binding_specs, is_wildcard) = match &arm.pattern {
                Pattern::Wildcard => {
                    let already_total = match &self.types[scrutinee.ty.0].kind {
                        TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
                            covered_cases.len() == self.types[scrutinee.ty.0].cases().len()
                        }
                        TTypeKind::Bool => covered_bools.len() == 2,
                        TTypeKind::Int | TTypeKind::Long => false,
                        _ => false,
                    };
                    if has_wildcard || already_total {
                        return Err(CheckError {
                            span: arm.span,
                            message:
                                "unreachable match arm; previous patterns already cover this value"
                                    .to_owned(),
                        });
                    }
                    has_wildcard = true;
                    (TPattern::Wildcard, Vec::new(), true)
                }
                Pattern::Integer(literal) => {
                    if !matches!(scrutinee.ty, Ty::Int | Ty::Long) {
                        return Err(CheckError {
                            span: literal.span,
                            message: "integer patterns require an int or long match value"
                                .to_owned(),
                        });
                    }
                    if has_wildcard {
                        return Err(CheckError {
                            span: arm.span,
                            message: "unreachable match arm after '_'".to_owned(),
                        });
                    }
                    let typed = self.check_expr(literal, Some(scrutinee.ty))?;
                    let TExprKind::Integer(value) = typed.kind else {
                        unreachable!()
                    };
                    if covered_ints.contains(&value) {
                        return Err(CheckError {
                            span: arm.span,
                            message: format!(
                                "unreachable duplicate pattern '{}'; remove this arm",
                                value
                            ),
                        });
                    }
                    covered_ints.push(value);
                    (TPattern::Integer(value), Vec::new(), false)
                }
                Pattern::Bool(value, pattern_span) => {
                    if scrutinee.ty != Ty::Bool {
                        return Err(CheckError {
                            span: *pattern_span,
                            message: "bool patterns require a bool match value".to_owned(),
                        });
                    }
                    if has_wildcard || covered_bools.contains(value) {
                        return Err(CheckError {
                            span: arm.span,
                            message: format!(
                                "unreachable duplicate pattern '{}'; remove this arm",
                                value
                            ),
                        });
                    }
                    covered_bools.push(*value);
                    (TPattern::Bool(*value), Vec::new(), false)
                }
                Pattern::Case {
                    enum_name,
                    name,
                    name_span,
                    bindings,
                } => {
                    if !sum {
                        return Err(CheckError {
                            span: *name_span,
                            message:
                                "enum case patterns require an enum, Option, or Result match value"
                                    .to_owned(),
                        });
                    }
                    if has_wildcard {
                        return Err(CheckError {
                            span: arm.span,
                            message: "unreachable match arm after '_'".to_owned(),
                        });
                    }
                    if let Some(qualifier) = enum_name {
                        let qualified_ty = if let Some(ty) = self.enum_ids.get(qualifier) {
                            Some(*ty)
                        } else if qualifier == "Option"
                            && matches!(self.types[scrutinee.ty.0].kind, TTypeKind::Option(_))
                        {
                            Some(scrutinee.ty)
                        } else if qualifier == "Result"
                            && matches!(self.types[scrutinee.ty.0].kind, TTypeKind::Result(..))
                        {
                            Some(scrutinee.ty)
                        } else {
                            None
                        };
                        if qualified_ty != Some(scrutinee.ty) {
                            return Err(CheckError {
                                span: *name_span,
                                message: format!(
                                    "pattern '{}.{}' does not match {}",
                                    qualifier,
                                    name,
                                    self.type_name(scrutinee.ty)
                                ),
                            });
                        }
                    }
                    let Some((case_index, case)) = self.find_case_in_type(scrutinee.ty, name)
                    else {
                        return Err(self.unknown_case(name, *name_span));
                    };
                    if bindings.len() != case.payload.len() {
                        return Err(CheckError {
                            span: *name_span,
                            message: format!(
                                "case '{}.{}' has {} payload part(s), but this pattern names {}",
                                self.type_name(scrutinee.ty),
                                case.name,
                                case.payload.len(),
                                bindings.len()
                            ),
                        });
                    }
                    if covered_cases.contains(&case_index) {
                        return Err(CheckError {
                            span: arm.span,
                            message: format!(
                                "unreachable duplicate pattern '{}.{}'; remove this arm",
                                self.type_name(scrutinee.ty),
                                case.name
                            ),
                        });
                    }
                    covered_cases.push(case_index);
                    (
                        TPattern::Case {
                            ty: scrutinee.ty,
                            case_index,
                            bindings: vec![None; case.payload.len()],
                        },
                        case.payload
                            .into_iter()
                            .zip(bindings.iter())
                            .map(|(ty, binding)| (binding.clone(), ty))
                            .collect::<Vec<_>>(),
                        false,
                    )
                }
            };

            self.locals.push(HashMap::new());
            self.scope_ids.push(self.next_scope);
            self.next_scope += 1;
            let mut ids = Vec::new();
            for (binding, ty) in binding_specs {
                if let Some((name, name_span)) = binding {
                    let declared = self.declare(&name, ty, false, name_span, false)?;
                    ids.push(Some(declared.id));
                } else {
                    ids.push(None);
                }
            }
            let typed_body = self.check_block(&arm.body, false, expected)?;
            self.locals.pop();
            self.scope_ids.pop();
            let pattern = match typed_pattern {
                TPattern::Case { ty, case_index, .. } => TPattern::Case {
                    ty,
                    case_index,
                    bindings: ids,
                },
                other => other,
            };
            let arm_ty = block_value_ty(&typed_body);
            if arm_ty != Ty::Never {
                if let Some(previous) = reachable_ty {
                    if previous != arm_ty {
                        return Err(CheckError {
                            span: arm.span,
                            message: format!(
                                "match arms have different types: {} and {}; make reachable arms return the same type",
                                self.type_name(previous),
                                self.type_name(arm_ty)
                            ),
                        });
                    }
                } else {
                    reachable_ty = Some(arm_ty);
                }
            }
            let _ = is_wildcard;
            typed_arms.push(TMatchArm {
                pattern,
                body: typed_body,
            });
        }

        if !has_wildcard {
            match &self.types[scrutinee.ty.0].kind {
                TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
                    let missing = self.types[scrutinee.ty.0]
                        .cases()
                        .iter()
                        .enumerate()
                        .filter(|(i, _)| !covered_cases.contains(i))
                        .map(|(_, c)| format!("{}.{}", self.type_name(scrutinee.ty), c.name))
                        .collect::<Vec<_>>();
                    if !missing.is_empty() {
                        return Err(CheckError {
                            span,
                            message: format!(
                                "non-exhaustive match; missing {}",
                                missing.join(", ")
                            ),
                        });
                    }
                }
                TTypeKind::Bool if covered_bools.len() != 2 => {
                    let missing = [true, false]
                        .iter()
                        .filter(|b| !covered_bools.contains(b))
                        .map(|b| b.to_string())
                        .collect::<Vec<_>>();
                    return Err(CheckError {
                        span,
                        message: format!(
                            "non-exhaustive bool match; missing {}",
                            missing.join(" and ")
                        ),
                    });
                }
                TTypeKind::Int | TTypeKind::Long => {
                    return Err(CheckError {
                        span,
                        message: "integer matches need a '_' catch-all arm".to_owned(),
                    });
                }
                _ => {}
            }
        }
        let result_ty = reachable_ty.unwrap_or(Ty::Never);
        if let Some(want) = expected {
            self.type_mismatch(result_ty, want, span)?;
        }
        Ok((
            TExprKind::Match {
                scrutinee: Box::new(scrutinee),
                arms: typed_arms,
            },
            result_ty,
        ))
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
        if op == BinaryOp::Coalesce {
            let left_expected = if let Some(want) = expected {
                Some(self.option_type(want, span))
            } else {
                None
            };
            let left = self.check_expr(left, left_expected)?;
            let value_ty =
                match self.types[left.ty.0].kind.clone() {
                    TTypeKind::Option(value) => value,
                    TTypeKind::Result(_, _) => return Err(CheckError {
                        span,
                        message:
                            "'??' works on Option only; use match or convert the Result with .ok()"
                                .to_owned(),
                    }),
                    _ => {
                        return Err(CheckError {
                            span,
                            message: format!(
                                "'??' requires Option<T>, found {}",
                                self.type_name(left.ty)
                            ),
                        });
                    }
                };
            let fallback = self.check_expr(right, Some(value_ty))?;
            if fallback.ty != Ty::Never {
                self.type_mismatch(fallback.ty, value_ty, right.span)?;
            }
            return Ok((
                TExprKind::Coalesce {
                    option: Box::new(left),
                    fallback: Box::new(fallback),
                },
                value_ty,
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
                    message: "equality requires values other than ()".to_owned(),
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
            let right_expected = if self.types[l.ty.0].is_sum() {
                Some(l.ty)
            } else {
                None
            };
            let r = self.check_expr(right, right_expected)?;
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
                        self.type_name(then_ty),
                        self.type_name(else_ty)
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
                    self.type_name(expected),
                    self.type_name(actual),
                    self.type_name(expected)
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
                self.type_name(left),
                self.type_name(right),
                self.type_name(right),
                self.type_name(left)
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
        BinaryOp::Coalesce => "??",
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
