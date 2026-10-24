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
    params: Vec<ParamSignature>,
    result: Ty,
}

#[derive(Clone, Copy)]
struct ParamSignature {
    ty: Ty,
    mode: ParamMode,
}

#[derive(Clone)]
struct Binding {
    id: usize,
    name: String,
    ty: Ty,
    mutable: bool,
    mode: ParamMode,
    span: Span,
    loop_counter: bool,
}

#[derive(Clone, Copy)]
struct Edge {
    from: usize,
    to: usize,
    span: Span,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct CollectionCountKey {
    root: usize,
    fields: Vec<usize>,
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
    type_ids: HashMap<String, Ty>,
    preferred_type_names: HashMap<Ty, String>,
    struct_decls: HashMap<Ty, StructDecl>,
    refinement_ids: HashMap<(Ty, i128, i128, RefinePolicy), Ty>,
    generic_ids: HashMap<(u8, Ty, Ty), Ty>,
    collection_ids: HashMap<(u8, Ty, usize), Ty>,
    ast_functions: Vec<Function>,
    ast_tests: Vec<Test>,
    ast_constants: Vec<ConstDecl>,
    constant_ids: HashMap<String, usize>,
    constant_types: Vec<Ty>,
    checking_constant: bool,
    edges: Vec<Edge>,
    locals: Vec<HashMap<String, Binding>>,
    scope_ids: Vec<usize>,
    next_scope: usize,
    next_local: usize,
    current_function: usize,
    current_return: Ty,
    current_is_test: bool,
    loop_depth: usize,
    facts: HashMap<(usize, Vec<usize>), (i128, i128)>,
    loop_writes: Vec<std::collections::HashSet<usize>>,
    active_views: Vec<TPlace>,
    view_bindings: HashMap<usize, TPlace>,
    collection_counts: HashMap<CollectionCountKey, usize>,
    loop_push_proofs: Vec<std::collections::HashSet<CollectionCountKey>>,
}

impl Checker {
    fn new(programs: Vec<Program>, files: Vec<String>, require_main: bool) -> Self {
        let mut checker = Self {
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
            type_ids: HashMap::new(),
            preferred_type_names: HashMap::new(),
            struct_decls: HashMap::new(),
            refinement_ids: HashMap::new(),
            generic_ids: HashMap::new(),
            collection_ids: HashMap::new(),
            ast_functions: Vec::new(),
            ast_tests: Vec::new(),
            ast_constants: Vec::new(),
            constant_ids: HashMap::new(),
            constant_types: Vec::new(),
            checking_constant: false,
            edges: Vec::new(),
            locals: Vec::new(),
            scope_ids: Vec::new(),
            next_scope: 0,
            next_local: 0,
            current_function: 0,
            current_return: Ty::Unit,
            current_is_test: false,
            loop_depth: 0,
            facts: HashMap::new(),
            loop_writes: Vec::new(),
            active_views: Vec::new(),
            view_bindings: HashMap::new(),
            collection_counts: HashMap::new(),
            loop_push_proofs: Vec::new(),
        };
        let full_ty = Ty(checker.types.len());
        checker.types.push(TType {
            name: "Full".to_owned(),
            kind: TTypeKind::Enum(vec![TCase {
                name: "Full".to_owned(),
                payload: Vec::new(),
                span: Span::default(),
            }]),
            span: Span::default(),
        });
        checker.type_ids.insert("Full".to_owned(), full_ty);
        checker
    }

    fn run(mut self) -> Result<TProgram, CheckError> {
        self.register_type_names()?;
        self.fill_type_aliases()?;
        self.fill_enum_cases()?;
        self.fill_struct_fields()?;
        self.check_recursive_value_types()?;
        self.check_all_type_sizes()?;
        for program in self.programs.clone() {
            for constant in program.constants {
                if self.constant_ids.contains_key(&constant.name) {
                    return Err(CheckError {
                        span: constant.span,
                        message: format!("constant '{}' is declared more than once", constant.name),
                    });
                }
                let id = self.ast_constants.len();
                let ty = self.parse_type(&constant.ty)?;
                self.constant_ids.insert(constant.name.clone(), id);
                self.constant_types.push(ty);
                self.ast_constants.push(constant);
            }
        }
        let mut test_names = HashMap::<String, Span>::new();
        for p in self.programs.clone() {
            for function in p.functions {
                let id = self.ast_functions.len();
                if matches!(function.name.as_str(), "print" | "min" | "max") {
                    return Err(CheckError {
                        span: function.span,
                        message: format!(
                            "'{}' is a built-in function name and cannot be redeclared",
                            function.name
                        )
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
                    .map(|p| {
                        Ok(ParamSignature {
                            ty: self.parse_type(&p.ty)?,
                            mode: p.mode,
                        })
                    })
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
        self.check_large_local_types(&functions)?;
        let mut constant_exprs = Vec::with_capacity(self.ast_constants.len());
        for id in 0..self.ast_constants.len() {
            constant_exprs.push(self.check_constant_expr(id)?);
        }
        self.check_recursion()?;
        let mut call_graph = vec![Vec::new(); functions.len()];
        for edge in self.edges {
            call_graph[edge.from].push(TCallEdge {
                target: edge.to,
                span: edge.span,
            });
        }
        let mut typed = TProgram {
            functions,
            tests,
            constants: Vec::new(),
            files: self.files,
            call_graph,
            types: self.types,
        };
        typed.constants = crate::const_eval::evaluate_constants(
            &constant_exprs,
            &typed.functions,
            &typed.call_graph,
            &typed.types,
        )?;
        Ok(typed)
    }

    fn check_constant_expr(&mut self, id: usize) -> Result<TConstExpr, CheckError> {
        let declaration = self.ast_constants[id].clone();
        self.current_function = 0;
        self.current_return = self.constant_types[id];
        self.current_is_test = false;
        self.checking_constant = true;
        self.loop_depth = 0;
        self.facts.clear();
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.scope_ids.clear();
        self.scope_ids.push(0);
        self.next_scope = 1;
        let expr = self.check_store(&declaration.value, self.constant_types[id]);
        self.checking_constant = false;
        self.locals.clear();
        let expr = expr?;
        Ok(TConstExpr {
            id,
            name: declaration.name,
            ty: self.constant_types[id],
            expr,
            span: declaration.span,
        })
    }

    fn register_type_names(&mut self) -> Result<(), CheckError> {
        for program in &self.programs {
            for (name, span, kind) in program
                .enums
                .iter()
                .map(|d| (&d.name, d.span, TTypeKind::Enum(Vec::new())))
                .chain(
                    program
                        .structs
                        .iter()
                        .map(|d| (&d.name, d.span, TTypeKind::Struct(Vec::new()))),
                )
            {
                if matches!(
                    name.as_str(),
                    "int" | "long" | "bool" | "Option" | "Result" | "Full"
                ) || self.type_ids.contains_key(name)
                {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "type '{}' is declared more than once or shadows a built-in type",
                            name
                        ),
                    });
                }
                let ty = Ty(self.types.len());
                self.type_ids.insert(name.clone(), ty);
                self.types.push(TType {
                    name: name.clone(),
                    kind,
                    span,
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
            let ty = self.type_ids[&declaration.name];
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

    fn fill_struct_fields(&mut self) -> Result<(), CheckError> {
        let declarations = self
            .programs
            .iter()
            .flat_map(|p| p.structs.clone())
            .collect::<Vec<_>>();
        for declaration in declarations {
            let ty = self.type_ids[&declaration.name];
            let mut names = HashMap::<String, Span>::new();
            let mut fields = Vec::new();
            for field in &declaration.fields {
                if let Some(previous) = names.insert(field.name.clone(), field.span) {
                    return Err(CheckError {
                        span: field.span,
                        message: format!(
                            "field '{}' is declared twice (first on line {})",
                            field.name, previous.line
                        ),
                    });
                }
                fields.push(TField {
                    name: field.name.clone(),
                    ty: self.parse_type(&field.ty)?,
                });
                if fields
                    .last()
                    .is_some_and(|field| field.ty == Ty::Unit || field.ty == Ty::Never)
                {
                    return Err(CheckError { span: field.span, message: "a struct field must have a storable value type; use an enum unit case for ()".to_owned() });
                }
            }
            self.types[ty.0].kind = TTypeKind::Struct(fields);
            self.struct_decls.insert(ty, declaration);
        }
        Ok(())
    }

    fn fill_type_aliases(&mut self) -> Result<(), CheckError> {
        let declarations = self
            .programs
            .iter()
            .flat_map(|p| p.aliases.clone())
            .collect::<Vec<_>>();
        let mut pending = declarations;
        while !pending.is_empty() {
            let mut next = Vec::new();
            let mut progressed = false;
            for alias in pending {
                if matches!(
                    alias.name.as_str(),
                    "int" | "long" | "bool" | "Option" | "Result" | "Full"
                ) || self.type_ids.contains_key(&alias.name)
                {
                    return Err(CheckError {
                        span: alias.span,
                        message: format!(
                            "type '{}' is declared more than once or shadows a built-in type",
                            alias.name
                        ),
                    });
                }
                match self.parse_type(&alias.ty) {
                    Ok(ty) => {
                        self.preferred_type_names
                            .entry(ty)
                            .or_insert_with(|| alias.name.clone());
                        self.type_ids.insert(alias.name, ty);
                        progressed = true;
                    }
                    Err(error) if error.message.starts_with("unknown type '") => next.push(alias),
                    Err(error) => return Err(error),
                }
            }
            if !progressed {
                let alias = &next[0];
                return Err(CheckError {
                    span: alias.ty.span,
                    message: format!(
                        "unknown type in alias '{}'; declare the base type first",
                        alias.name
                    ),
                });
            }
            pending = next;
        }
        Ok(())
    }

    fn parse_type(&mut self, ty: &TypeAst) -> Result<Ty, CheckError> {
        let mut result = match ty.name.as_str() {
            "int" if ty.args.is_empty() && ty.const_args.is_empty() => {
                if let Some(range) = ty.range {
                    self.intern_refinement(Ty::Int, range, ty.policy, ty.span)?
                } else {
                    Ty::Int
                }
            }
            "long" if ty.args.is_empty() && ty.const_args.is_empty() => {
                if let Some(range) = ty.range {
                    self.intern_refinement(Ty::Long, range, ty.policy, ty.span)?
                } else {
                    Ty::Long
                }
            }
            "bool" if ty.args.is_empty() && ty.const_args.is_empty() && ty.range.is_none() => {
                Ty::Bool
            }
            "()" if ty.args.is_empty() && ty.const_args.is_empty() && ty.range.is_none() => {
                Ty::Unit
            }
            "Option" if ty.args.len() == 1 && ty.const_args.is_empty() && ty.range.is_none() => {
                let value = self.parse_type(&ty.args[0])?;
                self.intern_generic(
                    1,
                    value,
                    Ty::Unit,
                    format!("Option<{}>", self.type_name(value)),
                    ty.span,
                    TTypeKind::Option(value),
                )
            }
            "Result" if ty.args.len() == 2 && ty.const_args.is_empty() && ty.range.is_none() => {
                let ok = self.parse_type(&ty.args[0])?;
                let err = self.parse_type(&ty.args[1])?;
                self.intern_generic(
                    2,
                    ok,
                    err,
                    format!("Result<{}, {}>", self.type_name(ok), self.type_name(err)),
                    ty.span,
                    TTypeKind::Result(ok, err),
                )
            }
            "list" if ty.args.len() == 1 && ty.const_args.len() == 1 && ty.range.is_none() => {
                let element = self.parse_type(&ty.args[0])?;
                let capacity = self.capacity_value(&ty.const_args[0])?;
                if capacity < 0 {
                    return Err(CheckError {
                        span: ty.const_args[0].span,
                        message:
                            "list capacity cannot be negative; use zero or a positive constant"
                                .to_owned(),
                    });
                }
                if capacity > i64::MAX as i128 {
                    return Err(CheckError {
                        span: ty.const_args[0].span,
                        message: "collection size overflows long; reduce a capacity".to_owned(),
                    });
                }
                let capacity = usize::try_from(capacity).map_err(|_| CheckError {
                    span: ty.const_args[0].span,
                    message: "collection size overflows long; reduce a capacity".to_owned(),
                })?;
                self.intern_collection(
                    1,
                    element,
                    capacity,
                    format!("list<{}, {}>", self.type_name(element), capacity),
                    ty.span,
                )
            }
            "Option" | "Result" | "list" => {
                return Err(CheckError {
                    span: ty.span,
                    message: match ty.name.as_str() {
                        "list" => {
                            "list types use list<T, capacity>; the capacity must be a constant"
                                .to_owned()
                        }
                        "Option" => {
                            "type 'Option' has the wrong number of parameters; use Option<T>"
                                .to_owned()
                        }
                        _ => "type 'Result' has the wrong number of parameters; use Result<T, E>"
                            .to_owned(),
                    },
                });
            }
            _ if !ty.args.is_empty() || !ty.const_args.is_empty() || ty.range.is_some() => {
                return Err(CheckError {
                    span: ty.span,
                    message: format!("'{}' is not a generic or range-refined type", ty.name),
                });
            }
            _ => *self.type_ids.get(&ty.name).ok_or_else(|| {
                let mut names = self.type_ids.keys().cloned().collect::<Vec<_>>();
                names.extend([
                    "int".to_owned(),
                    "long".to_owned(),
                    "bool".to_owned(),
                    "Option".to_owned(),
                    "Result".to_owned(),
                    "list".to_owned(),
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
            })?,
        };
        for cap_expr in &ty.array_caps {
            let capacity = self.capacity_value(cap_expr)?;
            if capacity < 0 {
                return Err(CheckError {
                    span: cap_expr.span,
                    message: "array capacity cannot be negative; use zero or a positive constant"
                        .to_owned(),
                });
            }
            if capacity > i64::MAX as i128 {
                return Err(CheckError {
                    span: cap_expr.span,
                    message: "collection size overflows long; reduce a capacity".to_owned(),
                });
            }
            let capacity = usize::try_from(capacity).map_err(|_| CheckError {
                span: cap_expr.span,
                message: "collection size overflows long; reduce a capacity".to_owned(),
            })?;
            result = self.intern_collection(
                0,
                result,
                capacity,
                format!("{}[{}]", self.type_name(result), capacity),
                cap_expr.span,
            );
        }
        let mut size_cache = vec![None; self.types.len()];
        let bytes = self.type_size_checked(result, &mut size_cache, ty.span)?;
        if bytes > i64::MAX as u128 {
            return Err(CheckError {
                span: ty.span,
                message:
                    "collection size overflows long; reduce a capacity or the nested element size"
                        .to_owned(),
            });
        }
        Ok(result)
    }

    fn intern_collection(
        &mut self,
        kind: u8,
        element: Ty,
        capacity: usize,
        name: String,
        span: Span,
    ) -> Ty {
        if let Some(ty) = self.collection_ids.get(&(kind, element, capacity)) {
            return *ty;
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name,
            kind: if kind == 0 {
                TTypeKind::Array { element, capacity }
            } else {
                TTypeKind::List { element, capacity }
            },
            span,
        });
        self.collection_ids.insert((kind, element, capacity), ty);
        ty
    }

    fn capacity_value(&self, expr: &Expr) -> Result<i128, CheckError> {
        fn eval(checker: &Checker, expr: &Expr, active: &mut Vec<String>) -> Option<i128> {
            match &expr.kind {
                ExprKind::Integer {
                    magnitude,
                    negative,
                    ..
                } => {
                    let value = i128::try_from(*magnitude).ok()?;
                    if *negative {
                        value.checked_neg()
                    } else {
                        Some(value)
                    }
                }
                ExprKind::Name(name) => {
                    if active.contains(name) {
                        return None;
                    }
                    let decl = checker
                        .programs
                        .iter()
                        .flat_map(|p| p.constants.iter())
                        .find(|c| c.name == *name)?;
                    active.push(name.clone());
                    let value = eval(checker, &decl.value, active);
                    active.pop();
                    value
                }
                ExprKind::Unary {
                    op: UnaryOp::Neg,
                    value,
                    ..
                } => eval(checker, value, active)?.checked_neg(),
                ExprKind::Binary {
                    op, left, right, ..
                } => {
                    let a = eval(checker, left, active)?;
                    let b = eval(checker, right, active)?;
                    match op {
                        BinaryOp::Add => a.checked_add(b),
                        BinaryOp::Sub => a.checked_sub(b),
                        BinaryOp::Mul => a.checked_mul(b),
                        BinaryOp::Div if b != 0 => a.checked_div(b),
                        BinaryOp::Rem if b != 0 => a.checked_rem(b),
                        _ => None,
                    }
                }
                _ => None,
            }
        }
        eval(self, expr, &mut Vec::new()).ok_or_else(|| CheckError {
            span: expr.span,
            message: "collection capacity must be a constant integer expression; use a literal or const value".to_owned(),
        })
    }

    fn type_size_checked(
        &self,
        ty: Ty,
        cache: &mut [Option<u128>],
        span: Span,
    ) -> Result<u128, CheckError> {
        if ty == Ty::Int {
            return Ok(4);
        }
        if ty == Ty::Long {
            return Ok(8);
        }
        if ty == Ty::Bool {
            return Ok(1);
        }
        if ty == Ty::Unit || ty == Ty::Never {
            return Ok(0);
        }
        if let Some(size) = cache.get(ty.0).and_then(|v| *v) {
            return Ok(size);
        }
        let checked_add = |left: u128, right: u128| {
            left.checked_add(right).ok_or_else(|| CheckError {
                span,
                message: "collection size overflows long; reduce a capacity".to_owned(),
            })
        };
        let checked_mul = |left: u128, right: u128| {
            left.checked_mul(right).ok_or_else(|| CheckError {
                span,
                message: "collection size overflows long; reduce a capacity".to_owned(),
            })
        };
        let size = match &self.types[ty.0].kind {
            TTypeKind::Refinement { base, .. } => self.type_size_checked(*base, cache, span)?,
            TTypeKind::Struct(fields) => {
                let mut size = 0u128;
                for field in fields {
                    size = checked_add(size, self.type_size_checked(field.ty, cache, span)?)?;
                }
                size
            }
            TTypeKind::Array { element, capacity } | TTypeKind::List { element, capacity } => {
                let lanes = match &self.types[element.0].kind {
                    TTypeKind::Struct(fields) => {
                        fields.iter().map(|field| field.ty).collect::<Vec<_>>()
                    }
                    _ => vec![*element],
                };
                let mut payload = 0u128;
                for lane in lanes {
                    payload = checked_add(
                        payload,
                        checked_mul(
                            self.type_size_checked(lane, cache, span)?,
                            *capacity as u128,
                        )?,
                    )?;
                }
                if matches!(self.types[ty.0].kind, TTypeKind::List { .. }) {
                    checked_add(8, payload)?
                } else {
                    payload
                }
            }
            TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
                let mut payload = 0u128;
                for case in self.types[ty.0].cases() {
                    let mut case_size = 0u128;
                    for field in case.payload {
                        case_size =
                            checked_add(case_size, self.type_size_checked(field, cache, span)?)?;
                    }
                    payload = payload.max(case_size);
                }
                checked_add(4, payload)?
                    .checked_add(3)
                    .ok_or_else(|| CheckError {
                        span,
                        message: "collection size overflows long; reduce a capacity".to_owned(),
                    })?
                    & !3
            }
            TTypeKind::Int
            | TTypeKind::Long
            | TTypeKind::Bool
            | TTypeKind::Unit
            | TTypeKind::Never => unreachable!(),
        };
        if let Some(slot) = cache.get_mut(ty.0) {
            *slot = Some(size);
        }
        Ok(size)
    }

    fn check_all_type_sizes(&self) -> Result<(), CheckError> {
        for (id, definition) in self.types.iter().enumerate().skip(5) {
            let mut cache = vec![None; self.types.len()];
            let size = self.type_size_checked(Ty(id), &mut cache, definition.span)?;
            if size > i64::MAX as u128 {
                return Err(CheckError { span: definition.span, message: "collection size overflows long; reduce a capacity or the nested element size".to_owned() });
            }
        }
        Ok(())
    }

    fn check_large_local_types(&self, functions: &[TFunction]) -> Result<(), CheckError> {
        const NATIVE_LOCAL_LIMIT: u128 = 65_536;
        fn check(checker: &Checker, ty: Ty, span: Span, label: &str) -> Result<(), CheckError> {
            let mut cache = vec![None; checker.types.len()];
            if checker.type_size_checked(ty, &mut cache, span)? > NATIVE_LOCAL_LIMIT {
                return Err(CheckError {
                    span,
                    message: format!(
                        "{} exceeds the temporary 64 KB native-stack limit; this value needs M3 data-stack lowering",
                        label
                    ),
                });
            }
            Ok(())
        }
        fn block(checker: &Checker, body: &TBlock) -> Result<(), CheckError> {
            for stmt in &body.statements {
                match &stmt.kind {
                    TStmtKind::Let { ty, name, .. } => {
                        check(checker, *ty, stmt.span, &format!("local '{}'", name))?
                    }
                    TStmtKind::If {
                        then_block,
                        else_block,
                        ..
                    } => {
                        block(checker, then_block)?;
                        if let Some(other) = else_block {
                            block(checker, other)?;
                        }
                    }
                    TStmtKind::For { body, .. }
                    | TStmtKind::ForEach { body, .. }
                    | TStmtKind::Block(body) => block(checker, body)?,
                    _ => {}
                }
            }
            Ok(())
        }
        for function in functions {
            for param in &function.params {
                check(
                    self,
                    param.ty,
                    param.span,
                    &format!("parameter '{}'", param.name),
                )?;
            }
            check(
                self,
                function.result,
                function.span,
                &format!("return value of '{}'", function.name),
            )?;
            block(self, &function.body)?;
        }
        Ok(())
    }

    fn intern_refinement(
        &mut self,
        base: Ty,
        range: TypeRangeAst,
        policy: RefinePolicy,
        span: Span,
    ) -> Result<Ty, CheckError> {
        let (base_min, base_max) = if base == Ty::Int {
            (i32::MIN as i128, i32::MAX as i128)
        } else if base == Ty::Long {
            (i64::MIN as i128, i64::MAX as i128)
        } else {
            return Err(CheckError {
                span: range.span,
                message: "range refinements can be declared on int or long only".to_owned(),
            });
        };
        let max = if range.inclusive {
            range.upper
        } else {
            range.upper.saturating_sub(1)
        };
        if range.lower > max {
            return Err(CheckError {
                span: range.span,
                message: "refinement range is empty or reversed; choose bounds that include at least one value".to_owned(),
            });
        }
        if range.lower < base_min || range.lower > base_max || max < base_min || max > base_max {
            return Err(CheckError {
                span: range.span,
                message: format!(
                    "refinement bounds must fit {}; use {} for a wider range",
                    self.type_name(base),
                    if base == Ty::Int {
                        "long"
                    } else {
                        "a narrower range"
                    }
                ),
            });
        }
        let key = (base, range.lower, max, policy);
        if let Some(ty) = self.refinement_ids.get(&key) {
            return Ok(*ty);
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!("{} {}..={}", self.type_name(base), range.lower, max),
            kind: TTypeKind::Refinement {
                base,
                min: range.lower,
                max,
                policy,
            },
            span,
        });
        self.refinement_ids.insert(key, ty);
        Ok(ty)
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
        self.preferred_type_names
            .get(&ty)
            .cloned()
            .unwrap_or_else(|| {
                self.types
                    .get(ty.0)
                    .map(|t| t.name.clone())
                    .unwrap_or_else(|| ty.name().to_owned())
            })
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
                TTypeKind::Struct(fields) => fields.iter().map(|field| field.ty).collect(),
                TTypeKind::Option(t) => vec![*t],
                TTypeKind::Result(a, b) => vec![*a, *b],
                TTypeKind::Array { element, .. } | TTypeKind::List { element, .. } => {
                    vec![*element]
                }
                TTypeKind::Refinement { .. } => Vec::new(),
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
        self.facts.clear();
        self.collection_counts.clear();
        self.loop_push_proofs.clear();
        self.active_views.clear();
        self.view_bindings.clear();
        self.loop_depth = 0;
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.next_scope = 1;
        self.scope_ids.clear();
        self.scope_ids.push(0);
        let mut params = Vec::new();
        for (i, param) in function.params.iter().enumerate() {
            let ty = signature.params[i].ty;
            let binding = self.declare_mode(
                &param.name,
                ty,
                param.mode == ParamMode::Write,
                param.mode,
                param.span,
                false,
            )?;
            params.push(TParam {
                id: binding.id,
                name: binding.name,
                ty,
                mode: param.mode,
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
        self.facts.clear();
        self.collection_counts.clear();
        self.loop_push_proofs.clear();
        self.active_views.clear();
        self.view_bindings.clear();
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
            if expected == Some(Ty::Unit) {
                let typed = self.check_expr(expr, None)?;
                if let TExprKind::CollectionOp {
                    op: CollectionOp::Push | CollectionOp::Insert,
                    proven_success,
                    ..
                } = &typed.kind
                {
                    if !proven_success {
                        return Err(CheckError { span: expr.span, message: "this collection operation returns Result<(), Full>; handle it with match, '?', or unwrap(), or write 'discard' when dropping a full result is intended".to_owned() });
                    }
                    statements.push(TStmt {
                        kind: TStmtKind::Expr(typed),
                        span: expr.span,
                    });
                    None
                } else {
                    Some(Box::new(self.coerce_store(typed, Ty::Unit)?))
                }
            } else if let Some(target) = expected {
                Some(Box::new(self.check_store(expr, target)?))
            } else {
                Some(Box::new(self.check_expr(expr, None)?))
            }
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
                let typed_value = if let Some(target) = annotated {
                    self.check_store(value, target)?
                } else {
                    self.check_expr(value, None)?
                };
                if typed_value.ty == Ty::Unit || typed_value.ty == Ty::Never {
                    return Err(CheckError { span: value.span, message: "a binding needs a value; functions and if expressions used here must return int, long, or bool".to_owned() });
                }
                let ty = annotated.unwrap_or(typed_value.ty);
                let binding = self.declare(name, ty, *mutable, stmt.span, false)?;
                if let Some(range) = self.expr_range(&typed_value) {
                    self.facts.insert((binding.id, Vec::new()), range);
                }
                self.record_nested_facts(binding.id, &[], &typed_value);
                if matches!(self.types[ty.0].kind, TTypeKind::List { .. }) {
                    let key = CollectionCountKey {
                        root: binding.id,
                        fields: Vec::new(),
                    };
                    if matches!(&typed_value.kind, TExprKind::EmptyList) {
                        self.collection_counts.insert(key, 0);
                    } else {
                        self.collection_counts.remove(&key);
                    }
                }
                TStmtKind::Let {
                    id: binding.id,
                    name: name.clone(),
                    ty,
                    mutable: *mutable,
                    value: typed_value,
                }
            }
            StmtKind::Assign {
                target,
                op,
                operator_span,
                value,
            } => {
                let place = self.resolve_place(target)?;
                if !self.place_is_mutable(&place) {
                    let binding = self
                        .binding_by_id(place.root)
                        .expect("place binding is in scope");
                    return Err(CheckError {
                        span: stmt.span,
                        message: if binding.loop_counter {
                            format!(
                                "cannot assign to loop counter '{}'; loop counters are immutable",
                                binding.name
                            )
                        } else if binding.mode == ParamMode::Read
                            && binding.id < self.function_param_count()
                        {
                            format!(
                                "cannot assign to read parameter '{}'; pass it as 'write' to allow mutation",
                                binding.name
                            )
                        } else if place.path.is_empty() {
                            format!(
                                "cannot assign to immutable 'let' binding '{}'; declare it with 'var'",
                                binding.name
                            )
                        } else {
                            format!(
                                "cannot assign through immutable 'let' binding '{}'; declare it with 'var'",
                                binding.name
                            )
                        },
                    });
                }
                let target_place = self.canonical_place(&place);
                if self.active_views.iter().any(|view| {
                    let view = self.canonical_place(view);
                    places_overlap(&view, &target_place)
                        && !places_proven_prefix(&view, &target_place)
                }) {
                    return Err(CheckError {
                        span: stmt.span,
                        message:
                            "cannot replace or modify storage that contains a live collection view"
                                .to_owned(),
                    });
                }
                let (typed_value, assigned_range) = if *op == AssignOp::Set {
                    let stored = self.check_store(value, place.ty)?;
                    let range = self.expr_range(&stored);
                    (stored, range)
                } else {
                    let typed_value = self.check_expr(value, Some(self.base_type(place.ty)))?;
                    let bop = assign_binary(*op);
                    self.check_binary_types(
                        bop,
                        self.base_type(place.ty),
                        self.base_type(typed_value.ty),
                        *operator_span,
                    )?;
                    let lhs = self.typed_place_expr(&place, target.span);
                    let result = TExpr {
                        kind: TExprKind::Binary {
                            op: bop,
                            operator_span: *operator_span,
                            left: Box::new(lhs),
                            right: Box::new(typed_value.clone()),
                        },
                        ty: self.base_type(place.ty),
                        span: *operator_span,
                    };
                    let stored = self.coerce_store(result, place.ty)?;
                    let range = self.expr_range(&stored);
                    (typed_value, range)
                };
                if *op != AssignOp::Set {
                    let bop = assign_binary(*op);
                    self.check_binary_types(bop, place.ty, typed_value.ty, *operator_span)?;
                    if !self.is_numeric(place.ty) {
                        return Err(CheckError {
                            span: stmt.span,
                            message: format!(
                                "'{}=' requires int or long; '{}' is {}",
                                assign_spelling(*op),
                                target_name(target),
                                self.type_name(place.ty)
                            ),
                        });
                    }
                }
                let place_fields = place_field_path(&place);
                let nested_facts = place_fields.as_deref().map_or_else(Vec::new, |fields| {
                    self.nested_facts_for_value(fields, &typed_value)
                });
                self.invalidate_place(&place);
                if let Some(key) = self.collection_count_key(&place) {
                    if *op == AssignOp::Set
                        && matches!(self.types[place.ty.0].kind, TTypeKind::List { .. })
                        && matches!(&typed_value.kind, TExprKind::EmptyList)
                    {
                        self.collection_counts.insert(key, 0);
                    } else {
                        self.invalidate_collection_counts(&place);
                    }
                } else {
                    self.invalidate_collection_counts(&place);
                }
                let is_loop_written = self
                    .loop_writes
                    .iter()
                    .any(|writes| writes.contains(&place.root));
                if !is_loop_written {
                    if let Some(fields) = place_field_path(&place) {
                        if let Some(range) = self
                            .refinement(place.ty)
                            .map(|(_, lo, hi, _)| (lo, hi))
                            .or(assigned_range)
                        {
                            self.facts.insert((place.root, fields), range);
                        }
                    }
                    for (fields, range) in nested_facts {
                        self.facts.insert((place.root, fields), range);
                    }
                }
                let place_ty = place.ty;
                TStmtKind::Assign {
                    place,
                    ty: place_ty,
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
                        Some(self.check_store(expr, self.current_return)?)
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
                    let typed = self.check_expr(expr, None)?;
                    if let TExprKind::CollectionOp {
                        op: CollectionOp::Push | CollectionOp::Insert,
                        proven_success: false,
                        ..
                    } = typed.kind
                    {
                        return Err(CheckError { span: expr.span, message: "this collection operation returns Result<(), Full>; handle it with match, '?', or unwrap(), or write 'discard' when dropping a full result is intended".to_owned() });
                    }
                    TStmtKind::Expr(typed)
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
                let before_counts = self.collection_counts.clone();
                let iteration_bound =
                    self.max_loop_iterations(&typed_start, &typed_end, *inclusive);
                let loop_pushes = self.prepare_loop_push_proofs(body, iteration_bound);
                let before_loop = self.facts.clone();
                let mut loop_writes = std::collections::HashSet::new();
                self.collect_loop_writes(body, &mut loop_writes);
                self.facts
                    .retain(|(root, _), _| !loop_writes.contains(root));
                self.locals.push(HashMap::new());
                self.scope_ids.push(self.next_scope);
                self.next_scope += 1;
                let counter = self.declare(name, ty, false, stmt.span, true)?;
                let start_range = self
                    .expr_range(&typed_start)
                    .unwrap_or_else(|| integer_bounds(ty).unwrap());
                let end_range = self
                    .expr_range(&typed_end)
                    .unwrap_or_else(|| integer_bounds(ty).unwrap());
                let last = if *inclusive {
                    end_range.1
                } else {
                    end_range.1.saturating_sub(1)
                };
                self.facts
                    .insert((counter.id, Vec::new()), (start_range.0, last));
                self.loop_writes.push(loop_writes.clone());
                self.loop_depth += 1;
                let typed_body = self.check_block(body, true, None)?;
                let after_body_counts = self.collection_counts.clone();
                self.loop_depth -= 1;
                self.loop_writes.pop();
                self.finish_loop_push_proofs(
                    before_counts,
                    after_body_counts,
                    loop_pushes,
                    iteration_bound.unwrap_or(0),
                );
                self.locals.pop();
                self.scope_ids.pop();
                self.facts = before_loop;
                self.facts
                    .retain(|(root, _), _| !loop_writes.contains(root));
                TStmtKind::For {
                    id: counter.id,
                    ty,
                    start: typed_start,
                    end: typed_end,
                    inclusive: *inclusive,
                    body: typed_body,
                }
            }
            StmtKind::ForEach {
                name,
                index_name,
                collection,
                body,
            } => {
                let typed_collection = self.check_expr(collection, None)?;
                let (element, capacity, is_list) = match self.types[typed_collection.ty.0].kind {
                    TTypeKind::Array { element, capacity } => (element, capacity, false),
                    TTypeKind::List { element, capacity } => (element, capacity, true),
                    _ => {
                        return Err(CheckError {
                            span: collection.span,
                            message: format!(
                                "{} is not an array or list; collection loops need a fixed collection",
                                self.type_name(typed_collection.ty)
                            ),
                        });
                    }
                };
                let source = self.resolve_place(collection).map_err(|_| CheckError {
                    span: collection.span,
                    message: "collection iteration needs a local, parameter, or field place; bind the value to a local first".to_owned(),
                })?;
                let writable = self.place_is_mutable(&source);
                let before_counts = self.collection_counts.clone();
                let iterations = if is_list {
                    self.collection_count_key(&source)
                        .and_then(|key| self.collection_counts.get(&key).copied())
                        .unwrap_or(capacity)
                } else {
                    capacity
                };
                let loop_pushes = self.prepare_loop_push_proofs(body, Some(iterations));
                let before_loop = self.facts.clone();
                let mut loop_writes = std::collections::HashSet::new();
                self.collect_loop_writes(body, &mut loop_writes);
                self.facts
                    .retain(|(root, _), _| !loop_writes.contains(root));
                self.locals.push(HashMap::new());
                self.scope_ids.push(self.next_scope);
                self.next_scope += 1;
                let counter_id = self.next_local;
                self.next_local += 1;
                let binding = self.declare(name, element, writable, stmt.span, false)?;
                let index_id = if let Some(index_name) = index_name {
                    Some(
                        self.declare(index_name, Ty::Long, false, stmt.span, true)?
                            .id,
                    )
                } else {
                    None
                };
                let index_expr = TExpr {
                    kind: TExprKind::Local(index_id.unwrap_or(counter_id)),
                    ty: Ty::Long,
                    span: stmt.span,
                };
                let mut element_place = source.clone();
                element_place.path.push(TProjection::Index {
                    index: index_expr,
                    constant: None,
                    capacity,
                    is_list,
                    proven: true,
                });
                element_place.ty = element;
                self.view_bindings.insert(binding.id, element_place.clone());
                self.active_views.push(element_place);
                self.loop_depth += 1;
                let typed_body = self.check_block(body, true, None)?;
                let after_body_counts = self.collection_counts.clone();
                self.loop_depth -= 1;
                self.active_views.pop();
                self.view_bindings.remove(&binding.id);
                self.finish_loop_push_proofs(
                    before_counts,
                    after_body_counts,
                    loop_pushes,
                    iterations,
                );
                self.locals.pop();
                self.scope_ids.pop();
                self.facts = before_loop;
                self.facts
                    .retain(|(root, _), _| !loop_writes.contains(root));
                let _ = capacity;
                TStmtKind::ForEach {
                    id: binding.id,
                    index_id,
                    counter_id,
                    collection: typed_collection,
                    source,
                    is_list,
                    body: typed_body,
                }
            }
            StmtKind::Discard(value) => {
                let typed = self.check_expr(value, None)?;
                if !matches!(
                    typed.kind,
                    TExprKind::CollectionOp {
                        op: CollectionOp::Push | CollectionOp::Insert,
                        ..
                    }
                ) {
                    return Err(CheckError { span: value.span, message: "discard accepts only a collection push or insert result with error type Full".to_owned() });
                }
                TStmtKind::Discard(typed)
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
            if !self.is_numeric(ty) {
                return Err(CheckError {
                    span: annotation.span,
                    message: "a loop counter must be int or long; use one of those types"
                        .to_owned(),
                });
            }
            constraints.push(self.base_type(ty));
        }
        for bound in [start, end] {
            if let Some(ty) = self.natural_expr_type(bound) {
                if !self.is_numeric(ty) {
                    return Err(CheckError {
                        span: bound.span,
                        message: format!(
                            "a range bound must be int or long, found {}",
                            self.type_name(ty)
                        ),
                    });
                }
                constraints.push(self.base_type(ty));
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
            ExprKind::ListLiteral => None,
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
                        (Some(left), None) if self.is_numeric(left) => Some(left),
                        (None, Some(right)) if self.is_numeric(right) => Some(right),
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
            ExprKind::QualifiedCase { enum_name, .. } => self.type_ids.get(enum_name).copied(),
            ExprKind::Field { receiver, name, .. } => {
                let receiver_ty = self.natural_expr_type_inner(receiver, shadowed_counter)?;
                match &self.types[receiver_ty.0].kind {
                    TTypeKind::Struct(fields) => {
                        fields.iter().find(|f| f.name == *name).map(|f| f.ty)
                    }
                    _ => None,
                }
            }
            ExprKind::Index { receiver, .. } => {
                let receiver_ty = self.natural_expr_type_inner(receiver, shadowed_counter)?;
                match self.types[receiver_ty.0].kind {
                    TTypeKind::Array { element, .. } | TTypeKind::List { element, .. } => {
                        Some(element)
                    }
                    _ => None,
                }
            }
            ExprKind::StructInit { name, .. } => self.type_ids.get(name).copied(),
            ExprKind::Fit { ty, .. } => self
                .parse_type(ty)
                .ok()
                .and_then(|inner| Some(self.option_type(inner, expr.span))),
            ExprKind::MethodCall { receiver, name, .. } => {
                let receiver_ty = self.natural_expr_type_inner(receiver, shadowed_counter)?;
                match (self.types[receiver_ty.0].kind.clone(), name.as_str()) {
                    (TTypeKind::Option(_), "is_none" | "is_some")
                    | (TTypeKind::Result(..), "is_ok" | "is_err") => Some(Ty::Bool),
                    (TTypeKind::Option(value), "unwrap") => Some(value),
                    (TTypeKind::Result(ok, _), "unwrap") => Some(ok),
                    (TTypeKind::Result(ok, _), "ok") => Some(self.option_type(ok, expr.span)),
                    (TTypeKind::Array { .. }, "len") | (TTypeKind::List { .. }, "count") => {
                        Some(Ty::Long)
                    }
                    (TTypeKind::List { element, .. }, "pop") => {
                        Some(self.option_type(element, expr.span))
                    }
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
            StmtKind::Assign { target, value, .. } => {
                let expected = self.resolve_place(target).ok().map(|place| place.ty);
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
            StmtKind::ForEach {
                collection, body, ..
            } => {
                self.collect_loop_constraints_expr(collection, counter, None, constraints);
                self.collect_loop_constraints_block(body, counter, constraints);
            }
            StmtKind::Discard(value) => {
                self.collect_loop_constraints_expr(value, counter, None, constraints)
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
                if let Some(ty) = expected.filter(|ty| self.is_numeric(*ty)) {
                    constraints.push(self.base_type(ty));
                }
            }
            ExprKind::Name(_) | ExprKind::Integer { .. } | ExprKind::Bool(_) | ExprKind::Unit => {}
            ExprKind::Call { name, args, .. } => {
                let parameters = self
                    .signatures
                    .get(name)
                    .map(|sig| sig.params.iter().map(|param| param.ty).collect::<Vec<_>>());
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
                    .type_ids
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
            ExprKind::Field { receiver, .. } => {
                self.collect_loop_constraints_expr(receiver, counter, None, constraints);
            }
            ExprKind::Index {
                receiver, index, ..
            } => {
                self.collect_loop_constraints_expr(receiver, counter, None, constraints);
                self.collect_loop_constraints_expr(index, counter, Some(Ty::Long), constraints);
            }
            ExprKind::ListLiteral => {}
            ExprKind::StructInit { fields, .. } => {
                for field in fields {
                    self.collect_loop_constraints_expr(&field.value, counter, None, constraints);
                }
            }
            ExprKind::Fit { value, .. } => {
                self.collect_loop_constraints_expr(value, counter, None, constraints);
            }
            ExprKind::Cast { ty, value, .. } => {
                // An explicit cast decides the expression's type at the use site. It must not
                // constrain the inferred loop counter type from the cast's destination.
                let _ = ty;
                self.collect_loop_constraints_expr(value, counter, None, constraints);
            }
            ExprKind::Unary { op, value, .. } => {
                let want = match op {
                    UnaryOp::Neg => expected.filter(|ty| self.is_numeric(*ty)),
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
                        expected.filter(|ty| self.is_numeric(*ty))
                    } else {
                        None
                    };
                    let left_natural = self
                        .natural_expr_type_inner(left, Some(counter))
                        .filter(|ty| self.is_numeric(*ty));
                    let right_natural = self
                        .natural_expr_type_inner(right, Some(counter))
                        .filter(|ty| self.is_numeric(*ty));
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
            values.push(self.check_store(arg, payload_ty)?);
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
                let value = if let Some(inner) = expected_inner {
                    self.check_store(&args[0], inner)?
                } else {
                    self.check_expr(&args[0], None)?
                };
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
                let value = self.check_store(&args[0], case.payload[0])?;
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
        let typed_collection = self.check_expr(receiver, None)?;
        if let TTypeKind::Array {
            element: _,
            capacity,
        } = self.types[typed_collection.ty.0].kind
        {
            if name == "len" && args.is_empty() {
                if let Some(want) = expected {
                    self.type_mismatch(Ty::Long, want, span)?;
                }
                return Ok((
                    TExprKind::CollectionOp {
                        op: CollectionOp::Len,
                        receiver: Box::new(typed_collection),
                        args: Vec::new(),
                        capacity,
                        proven_success: true,
                    },
                    Ty::Long,
                ));
            }
        }
        if let TTypeKind::List { element, capacity } = self.types[typed_collection.ty.0].kind {
            let op = match name {
                "push" => CollectionOp::Push,
                "pop" => CollectionOp::Pop,
                "insert" => CollectionOp::Insert,
                "remove" => CollectionOp::Remove,
                "count" => CollectionOp::Count,
                "clear" => CollectionOp::Clear,
                _ => {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "no method '{}' on {}; available methods: push, pop, insert, remove, count, clear",
                            name,
                            self.type_name(typed_collection.ty)
                        ),
                    });
                }
            };
            let expected_args = match op {
                CollectionOp::Push | CollectionOp::Remove => 1,
                CollectionOp::Insert => 2,
                _ => 0,
            };
            if args.len() != expected_args {
                return Err(CheckError {
                    span: method_span,
                    message: format!(
                        "method '{}.{}' takes {} argument(s), but got {}",
                        self.type_name(typed_collection.ty),
                        name,
                        expected_args,
                        args.len()
                    ),
                });
            }
            if op == CollectionOp::Count {
                if let Some(want) = expected {
                    self.type_mismatch(Ty::Long, want, span)?;
                }
                return Ok((
                    TExprKind::CollectionOp {
                        op,
                        receiver: Box::new(typed_collection),
                        args: Vec::new(),
                        capacity,
                        proven_success: true,
                    },
                    Ty::Long,
                ));
            }
            let mut receiver_place = self.resolve_place(receiver).map_err(|_| CheckError { span: receiver.span, message: "a collection mutation needs a var, write parameter, or writable collection view".to_owned() })?;
            if matches!(
                op,
                CollectionOp::Push
                    | CollectionOp::Pop
                    | CollectionOp::Insert
                    | CollectionOp::Remove
                    | CollectionOp::Clear
            ) {
                if !self.place_is_mutable(&receiver_place) {
                    return Err(CheckError { span: receiver.span, message: "a collection mutation needs mutable storage; use var or pass it as write".to_owned() });
                }
            }
            if matches!(
                op,
                CollectionOp::Pop
                    | CollectionOp::Insert
                    | CollectionOp::Remove
                    | CollectionOp::Clear
            ) && self.active_views.iter().any(|view| {
                let view = self.canonical_place(view);
                let receiver = self.canonical_place(&receiver_place);
                places_may_prefix(&receiver, &view)
            }) {
                return Err(CheckError {
                    span: method_span,
                    message: format!(
                        "cannot call '{}.{}' while a collection view is live; move the operation after the loop",
                        self.type_name(typed_collection.ty),
                        name
                    ),
                });
            }
            let mut typed_args = Vec::new();
            match op {
                CollectionOp::Push => typed_args.push(self.check_store(&args[0], element)?),
                CollectionOp::Insert => {
                    let index = self.check_collection_index(&args[0])?;
                    typed_args.push(index);
                    typed_args.push(self.check_store(&args[1], element)?);
                }
                CollectionOp::Remove => typed_args.push(self.check_collection_index(&args[0])?),
                _ => {}
            }
            let result = match op {
                CollectionOp::Push | CollectionOp::Insert => {
                    let full = self.type_ids["Full"];
                    self.intern_generic(
                        2,
                        Ty::Unit,
                        full,
                        "Result<(), Full>".to_owned(),
                        method_span,
                        TTypeKind::Result(Ty::Unit, full),
                    )
                }
                CollectionOp::Pop => self.option_type(element, method_span),
                CollectionOp::Remove => element,
                CollectionOp::Count | CollectionOp::Len => Ty::Long,
                CollectionOp::Clear => Ty::Unit,
            };
            if let Some(want) = expected {
                self.type_mismatch(result, want, span)?;
            }
            let count_key = self.collection_count_key(&receiver_place);
            let loop_proven = count_key.as_ref().is_some_and(|key| {
                self.loop_push_proofs
                    .iter()
                    .any(|proofs| proofs.contains(key))
            });
            let count_proven = self.loop_depth == 0
                && count_key
                    .as_ref()
                    .and_then(|key| self.collection_counts.get(key))
                    .is_some_and(|count| *count < capacity);
            let proven_success = op == CollectionOp::Push && (loop_proven || count_proven);
            match op {
                CollectionOp::Push => {
                    if let Some(key) = count_key {
                        if proven_success {
                            let current = self.collection_counts.get(&key).copied().unwrap_or(0);
                            self.collection_counts
                                .insert(key, current.saturating_add(1).min(capacity));
                        } else {
                            self.collection_counts.insert(key, capacity);
                        }
                    }
                }
                CollectionOp::Clear => {
                    if let Some(key) = count_key {
                        self.collection_counts.insert(key, 0);
                    }
                }
                CollectionOp::Pop | CollectionOp::Insert | CollectionOp::Remove => {
                    self.invalidate_collection_counts(&receiver_place)
                }
                CollectionOp::Count | CollectionOp::Len => {}
            }
            if matches!(
                op,
                CollectionOp::Push
                    | CollectionOp::Pop
                    | CollectionOp::Insert
                    | CollectionOp::Remove
                    | CollectionOp::Clear
            ) {
                self.invalidate_place(&receiver_place);
            }
            receiver_place.ty = typed_collection.ty;
            return Ok((
                TExprKind::CollectionOp {
                    op,
                    receiver: Box::new(typed_collection),
                    args: typed_args,
                    capacity,
                    proven_success,
                },
                result,
            ));
        }
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
        let typed = typed_collection;
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

    fn check_collection_index(&mut self, expr: &Expr) -> Result<TExpr, CheckError> {
        if self
            .natural_expr_type(expr)
            .is_some_and(|ty| self.base_type(ty) == Ty::Int)
        {
            return Err(CheckError {
                span: expr.span,
                message: "collection indexes are long; cast an int index with .to_long()"
                    .to_owned(),
            });
        }
        let index = self.check_expr(expr, Some(Ty::Long))?;
        if self.base_type(index.ty) != Ty::Long {
            return Err(CheckError {
                span: expr.span,
                message: "collection indexes are long; cast an int index with .to_long()"
                    .to_owned(),
            });
        }
        Ok(index)
    }

    fn default_typed_value(&mut self, ty: Ty, span: Span) -> Result<TExpr, CheckError> {
        let expr = match self.types[ty.0].kind.clone() {
            TTypeKind::Refinement {
                base,
                min,
                max,
                policy,
            } => {
                if min > 0 || max < 0 {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "{} has no valid default value; initialize it explicitly or give the field a default",
                            self.type_name(ty)
                        ),
                    });
                }
                let value = TExpr {
                    kind: TExprKind::Integer(0),
                    ty: base,
                    span,
                };
                TExpr {
                    kind: TExprKind::Convert {
                        value: Box::new(value),
                        min,
                        max,
                        policy,
                    },
                    ty,
                    span,
                }
            }
            TTypeKind::Int | TTypeKind::Long => TExpr {
                kind: TExprKind::Integer(0),
                ty,
                span,
            },
            TTypeKind::Bool => TExpr {
                kind: TExprKind::Bool(false),
                ty,
                span,
            },
            TTypeKind::List { .. } => TExpr {
                kind: TExprKind::EmptyList,
                ty,
                span,
            },
            TTypeKind::Array { element, capacity } => {
                if capacity == 0 {
                    TExpr {
                        kind: TExprKind::EmptyArray,
                        ty,
                        span,
                    }
                } else {
                    let value = self.default_typed_value(element, span)?;
                    TExpr {
                        kind: TExprKind::Fill {
                            value: Box::new(value),
                            capacity,
                        },
                        ty,
                        span,
                    }
                }
            }
            TTypeKind::Struct(fields) => {
                let declaration = self
                    .struct_decls
                    .get(&ty)
                    .cloned()
                    .expect("struct declaration exists");
                let mut values = Vec::new();
                for (index, field) in fields.iter().enumerate() {
                    if let Some(default) = declaration.fields[index].default.as_ref() {
                        values.push((index, self.check_store(default, field.ty)?));
                    } else if matches!(
                        self.types[field.ty.0].kind,
                        TTypeKind::Array { .. } | TTypeKind::List { .. }
                    ) {
                        values.push((index, self.default_typed_value(field.ty, span)?));
                    } else {
                        return Err(CheckError {
                            span,
                            message: format!(
                                "required field '{}.{}' has no default; initialize it or provide a fill value",
                                self.type_name(ty),
                                field.name
                            ),
                        });
                    }
                }
                TExpr {
                    kind: TExprKind::StructConstruct { fields: values },
                    ty,
                    span,
                }
            }
            TTypeKind::Option(inner) => {
                let _ = inner;
                TExpr {
                    kind: TExprKind::Construct {
                        case_index: 1,
                        args: Vec::new(),
                    },
                    ty,
                    span,
                }
            }
            _ => {
                return Err(CheckError {
                    span,
                    message: format!(
                        "{} has no valid default value; initialize it explicitly or give the field a default",
                        self.type_name(ty)
                    ),
                });
            }
        };
        Ok(expr)
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
                    expected
                        .filter(|t| self.is_numeric(*t))
                        .map(|t| self.base_type(t))
                        .unwrap_or(Ty::Int)
                };
                if *long_suffix && expected.is_some_and(|t| self.base_type(t) != Ty::Long) {
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
                } else if let Some(id) = self.constant_ids.get(name).copied() {
                    let ty = self.constant_types[id];
                    if let Some(want) = expected {
                        self.type_mismatch(ty, want, expr.span)?;
                    }
                    (TExprKind::Constant(id), ty)
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
            ExprKind::Field {
                receiver,
                name,
                field_span,
            } => {
                if let ExprKind::Name(type_name) = &receiver.kind {
                    if self.find_binding(type_name).is_none() {
                        if let Some(ty) = self.type_ids.get(type_name).copied() {
                            if let Some((index, case)) = self.find_case_in_type(ty, name) {
                                if !case.payload.is_empty() {
                                    return Err(CheckError {
                                        span: *field_span,
                                        message: format!(
                                            "case '{}.{}' needs {} payload value(s)",
                                            type_name,
                                            name,
                                            case.payload.len()
                                        ),
                                    });
                                }
                                let built =
                                    self.check_constructor(ty, index, &[], *field_span, expected)?;
                                return self.finish_expr(expr, built, expected);
                            }
                        }
                    }
                }
                let typed_receiver = self.check_expr(receiver, None)?;
                let TTypeKind::Struct(fields) = &self.types[typed_receiver.ty.0].kind else {
                    return Err(CheckError {
                        span: *field_span,
                        message: format!(
                            "{} has no fields; cannot read '{}'",
                            self.type_name(typed_receiver.ty),
                            name
                        ),
                    });
                };
                let Some(field_index) = fields.iter().position(|field| field.name == *name) else {
                    let names = fields
                        .iter()
                        .map(|field| field.name.clone())
                        .collect::<Vec<_>>();
                    let suffix = close_name(name, &names)
                        .map(|suggestion| format!("; did you mean '{}'", suggestion))
                        .unwrap_or_default();
                    return Err(CheckError {
                        span: *field_span,
                        message: format!(
                            "unknown field '{}' on {}{}",
                            name,
                            self.type_name(typed_receiver.ty),
                            suffix
                        ),
                    });
                };
                let field_ty = fields[field_index].ty;
                if let Some(want) = expected {
                    self.type_mismatch(field_ty, want, expr.span)?;
                }
                (
                    TExprKind::Field {
                        receiver: Box::new(typed_receiver),
                        field_index,
                    },
                    field_ty,
                )
            }
            ExprKind::Index {
                receiver,
                index,
                index_span,
            } => {
                let typed_receiver = self.check_expr(receiver, None)?;
                let (element, capacity, is_list) =
                    match self.types[typed_receiver.ty.0].kind.clone() {
                        TTypeKind::Array { element, capacity } => (element, capacity, false),
                        TTypeKind::List { element, capacity } => (element, capacity, true),
                        _ => {
                            return Err(CheckError {
                                span: *index_span,
                                message: format!(
                                    "{} cannot be indexed; use an array or list",
                                    self.type_name(typed_receiver.ty)
                                ),
                            });
                        }
                    };
                let typed_index = self.check_collection_index(index)?;
                let range = self.expr_range(&typed_index);
                let proven = range.is_some_and(|(lo, hi)| {
                    lo >= 0
                        && if is_list {
                            false
                        } else {
                            hi < capacity as i128
                        }
                });
                if let Some(want) = expected {
                    self.type_mismatch(element, want, expr.span)?;
                }
                (
                    TExprKind::Index {
                        receiver: Box::new(typed_receiver),
                        index: Box::new(typed_index),
                        capacity,
                        is_list,
                        proven,
                    },
                    element,
                )
            }
            ExprKind::ListLiteral => {
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::List { .. }))
                else {
                    return Err(CheckError { span: expr.span, message: "cannot infer the capacity for 'list {}'; add a list<T, N> type annotation".to_owned() });
                };
                (TExprKind::EmptyList, ty)
            }
            ExprKind::StructInit { name, fields } => {
                let Some(ty) = self.type_ids.get(name).copied() else {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!("unknown struct '{}'; declare it with struct", name),
                    });
                };
                let TTypeKind::Struct(type_fields) = self.types[ty.0].kind.clone() else {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!("'{}' is not a struct type", name),
                    });
                };
                let declaration = self
                    .struct_decls
                    .get(&ty)
                    .cloned()
                    .expect("struct declaration recorded");
                let mut supplied = HashMap::<usize, Span>::new();
                let mut typed_fields = Vec::new();
                for init in fields {
                    let Some(index) = type_fields.iter().position(|field| field.name == init.name)
                    else {
                        let names = type_fields
                            .iter()
                            .map(|field| field.name.clone())
                            .collect::<Vec<_>>();
                        let suffix = close_name(&init.name, &names)
                            .map(|suggestion| format!("; did you mean '{}'", suggestion))
                            .unwrap_or_default();
                        return Err(CheckError {
                            span: init.span,
                            message: format!(
                                "unknown field '{}' in {} literal{}",
                                init.name, name, suffix
                            ),
                        });
                    };
                    if let Some(previous) = supplied.insert(index, init.span) {
                        return Err(CheckError {
                            span: init.span,
                            message: format!(
                                "field '{}' is supplied more than once (first on line {})",
                                init.name, previous.line
                            ),
                        });
                    }
                    let value = self.check_store(&init.value, type_fields[index].ty)?;
                    typed_fields.push((index, value));
                }
                for (index, field) in type_fields.iter().enumerate() {
                    if supplied.contains_key(&index) {
                        continue;
                    }
                    let default = declaration.fields[index].default.as_ref();
                    if let Some(default) = default {
                        typed_fields.push((index, self.check_store(default, field.ty)?));
                    } else if matches!(
                        self.types[field.ty.0].kind,
                        TTypeKind::Array { .. } | TTypeKind::List { .. }
                    ) {
                        typed_fields.push((index, self.default_typed_value(field.ty, expr.span)?));
                    } else {
                        return Err(CheckError {
                            span: expr.span,
                            message: format!(
                                "missing required field '{}' in {} literal; give it a value",
                                field.name, name
                            ),
                        });
                    }
                }
                if let Some(want) = expected {
                    self.type_mismatch(ty, want, expr.span)?;
                }
                (
                    TExprKind::StructConstruct {
                        fields: typed_fields,
                    },
                    ty,
                )
            }
            ExprKind::Fit {
                value,
                ty,
                method_span,
            } => {
                let target = self.parse_type(ty)?;
                let Some((base, min, max, _)) = self.refinement(target) else {
                    return Err(CheckError {
                        span: ty.span,
                        message: "fit<T>() needs an int or long refinement type".to_owned(),
                    });
                };
                let value = self.check_expr(value, Some(base))?;
                if self.base_type(value.ty) != base {
                    return Err(CheckError {
                        span: *method_span,
                        message: format!(
                            "fit input must have base type {}; found {}",
                            self.type_name(base),
                            self.type_name(value.ty)
                        ),
                    });
                }
                let option_ty = self.option_type(target, expr.span);
                if let Some(want) = expected {
                    self.type_mismatch(option_ty, want, expr.span)?;
                }
                (
                    TExprKind::Fit {
                        value: Box::new(value),
                        min,
                        max,
                        option_ty,
                    },
                    option_ty,
                )
            }
            ExprKind::Call {
                name,
                call_span,
                args,
            } => {
                if name == "default" {
                    if !args.is_empty() {
                        return Err(CheckError {
                            span: *call_span,
                            message: "default takes no arguments".to_owned(),
                        });
                    }
                    let Some(target) = expected else {
                        return Err(CheckError {
                            span: *call_span,
                            message: "default needs an expected type; add a type annotation"
                                .to_owned(),
                        });
                    };
                    let value = self.default_typed_value(target, *call_span)?;
                    return self.finish_expr(expr, (value.kind, target), expected);
                } else if name == "fill" {
                    if args.len() != 1 {
                        return Err(CheckError {
                            span: *call_span,
                            message: format!("fill takes one value, but got {}", args.len()),
                        });
                    }
                    let Some(target) = expected else {
                        return Err(CheckError {
                            span: *call_span,
                            message: "fill needs an expected array type; add a T[N] annotation"
                                .to_owned(),
                        });
                    };
                    let TTypeKind::Array { element, capacity } = self.types[target.0].kind else {
                        return Err(CheckError {
                            span: *call_span,
                            message:
                                "fill constructs a fixed array; the expected type must be T[N]"
                                    .to_owned(),
                        });
                    };
                    let value = self.check_store(&args[0], element)?;
                    return self.finish_expr(
                        expr,
                        (
                            TExprKind::Fill {
                                value: Box::new(value),
                                capacity,
                            },
                            target,
                        ),
                        expected,
                    );
                } else if matches!(name.as_str(), "some" | "none" | "ok" | "err") {
                    self.check_builtin_constructor(name, args, *call_span, expected)?
                        .unwrap()
                } else if name == "min" || name == "max" {
                    if args.len() != 2 {
                        return Err(CheckError {
                            span: *call_span,
                            message: format!("{} takes two values; got {}", name, args.len()),
                        });
                    }
                    let (left, right) = self.check_operand_pair(
                        &args[0],
                        &args[1],
                        expected.filter(|ty| self.is_numeric(*ty)),
                    )?;
                    if self.base_type(left.ty) != self.base_type(right.ty)
                        || !self.is_numeric(left.ty)
                    {
                        return Err(self.mixed_types_error(left.ty, right.ty, *call_span));
                    }
                    let result_ty = self.base_type(left.ty);
                    if let Some(want) = expected {
                        self.type_mismatch(result_ty, self.base_type(want), *call_span)?;
                    }
                    (
                        TExprKind::Call {
                            target: if name == "min" {
                                CallTarget::Min
                            } else {
                                CallTarget::Max
                            },
                            args: vec![left, right],
                            effect: Effect::None,
                        },
                        result_ty,
                    )
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
                    if !matches!(self.base_type(arg.ty), Ty::Int | Ty::Long | Ty::Bool)
                        && !self.types[arg.ty.0].is_sum()
                        && !matches!(self.types[arg.ty.0].kind, TTypeKind::Struct(_))
                        && !matches!(
                            self.types[arg.ty.0].kind,
                            TTypeKind::Array { .. } | TTypeKind::List { .. }
                        )
                    {
                        return Err(CheckError {
                            span: args[0].span,
                            message: "print supports int, long, bool, enum, struct, array, and list values"
                                .to_owned(),
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
                    let mut arg_places = Vec::<Option<TPlace>>::new();
                    for (arg, param) in args.iter().zip(signature.params.iter().copied()) {
                        let place = self.resolve_place(arg).ok();
                        for (previous, previous_param) in
                            arg_places.iter().zip(signature.params.iter())
                        {
                            if (param.mode == ParamMode::Write
                                || previous_param.mode == ParamMode::Write)
                                && previous.as_ref().zip(place.as_ref()).is_some_and(|(a, b)| {
                                    places_overlap(
                                        &self.canonical_place(a),
                                        &self.canonical_place(b),
                                    )
                                })
                            {
                                return Err(CheckError { span: arg.span, message: "arguments overlap, and at least one is passed as write; pass separate fields or a copy".to_owned() });
                            }
                        }
                        if param.mode == ParamMode::Write {
                            let place = place.clone().ok_or_else(|| CheckError {
                                span: arg.span,
                                message: "a write argument must be an assignable place".to_owned(),
                            })?;
                            if !self.place_is_mutable(&place) {
                                return Err(CheckError { span: arg.span, message: "a write argument must be a var, a field of a var, or another write parameter".to_owned() });
                            }
                            let canonical = self.canonical_place(&place);
                            if self.active_views.iter().any(|view| {
                                let view = self.canonical_place(view);
                                places_overlap(&view, &canonical)
                                    && !places_proven_prefix(&view, &canonical)
                            }) {
                                return Err(CheckError { span: arg.span, message: "cannot pass storage containing a live collection view as write".to_owned() });
                            }
                            if place.ty != param.ty {
                                return Err(CheckError {
                                    span: arg.span,
                                    message: format!(
                                        "write argument needs exactly {}; found {}",
                                        self.type_name(param.ty),
                                        self.type_name(place.ty)
                                    ),
                                });
                            }
                            self.invalidate_place(&place);
                            self.invalidate_collection_counts(&place);
                            typed_args.push(self.check_expr(arg, Some(param.ty))?);
                        } else {
                            typed_args.push(self.check_store(arg, param.ty)?);
                        }
                        arg_places.push(place);
                    }
                    if let Some(want) = expected {
                        self.type_mismatch(signature.result, want, *call_span)?;
                    }
                    if !self.checking_constant {
                        self.edges.push(Edge {
                            from: self.current_function,
                            to: signature.id,
                            span: *call_span,
                        });
                    }
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
                let Some(ty) = self.type_ids.get(enum_name).copied() else {
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
                if name == "to_long" {
                    if !args.is_empty() || self.base_type(inner) != Ty::Int {
                        return Err(CheckError { span: *method_span, message: "optional method 'to_long()' takes no arguments and requires Option<int>".to_owned() });
                    }
                    let result_ty = self.option_type(Ty::Long, expr.span);
                    if let Some(want) = expected {
                        self.type_mismatch(result_ty, want, expr.span)?;
                    }
                    (
                        TExprKind::OptionalToLong(Box::new(typed_receiver)),
                        result_ty,
                    )
                } else {
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
                    if signature.params[0].mode == ParamMode::Write {
                        return Err(CheckError { span: *method_span, message: "optional chaining cannot call a function whose receiver parameter is write".to_owned() });
                    }
                    self.type_mismatch(inner, signature.params[0].ty, receiver.span)?;
                    let mut typed_args = Vec::new();
                    for (arg, param) in args.iter().zip(signature.params.iter().copied().skip(1)) {
                        if param.mode == ParamMode::Write {
                            return Err(CheckError { span: *method_span, message: "optional calls cannot pass a write parameter; call a function directly with an assignable place".to_owned() });
                        }
                        typed_args.push(self.check_store(arg, param.ty)?);
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
                    if !self.checking_constant {
                        self.edges.push(Edge {
                            from: self.current_function,
                            to: signature.id,
                            span: *method_span,
                        });
                    }
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
                if self.checking_constant {
                    return Err(CheckError {
                        span: expr.span,
                        message: "return is not allowed in a constant initializer".to_owned(),
                    });
                }
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
                if self.base_type(typed.ty) != Ty::Int {
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
                if !self.is_numeric(target) {
                    return Err(CheckError {
                        span: ty.span,
                        message: "casts in this task are between int and long".to_owned(),
                    });
                }
                let source = self.check_expr(value, None)?;
                if !self.is_numeric(source.ty) {
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
                        UnaryOp::Neg => expected.filter(|t| self.is_numeric(*t)),
                    },
                )?;
                match op {
                    UnaryOp::Not if typed.ty != Ty::Bool => {
                        return Err(CheckError {
                            span: value.span,
                            message: "'!' requires a bool".to_owned(),
                        });
                    }
                    UnaryOp::Neg if !self.is_numeric(typed.ty) => {
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
                        let qualified_ty = if let Some(ty) = self.type_ids.get(qualifier) {
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
                self.check_operand_pair(left, right, expected.filter(|t| self.is_numeric(*t)))?;
            if l.ty != r.ty
                && !(self.is_numeric(l.ty) && self.base_type(l.ty) == self.base_type(r.ty))
            {
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
                self.check_operand_pair(left, right, expected.filter(|t| self.is_numeric(*t)))?;
            if l.ty != r.ty
                && !(self.is_numeric(l.ty) && self.base_type(l.ty) == self.base_type(r.ty))
            {
                return Err(self.mixed_types_error(l.ty, r.ty, span));
            }
            if !self.is_numeric(l.ty) {
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
            self.check_operand_pair(left, right, expected.filter(|t| self.is_numeric(*t)))?
        };
        if l.ty != r.ty && !(self.is_numeric(l.ty) && self.base_type(l.ty) == self.base_type(r.ty))
        {
            return Err(self.mixed_types_error(l.ty, r.ty, span));
        }
        if !self.is_numeric(l.ty) {
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
                self.base_type(l.ty),
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
        if left != right
            && !(self.is_numeric(left) && self.base_type(left) == self.base_type(right))
        {
            return Err(self.mixed_types_error(left, right, span));
        }
        if !self.is_numeric(left) {
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
        let entry_facts = self.facts.clone();
        let entry_counts = self.collection_counts.clone();
        self.narrow_from_condition(&condition, true);
        let then_block =
            self.check_block(then_ast, true, if value_context { expected } else { None })?;
        let then_facts = self.facts.clone();
        let then_counts = self.collection_counts.clone();
        self.facts = entry_facts.clone();
        self.collection_counts = entry_counts.clone();
        self.narrow_from_condition(&condition, false);
        let else_block = else_ast
            .map(|b| self.check_block(b, true, if value_context { expected } else { None }))
            .transpose()?;
        let else_facts = self.facts.clone();
        let else_counts = self.collection_counts.clone();
        self.facts = match (
            then_block.falls_through,
            else_block.as_ref().is_none_or(|b| b.falls_through),
        ) {
            (true, true) => intersect_facts(&then_facts, &else_facts),
            (true, false) => then_facts,
            (false, true) => else_facts,
            (false, false) => entry_facts,
        };
        self.collection_counts = match (
            then_block.falls_through,
            else_block.as_ref().is_none_or(|b| b.falls_through),
        ) {
            (true, true) => {
                let mut joined = HashMap::new();
                for (key, left) in &then_counts {
                    if let Some(right) = else_counts.get(key) {
                        joined.insert(key.clone(), (*left).max(*right));
                    }
                }
                joined
            }
            (true, false) => then_counts,
            (false, true) => else_counts,
            (false, false) => entry_counts,
        };
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

    fn narrow_from_condition(&mut self, condition: &TExpr, truth: bool) {
        match &condition.kind {
            TExprKind::Unary {
                op: UnaryOp::Not,
                value,
                ..
            } => self.narrow_from_condition(value, !truth),
            TExprKind::Binary {
                op, left, right, ..
            } if is_comparison(*op) => {
                let (place_expr, value, mut op) = if let (Some(_), TExprKind::Integer(value)) =
                    (self.place_key(left), &right.kind)
                {
                    (left.as_ref(), *value, *op)
                } else if let (TExprKind::Integer(value), Some(_)) =
                    (&left.kind, self.place_key(right))
                {
                    (right.as_ref(), *value, reverse_comparison(*op))
                } else {
                    return;
                };
                if !truth {
                    op = negate_comparison(op);
                }
                let Some((root, fields)) = self.place_key(place_expr) else {
                    return;
                };
                let Some((base_lo, base_hi)) = integer_bounds(self.base_type(place_expr.ty)) else {
                    return;
                };
                let (mut lo, mut hi) = self
                    .facts
                    .get(&(root, fields.clone()))
                    .copied()
                    .or_else(|| {
                        self.refinement(place_expr.ty)
                            .map(|(_, lo, hi, _)| (lo, hi))
                    })
                    .unwrap_or((base_lo, base_hi));
                match op {
                    BinaryOp::Lt => hi = hi.min(value.saturating_sub(1)),
                    BinaryOp::Le => hi = hi.min(value),
                    BinaryOp::Gt => lo = lo.max(value.saturating_add(1)),
                    BinaryOp::Ge => lo = lo.max(value),
                    BinaryOp::Eq => {
                        lo = lo.max(value);
                        hi = hi.min(value);
                    }
                    BinaryOp::Ne => {
                        if value == lo {
                            lo = lo.saturating_add(1);
                        } else if value == hi {
                            hi = hi.saturating_sub(1);
                        }
                    }
                    _ => return,
                }
                if lo <= hi {
                    self.facts.insert((root, fields), (lo, hi));
                }
            }
            TExprKind::Binary {
                op: BinaryOp::And,
                left,
                right,
                ..
            } if truth => {
                self.narrow_from_condition(left, true);
                self.narrow_from_condition(right, true);
            }
            TExprKind::Binary {
                op: BinaryOp::Or,
                left,
                right,
                ..
            } if !truth => {
                self.narrow_from_condition(left, false);
                self.narrow_from_condition(right, false);
            }
            _ => {}
        }
    }

    fn collect_loop_writes(
        &mut self,
        block: &Block,
        writes: &mut std::collections::HashSet<usize>,
    ) {
        for statement in &block.statements {
            match &statement.kind {
                StmtKind::Assign { target, value, .. } => {
                    if let Ok(place) = self.resolve_place(target) {
                        writes.insert(place.root);
                    }
                    self.collect_expr_writes(value, writes);
                }
                StmtKind::Let { value, .. } | StmtKind::Expr(value) | StmtKind::Discard(value) => {
                    self.collect_expr_writes(value, writes)
                }
                StmtKind::Return(value) => {
                    if let Some(value) = value {
                        self.collect_expr_writes(value, writes);
                    }
                }
                StmtKind::For {
                    start, end, body, ..
                } => {
                    self.collect_expr_writes(start, writes);
                    self.collect_expr_writes(end, writes);
                    self.collect_loop_writes(body, writes);
                }
                StmtKind::ForEach {
                    collection, body, ..
                } => {
                    self.collect_expr_writes(collection, writes);
                    self.collect_loop_writes(body, writes);
                }
                StmtKind::Expect { value, .. } => self.collect_expr_writes(value, writes),
                StmtKind::Block(body) => self.collect_loop_writes(body, writes),
                StmtKind::Break | StmtKind::Continue => {}
            }
        }
        if let Some(tail) = &block.tail {
            self.collect_expr_writes(tail, writes);
        }
    }

    fn collect_expr_writes(&mut self, expr: &Expr, writes: &mut std::collections::HashSet<usize>) {
        match &expr.kind {
            ExprKind::Call { name, args, .. } => {
                if let Some(signature) = self.signatures.get(name).cloned() {
                    for (arg, param) in args.iter().zip(&signature.params) {
                        if param.mode == ParamMode::Write {
                            if let Ok(place) = self.resolve_place(arg) {
                                writes.insert(place.root);
                            }
                        }
                    }
                }
                for arg in args {
                    self.collect_expr_writes(arg, writes);
                }
            }
            ExprKind::StructInit { fields, .. } => {
                for field in fields {
                    self.collect_expr_writes(&field.value, writes);
                }
            }
            ExprKind::MethodCall { receiver, args, .. }
            | ExprKind::OptionalCall { receiver, args, .. } => {
                self.collect_expr_writes(receiver, writes);
                for arg in args {
                    self.collect_expr_writes(arg, writes);
                }
            }
            ExprKind::Field { receiver, .. }
            | ExprKind::Index { receiver, .. }
            | ExprKind::Fit {
                value: receiver, ..
            }
            | ExprKind::Try(receiver)
            | ExprKind::ToLong {
                value: receiver, ..
            }
            | ExprKind::Cast {
                value: receiver, ..
            }
            | ExprKind::Unary {
                value: receiver, ..
            } => self.collect_expr_writes(receiver, writes),
            ExprKind::QualifiedCase { args, .. } => {
                for arg in args {
                    self.collect_expr_writes(arg, writes);
                }
            }
            ExprKind::Binary { left, right, .. } => {
                self.collect_expr_writes(left, writes);
                self.collect_expr_writes(right, writes);
            }
            ExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                self.collect_expr_writes(condition, writes);
                self.collect_loop_writes(then_block, writes);
                if let Some(other) = else_block {
                    self.collect_loop_writes(other, writes);
                }
            }
            ExprKind::Match { scrutinee, arms } => {
                self.collect_expr_writes(scrutinee, writes);
                for arm in arms {
                    self.collect_loop_writes(&arm.body, writes);
                }
            }
            ExprKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr_writes(value, writes);
                }
            }
            ExprKind::Name(_)
            | ExprKind::ListLiteral
            | ExprKind::Unit
            | ExprKind::Integer { .. }
            | ExprKind::Bool(_)
            | ExprKind::LoopExit(_) => {}
        }
    }

    fn declare(
        &mut self,
        name: &str,
        ty: Ty,
        mutable: bool,
        span: Span,
        loop_counter: bool,
    ) -> Result<Binding, CheckError> {
        self.declare_mode(name, ty, mutable, ParamMode::Read, span, loop_counter)
    }

    fn declare_mode(
        &mut self,
        name: &str,
        ty: Ty,
        mutable: bool,
        mode: ParamMode,
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
            mode,
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

    fn binding_by_id(&self, id: usize) -> Option<Binding> {
        self.locals
            .iter()
            .flat_map(|scope| scope.values())
            .find(|binding| binding.id == id)
            .cloned()
    }

    fn function_param_count(&self) -> usize {
        self.ast_functions
            .get(self.current_function)
            .map_or(0, |function| function.params.len())
    }

    fn resolve_place(&mut self, expr: &Expr) -> Result<TPlace, CheckError> {
        match &expr.kind {
            ExprKind::Name(name) => {
                let binding = self
                    .find_binding(name)
                    .ok_or_else(|| self.unknown_local(name, expr.span))?;
                Ok(TPlace {
                    root: binding.id,
                    fields: Vec::new(),
                    path: Vec::new(),
                    ty: binding.ty,
                })
            }
            ExprKind::Field {
                receiver,
                name,
                field_span,
            } => {
                let mut place = self.resolve_place(receiver)?;
                let TTypeKind::Struct(fields) = &self.types[place.ty.0].kind else {
                    return Err(CheckError {
                        span: *field_span,
                        message: format!("{} has no fields", self.type_name(place.ty)),
                    });
                };
                let Some(index) = fields.iter().position(|field| field.name == *name) else {
                    let candidates = fields
                        .iter()
                        .map(|field| field.name.clone())
                        .collect::<Vec<_>>();
                    let suffix = close_name(name, &candidates)
                        .map(|suggestion| format!("; did you mean '{}'", suggestion))
                        .unwrap_or_default();
                    return Err(CheckError {
                        span: *field_span,
                        message: format!(
                            "unknown field '{}' on {}{}",
                            name,
                            self.type_name(place.ty),
                            suffix
                        ),
                    });
                };
                place.fields.push(index);
                place.path.push(TProjection::Field(index));
                place.ty = fields[index].ty;
                Ok(place)
            }
            ExprKind::Index {
                receiver,
                index,
                index_span,
            } => {
                let mut place = self.resolve_place(receiver)?;
                let (element, capacity, is_list) = match self.types[place.ty.0].kind {
                    TTypeKind::Array { element, capacity } => (element, capacity, false),
                    TTypeKind::List { element, capacity } => (element, capacity, true),
                    _ => {
                        return Err(CheckError {
                            span: *index_span,
                            message: format!(
                                "{} cannot be indexed; use an array or list",
                                self.type_name(place.ty)
                            ),
                        });
                    }
                };
                let typed_index = self.check_collection_index(index)?;
                let range = self.expr_range(&typed_index);
                let proven = range.is_some_and(|(lo, hi)| {
                    lo >= 0
                        && if is_list {
                            false
                        } else {
                            hi < capacity as i128
                        }
                });
                let constant = range.filter(|(lo, hi)| lo == hi).map(|(lo, _)| lo);
                place.path.push(TProjection::Index {
                    index: typed_index,
                    constant,
                    capacity,
                    is_list,
                    proven,
                });
                place.ty = element;
                Ok(place)
            }
            _ => Err(CheckError {
                span: expr.span,
                message: "this expression is not an assignable place; use a var or a field of one"
                    .to_owned(),
            }),
        }
    }

    fn place_is_mutable(&self, place: &TPlace) -> bool {
        self.binding_by_id(place.root)
            .is_some_and(|binding| binding.mutable)
    }

    fn canonical_place(&self, place: &TPlace) -> TPlace {
        let mut canonical = place.clone();
        let mut seen = Vec::new();
        while let Some(alias) = self.view_bindings.get(&canonical.root) {
            if seen.contains(&canonical.root) {
                break;
            }
            seen.push(canonical.root);
            let mut expanded = alias.clone();
            expanded.path.extend(canonical.path.iter().cloned());
            expanded.fields.extend(canonical.fields.iter().copied());
            expanded.ty = canonical.ty;
            canonical = expanded;
        }
        canonical
    }

    fn collection_count_key(&self, place: &TPlace) -> Option<CollectionCountKey> {
        let place = self.canonical_place(place);
        let mut fields = Vec::with_capacity(place.path.len());
        for projection in &place.path {
            match projection {
                TProjection::Field(index) => fields.push(*index),
                TProjection::Index { .. } => return None,
            }
        }
        Some(CollectionCountKey {
            root: place.root,
            fields,
        })
    }

    fn invalidate_collection_counts(&mut self, place: &TPlace) {
        let Some(key) = self.collection_count_key(place) else {
            return;
        };
        self.collection_counts.retain(|existing, _| {
            existing.root != key.root
                || !(is_prefix(&key.fields, &existing.fields)
                    || is_prefix(&existing.fields, &key.fields))
        });
        for proofs in &mut self.loop_push_proofs {
            proofs.retain(|existing| {
                existing.root != key.root
                    || !(is_prefix(&key.fields, &existing.fields)
                        || is_prefix(&existing.fields, &key.fields))
            });
        }
    }

    fn count_key_capacity(&self, key: &CollectionCountKey) -> Option<usize> {
        let mut ty = self.binding_by_id(key.root)?.ty;
        for field in &key.fields {
            ty = match &self.types[ty.0].kind {
                TTypeKind::Struct(fields) => fields.get(*field)?.ty,
                _ => return None,
            };
        }
        match self.types[ty.0].kind {
            TTypeKind::List { capacity, .. } => Some(capacity),
            _ => None,
        }
    }

    fn max_loop_iterations(&self, start: &TExpr, end: &TExpr, inclusive: bool) -> Option<usize> {
        let (start_min, _) = self.expr_range(start)?;
        let (_, end_max) = self.expr_range(end)?;
        let count = if inclusive {
            end_max.saturating_sub(start_min).saturating_add(1)
        } else {
            end_max.saturating_sub(start_min).max(0)
        };
        usize::try_from(count).ok()
    }

    fn collect_loop_pushes(&mut self, body: &Block) -> Option<HashMap<CollectionCountKey, usize>> {
        fn expr(
            checker: &mut Checker,
            value: &Expr,
            counts: &mut HashMap<CollectionCountKey, usize>,
        ) -> bool {
            match &value.kind {
                ExprKind::MethodCall {
                    receiver,
                    name,
                    args,
                    ..
                } => {
                    if name == "push" {
                        if let Ok(place) = checker.resolve_place(receiver) {
                            if let Some(key) = checker.collection_count_key(&place) {
                                *counts.entry(key).or_insert(0) += 1;
                            }
                        }
                    }
                    expr(checker, receiver, counts)
                        && args.iter().all(|arg| expr(checker, arg, counts))
                }
                ExprKind::Call { args, .. } | ExprKind::QualifiedCase { args, .. } => {
                    args.iter().all(|arg| expr(checker, arg, counts))
                }
                ExprKind::OptionalCall { receiver, args, .. } => {
                    expr(checker, receiver, counts)
                        && args.iter().all(|arg| expr(checker, arg, counts))
                }
                ExprKind::Index {
                    receiver, index, ..
                }
                | ExprKind::Binary {
                    left: receiver,
                    right: index,
                    ..
                } => expr(checker, receiver, counts) && expr(checker, index, counts),
                ExprKind::Field { receiver, .. }
                | ExprKind::Fit {
                    value: receiver, ..
                }
                | ExprKind::Try(receiver)
                | ExprKind::ToLong {
                    value: receiver, ..
                }
                | ExprKind::Cast {
                    value: receiver, ..
                }
                | ExprKind::Unary {
                    value: receiver, ..
                } => expr(checker, receiver, counts),
                ExprKind::StructInit { fields, .. } => fields
                    .iter()
                    .all(|field| expr(checker, &field.value, counts)),
                ExprKind::Return(Some(value)) => expr(checker, value, counts),
                ExprKind::Return(None)
                | ExprKind::Unit
                | ExprKind::Integer { .. }
                | ExprKind::Bool(_)
                | ExprKind::Name(_)
                | ExprKind::ListLiteral
                | ExprKind::LoopExit(_) => true,
                ExprKind::Match { scrutinee, arms } => {
                    if !expr(checker, scrutinee, counts) {
                        return false;
                    }
                    let base = counts.clone();
                    let mut joined = base.clone();
                    for arm in arms {
                        let mut branch = base.clone();
                        if !block(checker, &arm.body, &mut branch) {
                            return false;
                        }
                        merge_push_counts(&mut joined, &base, &branch);
                    }
                    *counts = joined;
                    true
                }
                ExprKind::If {
                    condition,
                    then_block,
                    else_block,
                } => {
                    if !expr(checker, condition, counts) {
                        return false;
                    }
                    let base = counts.clone();
                    let mut then_counts = base.clone();
                    if !block(checker, then_block, &mut then_counts) {
                        return false;
                    }
                    let mut else_counts = base.clone();
                    if let Some(other) = else_block {
                        if !block(checker, other, &mut else_counts) {
                            return false;
                        }
                    }
                    let mut joined = base.clone();
                    merge_push_counts(&mut joined, &base, &then_counts);
                    merge_push_counts(&mut joined, &base, &else_counts);
                    *counts = joined;
                    true
                }
            }
        }
        fn merge_push_counts(
            joined: &mut HashMap<CollectionCountKey, usize>,
            base: &HashMap<CollectionCountKey, usize>,
            branch: &HashMap<CollectionCountKey, usize>,
        ) {
            for (key, value) in branch {
                let initial = base.get(key).copied().unwrap_or(0);
                if *value > initial {
                    let slot = joined.entry(key.clone()).or_insert(initial);
                    *slot = (*slot).max(*value);
                }
            }
        }
        fn block(
            checker: &mut Checker,
            body: &Block,
            counts: &mut HashMap<CollectionCountKey, usize>,
        ) -> bool {
            for statement in &body.statements {
                let simple = match &statement.kind {
                    StmtKind::Let { value, .. }
                    | StmtKind::Expr(value)
                    | StmtKind::Discard(value) => expr(checker, value, counts),
                    StmtKind::Assign { target, value, .. } => {
                        expr(checker, target, counts) && expr(checker, value, counts)
                    }
                    StmtKind::Return(Some(value)) => expr(checker, value, counts),
                    StmtKind::Expect { value, .. } => expr(checker, value, counts),
                    StmtKind::Block(inner) => block(checker, inner, counts),
                    StmtKind::For { .. } | StmtKind::ForEach { .. } => return false,
                    StmtKind::Return(None) | StmtKind::Break | StmtKind::Continue => true,
                };
                if !simple {
                    return false;
                }
            }
            body.tail
                .as_ref()
                .is_none_or(|tail| expr(checker, tail, counts))
        }
        let mut counts = HashMap::new();
        block(self, body, &mut counts).then_some(counts)
    }

    fn prepare_loop_push_proofs(
        &mut self,
        body: &Block,
        iterations: Option<usize>,
    ) -> HashMap<CollectionCountKey, usize> {
        let Some(pushes) = self.collect_loop_pushes(body) else {
            self.loop_push_proofs.push(std::collections::HashSet::new());
            return HashMap::new();
        };
        let mut proofs = std::collections::HashSet::new();
        let mut per_iteration = HashMap::new();
        if let Some(iterations) = iterations {
            for (key, amount) in pushes {
                if let (Some(current), Some(capacity)) = (
                    self.collection_counts.get(&key).copied(),
                    self.count_key_capacity(&key),
                ) {
                    let total = amount
                        .checked_mul(iterations)
                        .and_then(|adds| current.checked_add(adds));
                    if total.is_some_and(|total| total <= capacity) {
                        proofs.insert(key.clone());
                    }
                    per_iteration.insert(key, amount);
                }
            }
        }
        self.loop_push_proofs.push(proofs);
        per_iteration
    }

    fn finish_loop_push_proofs(
        &mut self,
        before: HashMap<CollectionCountKey, usize>,
        after_body: HashMap<CollectionCountKey, usize>,
        per_iteration: HashMap<CollectionCountKey, usize>,
        iterations: usize,
    ) {
        let proofs = self.loop_push_proofs.pop().unwrap_or_default();
        let push_keys = per_iteration
            .keys()
            .cloned()
            .collect::<std::collections::HashSet<_>>();
        self.collection_counts = before.clone();
        for key in before.keys() {
            if !after_body.contains_key(key) {
                self.collection_counts.remove(key);
            }
        }
        for (key, amount) in per_iteration {
            if !after_body.contains_key(&key) {
                self.collection_counts.remove(&key);
            } else if proofs.contains(&key) {
                if let Some(start) = before.get(&key) {
                    let total = amount.saturating_mul(iterations);
                    self.collection_counts
                        .insert(key, start.saturating_add(total));
                }
            } else if let Some(capacity) = self.count_key_capacity(&key) {
                self.collection_counts.insert(key, capacity);
            }
        }
        for (key, count) in after_body {
            if !push_keys.contains(&key) {
                let merged = before.get(&key).copied().unwrap_or(count).max(count);
                self.collection_counts.insert(key, merged);
            }
        }
    }

    fn typed_place_expr(&self, place: &TPlace, span: Span) -> TExpr {
        let binding = self
            .binding_by_id(place.root)
            .expect("place owner exists in scope");
        let mut expr = TExpr {
            kind: TExprKind::Local(place.root),
            ty: binding.ty,
            span,
        };
        for projection in &place.path {
            match projection {
                TProjection::Field(index) => {
                    let field_ty = match &self.types[expr.ty.0].kind {
                        TTypeKind::Struct(fields) => fields[*index].ty,
                        _ => unreachable!("resolved place field belongs to a struct"),
                    };
                    expr = TExpr {
                        kind: TExprKind::Field {
                            receiver: Box::new(expr),
                            field_index: *index,
                        },
                        ty: field_ty,
                        span,
                    };
                }
                TProjection::Index {
                    index,
                    capacity,
                    is_list,
                    proven,
                    ..
                } => {
                    let element = match self.types[expr.ty.0].kind {
                        TTypeKind::Array { element, .. } | TTypeKind::List { element, .. } => {
                            element
                        }
                        _ => unreachable!("resolved place index belongs to a collection"),
                    };
                    expr = TExpr {
                        kind: TExprKind::Index {
                            receiver: Box::new(expr),
                            index: Box::new(index.clone()),
                            capacity: *capacity,
                            is_list: *is_list,
                            proven: *proven,
                        },
                        ty: element,
                        span,
                    };
                }
            }
        }
        expr
    }

    fn invalidate_place(&mut self, place: &TPlace) {
        let Some(path) = place_field_path(place) else {
            self.facts.retain(|(root, _), _| *root != place.root);
            return;
        };
        self.facts.retain(|(root, fields), _| {
            if *root != place.root {
                return true;
            }
            !is_prefix(&path, fields) && !is_prefix(fields, &path)
        });
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
        if actual == expected
            || actual == Ty::Never
            || (self.is_numeric(actual) && self.base_type(actual) == self.base_type(expected))
        {
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

    fn base_type(&self, ty: Ty) -> Ty {
        base_type(ty, &self.types)
    }

    fn is_numeric(&self, ty: Ty) -> bool {
        is_numeric_type(ty, &self.types)
    }

    fn refinement(&self, ty: Ty) -> Option<(Ty, i128, i128, RefinePolicy)> {
        refinement(ty, &self.types)
    }

    fn place_key(&self, expr: &TExpr) -> Option<(usize, Vec<usize>)> {
        match &expr.kind {
            TExprKind::Local(id) => Some((*id, Vec::new())),
            TExprKind::Field {
                receiver,
                field_index,
            } => {
                let (root, mut fields) = self.place_key(receiver)?;
                fields.push(*field_index);
                Some((root, fields))
            }
            _ => None,
        }
    }

    fn expr_range(&self, expr: &TExpr) -> Option<(i128, i128)> {
        match &expr.kind {
            TExprKind::Integer(value) => Some((*value, *value)),
            TExprKind::Constant(id) => self
                .ast_constants
                .get(*id)
                .and_then(|constant| self.capacity_value(&constant.value).ok())
                .map(|value| (value, value)),
            TExprKind::CollectionOp {
                op: CollectionOp::Len,
                capacity,
                ..
            } => Some((*capacity as i128, *capacity as i128)),
            TExprKind::CollectionOp {
                op: CollectionOp::Count,
                capacity,
                ..
            } => Some((0, *capacity as i128)),
            TExprKind::Local(id) => self
                .range_for_place(*id, &[])
                .or_else(|| self.refinement(expr.ty).map(|(_, lo, hi, _)| (lo, hi)))
                .or_else(|| integer_bounds(self.base_type(expr.ty))),
            TExprKind::Field {
                receiver,
                field_index,
            } => {
                let (root, mut fields) = self.place_key(receiver)?;
                fields.push(*field_index);
                self.range_for_place(root, &fields)
                    .or_else(|| self.refinement(expr.ty).map(|(_, lo, hi, _)| (lo, hi)))
                    .or_else(|| integer_bounds(self.base_type(expr.ty)))
            }
            TExprKind::Convert {
                value,
                min,
                max,
                policy,
            } => match policy {
                RefinePolicy::Checked => self.expr_range(value),
                RefinePolicy::Wrap | RefinePolicy::Clamp => Some((*min, *max)),
            },
            TExprKind::ToLong(value) => self.expr_range(value),
            TExprKind::Unary {
                op: UnaryOp::Neg,
                value,
                ..
            } => {
                let (lo, hi) = self.expr_range(value)?;
                let base = self.base_type(expr.ty);
                let (base_lo, base_hi) = integer_bounds(base)?;
                Some(((-hi).max(base_lo), (-lo).min(base_hi)))
            }
            TExprKind::Binary {
                op, left, right, ..
            } if is_numeric_type(expr.ty, &self.types) => {
                let base = self.base_type(expr.ty);
                let (base_lo, base_hi) = integer_bounds(base)?;
                if matches!(
                    op,
                    BinaryOp::WrapAdd | BinaryOp::WrapSub | BinaryOp::WrapMul
                ) {
                    return Some((base_lo, base_hi));
                }
                let (a, b) = self.expr_range(left)?;
                let (c, d) = self.expr_range(right)?;
                let (lo, hi) = match op {
                    BinaryOp::Add => (a.saturating_add(c), b.saturating_add(d)),
                    BinaryOp::Sub => (a.saturating_sub(d), b.saturating_sub(c)),
                    BinaryOp::Mul => {
                        let vals = [
                            a.saturating_mul(c),
                            a.saturating_mul(d),
                            b.saturating_mul(c),
                            b.saturating_mul(d),
                        ];
                        (*vals.iter().min()?, *vals.iter().max()?)
                    }
                    BinaryOp::Div | BinaryOp::Rem => (base_lo, base_hi),
                    _ => return None,
                };
                Some((lo.max(base_lo), hi.min(base_hi)))
            }
            TExprKind::Call {
                target: CallTarget::Min,
                args,
                ..
            } if args.len() == 2 => {
                let (a, b) = self.expr_range(&args[0])?;
                let (c, d) = self.expr_range(&args[1])?;
                Some((a.min(c), b.min(d)))
            }
            TExprKind::Call {
                target: CallTarget::Max,
                args,
                ..
            } if args.len() == 2 => {
                let (a, b) = self.expr_range(&args[0])?;
                let (c, d) = self.expr_range(&args[1])?;
                Some((a.max(c), b.max(d)))
            }
            _ => self.refinement(expr.ty).map(|(_, lo, hi, _)| (lo, hi)),
        }
    }

    fn range_for_place(&self, root: usize, fields: &[usize]) -> Option<(i128, i128)> {
        self.facts.get(&(root, fields.to_vec())).copied()
    }

    fn record_nested_facts(&mut self, root: usize, prefix: &[usize], value: &TExpr) {
        for (path, range) in self.nested_facts_for_value(prefix, value) {
            self.facts.insert((root, path), range);
        }
    }

    fn nested_facts_for_value(
        &self,
        prefix: &[usize],
        value: &TExpr,
    ) -> Vec<(Vec<usize>, (i128, i128))> {
        let mut collected = Vec::new();
        if let Some((source_root, source_fields)) = self.place_key(value) {
            let copies = self
                .facts
                .iter()
                .filter_map(|((owner, path), range)| {
                    if *owner == source_root && is_prefix(&source_fields, path) {
                        let mut target = prefix.to_vec();
                        target.extend_from_slice(&path[source_fields.len()..]);
                        Some((target, *range))
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();
            collected.extend(copies);
        }
        if let TExprKind::StructConstruct { fields } = &value.kind {
            for (index, field) in fields {
                let mut path = prefix.to_vec();
                path.push(*index);
                if let Some(range) = self.expr_range(field) {
                    collected.push((path.clone(), range));
                }
                collected.extend(self.nested_facts_for_value(&path, field));
            }
        }
        collected
    }

    fn check_store(&mut self, expr: &Expr, target: Ty) -> Result<TExpr, CheckError> {
        let typed = self.check_expr(expr, Some(target))?;
        self.coerce_store_hint(typed, target, &source_hint(expr))
    }

    fn coerce_store(&self, value: TExpr, target: Ty) -> Result<TExpr, CheckError> {
        self.coerce_store_hint(value, target, "value")
    }

    fn coerce_store_hint(&self, value: TExpr, target: Ty, hint: &str) -> Result<TExpr, CheckError> {
        if self.base_type(value.ty) != self.base_type(target) {
            return Err(self.mixed_types_error(value.ty, target, value.span));
        }
        let Some((base, min, max, policy)) = self.refinement(target) else {
            if value.ty != target && self.base_type(value.ty) != self.base_type(target) {
                return Err(self.mixed_types_error(value.ty, target, value.span));
            }
            return Ok(value);
        };
        if self.base_type(value.ty) != base {
            return Err(self.mixed_types_error(value.ty, target, value.span));
        }
        if value.ty == target {
            return Ok(value);
        }
        if policy == RefinePolicy::Checked {
            let range = self
                .expr_range(&value)
                .unwrap_or_else(|| integer_bounds(base).unwrap());
            if range.0 < min || range.1 > max {
                return Err(CheckError {
                    span: value.span,
                    message: format!(
                        "cannot prove this value fits {}; use ({})({}) for a checked cast or {}.fit<{}>() to handle failure",
                        self.type_name(target),
                        self.type_name(target),
                        hint,
                        hint,
                        self.type_name(target)
                    ),
                });
            }
        }
        let span = value.span;
        Ok(TExpr {
            kind: TExprKind::Convert {
                value: Box::new(value),
                min,
                max,
                policy,
            },
            ty: target,
            span,
        })
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

fn integer_bounds(ty: Ty) -> Option<(i128, i128)> {
    match ty {
        Ty::Int => Some((i32::MIN as i128, i32::MAX as i128)),
        Ty::Long => Some((i64::MIN as i128, i64::MAX as i128)),
        _ => None,
    }
}

fn is_prefix(a: &[usize], b: &[usize]) -> bool {
    a.len() <= b.len() && a.iter().zip(b).all(|(x, y)| x == y)
}

fn places_overlap(a: &TPlace, b: &TPlace) -> bool {
    if a.root != b.root {
        return false;
    }
    fn same_or_uncertain(a: &TProjection, b: &TProjection) -> bool {
        match (a, b) {
            (TProjection::Field(x), TProjection::Field(y)) => x == y,
            (
                TProjection::Index {
                    constant: Some(x), ..
                },
                TProjection::Index {
                    constant: Some(y), ..
                },
            ) => x == y,
            (TProjection::Index { .. }, TProjection::Index { .. }) => true,
            _ => false,
        }
    }
    fn prefix(a: &[TProjection], b: &[TProjection]) -> bool {
        a.len() <= b.len() && a.iter().zip(b).all(|(x, y)| same_or_uncertain(x, y))
    }
    prefix(&a.path, &b.path) || prefix(&b.path, &a.path)
}

fn places_may_prefix(a: &TPlace, b: &TPlace) -> bool {
    if a.root != b.root || a.path.len() > b.path.len() {
        return false;
    }
    a.path
        .iter()
        .zip(&b.path)
        .all(|(left, right)| match (left, right) {
            (TProjection::Field(x), TProjection::Field(y)) => x == y,
            (
                TProjection::Index {
                    constant: Some(x), ..
                },
                TProjection::Index {
                    constant: Some(y), ..
                },
            ) => x == y,
            (TProjection::Index { .. }, TProjection::Index { .. }) => true,
            _ => false,
        })
}

fn places_proven_prefix(a: &TPlace, b: &TPlace) -> bool {
    if a.root != b.root || a.path.len() > b.path.len() {
        return false;
    }
    a.path
        .iter()
        .zip(&b.path)
        .all(|(left, right)| match (left, right) {
            (TProjection::Field(x), TProjection::Field(y)) => x == y,
            (
                TProjection::Index {
                    constant: Some(x), ..
                },
                TProjection::Index {
                    constant: Some(y), ..
                },
            ) => x == y,
            (
                TProjection::Index {
                    index:
                        TExpr {
                            kind: TExprKind::Local(x),
                            ..
                        },
                    ..
                },
                TProjection::Index {
                    index:
                        TExpr {
                            kind: TExprKind::Local(y),
                            ..
                        },
                    ..
                },
            ) => x == y,
            _ => false,
        })
}

fn place_field_path(place: &TPlace) -> Option<Vec<usize>> {
    place
        .path
        .iter()
        .map(|projection| match projection {
            TProjection::Field(index) => Some(*index),
            TProjection::Index { .. } => None,
        })
        .collect()
}

fn intersect_facts(
    a: &HashMap<(usize, Vec<usize>), (i128, i128)>,
    b: &HashMap<(usize, Vec<usize>), (i128, i128)>,
) -> HashMap<(usize, Vec<usize>), (i128, i128)> {
    a.iter()
        .filter_map(|(key, left)| {
            b.get(key)
                .map(|right| (key.clone(), (left.0.min(right.0), left.1.max(right.1))))
        })
        .collect()
}

fn reverse_comparison(op: BinaryOp) -> BinaryOp {
    match op {
        BinaryOp::Lt => BinaryOp::Gt,
        BinaryOp::Le => BinaryOp::Ge,
        BinaryOp::Gt => BinaryOp::Lt,
        BinaryOp::Ge => BinaryOp::Le,
        other => other,
    }
}

fn negate_comparison(op: BinaryOp) -> BinaryOp {
    match op {
        BinaryOp::Lt => BinaryOp::Ge,
        BinaryOp::Le => BinaryOp::Gt,
        BinaryOp::Gt => BinaryOp::Le,
        BinaryOp::Ge => BinaryOp::Lt,
        BinaryOp::Eq => BinaryOp::Ne,
        BinaryOp::Ne => BinaryOp::Eq,
        other => other,
    }
}

fn target_name(expr: &Expr) -> &str {
    match &expr.kind {
        ExprKind::Name(name) => name,
        ExprKind::Field { name, .. } => name,
        _ => "place",
    }
}

fn source_hint(expr: &Expr) -> String {
    match &expr.kind {
        ExprKind::Name(name) => name.clone(),
        ExprKind::Field { receiver, name, .. } => format!("{}.{}", source_hint(receiver), name),
        ExprKind::Integer {
            magnitude,
            negative,
            ..
        } => {
            if *negative {
                format!("-{magnitude}")
            } else {
                magnitude.to_string()
            }
        }
        _ => "value".to_owned(),
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
        TStmtKind::For { .. }
        | TStmtKind::ForEach { .. }
        | TStmtKind::Discard(_)
        | TStmtKind::Expect { .. } => true,
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
