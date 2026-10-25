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
struct FunctionValueUse {
    function: usize,
    function_ty: Ty,
    span: Span,
    sort_comparator: bool,
}

#[derive(Clone, Copy)]
struct IndirectCallSite {
    id: usize,
    from: usize,
    function_ty: Ty,
    span: Span,
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
    owner: Option<usize>,
    scope_depth: usize,
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
    package_capabilities: std::collections::HashSet<String>,
) -> Result<TProgram, CheckError> {
    Checker::new(programs, files, require_main, package_capabilities).run()
}

struct Checker {
    programs: Vec<Program>,
    files: Vec<String>,
    require_main: bool,
    package_capabilities: std::collections::HashSet<String>,
    signatures: HashMap<String, Signature>,
    function_signatures: HashMap<usize, Signature>,
    generic_functions: HashMap<String, Function>,
    generic_function_owner_placeholders: HashMap<(String, String), usize>,
    function_owner_substitutions: HashMap<usize, HashMap<String, usize>>,
    function_capacity_substitutions: HashMap<usize, HashMap<String, usize>>,
    current_generic_capacities: HashMap<String, usize>,
    generic_specializations: HashMap<(String, Vec<String>), usize>,
    capacity_instantiations: std::collections::HashSet<(String, Vec<usize>)>,
    types: Vec<TType>,
    type_ids: HashMap<String, Ty>,
    preferred_type_names: HashMap<Ty, String>,
    struct_decls: HashMap<Ty, StructDecl>,
    generic_struct_owners: HashMap<Ty, HashMap<String, usize>>,
    specialized_struct_base: HashMap<Ty, Ty>,
    specialized_struct_owners: HashMap<Ty, Vec<usize>>,
    struct_specialization_ids: HashMap<(Ty, Vec<usize>), Ty>,
    current_generic_owners: HashMap<String, usize>,
    owner_labels: HashMap<usize, String>,
    global_owner_paths: HashMap<String, usize>,
    owner_scope_depths: HashMap<usize, usize>,
    current_external_owners: std::collections::HashSet<usize>,
    next_owner: usize,
    pending_owner: Option<(String, usize)>,
    refinement_ids: HashMap<(Ty, i128, i128, RefinePolicy), Ty>,
    generic_ids: HashMap<(u8, Ty, Ty), Ty>,
    collection_ids: HashMap<(u8, Ty, usize), Ty>,
    grid_ids: HashMap<(Ty, usize, usize), Ty>,
    map_ids: HashMap<(Ty, Ty, usize), Ty>,
    set_ids: HashMap<(Ty, usize), Ty>,
    pool_ids: HashMap<(Ty, usize, usize), Ty>,
    id_ids: HashMap<usize, Ty>,
    function_type_ids: HashMap<(Vec<TFunctionTypeParam>, Ty, TFunctionEffects), Ty>,
    function_effect_spans: HashMap<(Ty, String), Span>,
    ast_functions: Vec<Function>,
    ast_tests: Vec<Test>,
    ast_constants: Vec<ConstDecl>,
    ast_globals: Vec<GlobalDecl>,
    constant_ids: HashMap<String, usize>,
    constant_types: Vec<Ty>,
    global_ids: HashMap<String, usize>,
    global_types: Vec<Option<Ty>>,
    checking_global_initializer: bool,
    checking_constant: bool,
    edges: Vec<Edge>,
    function_value_uses: Vec<FunctionValueUse>,
    indirect_calls: Vec<IndirectCallSite>,
    next_indirect_call: usize,
    sort_specializations: std::collections::HashSet<(Ty, usize)>,
    sort_scratch_specializations: std::collections::HashSet<(usize, Ty)>,
    suppress_function_value_effect_check: bool,
    locals: Vec<HashMap<String, Binding>>,
    scope_ids: Vec<usize>,
    next_scope: usize,
    next_local: usize,
    current_function: usize,
    current_return: Ty,
    current_is_test: bool,
    loop_depth: usize,
    loop_names: Vec<String>,
    loop_outer_depths: Vec<usize>,
    conditional_depth: usize,
    moved_locals: std::collections::HashSet<usize>,
    ascii_lengths: HashMap<usize, (usize, usize)>,
    facts: HashMap<(usize, Vec<usize>), (i128, i128)>,
    loop_writes: Vec<std::collections::HashSet<usize>>,
    active_views: Vec<TPlace>,
    view_bindings: HashMap<usize, TPlace>,
    collection_counts: HashMap<CollectionCountKey, usize>,
    loop_push_proofs: Vec<std::collections::HashSet<CollectionCountKey>>,
}

impl Checker {
    fn new(
        programs: Vec<Program>,
        files: Vec<String>,
        require_main: bool,
        package_capabilities: std::collections::HashSet<String>,
    ) -> Self {
        let mut checker = Self {
            programs,
            files,
            require_main,
            package_capabilities,
            signatures: HashMap::new(),
            function_signatures: HashMap::new(),
            generic_functions: HashMap::new(),
            generic_function_owner_placeholders: HashMap::new(),
            function_owner_substitutions: HashMap::new(),
            function_capacity_substitutions: HashMap::new(),
            current_generic_capacities: HashMap::new(),
            generic_specializations: HashMap::new(),
            capacity_instantiations: std::collections::HashSet::new(),
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
            generic_struct_owners: HashMap::new(),
            specialized_struct_base: HashMap::new(),
            specialized_struct_owners: HashMap::new(),
            struct_specialization_ids: HashMap::new(),
            current_generic_owners: HashMap::new(),
            owner_labels: HashMap::new(),
            global_owner_paths: HashMap::new(),
            owner_scope_depths: HashMap::new(),
            current_external_owners: std::collections::HashSet::new(),
            next_owner: 0,
            pending_owner: None,
            refinement_ids: HashMap::new(),
            generic_ids: HashMap::new(),
            collection_ids: HashMap::new(),
            grid_ids: HashMap::new(),
            map_ids: HashMap::new(),
            set_ids: HashMap::new(),
            pool_ids: HashMap::new(),
            id_ids: HashMap::new(),
            function_type_ids: HashMap::new(),
            function_effect_spans: HashMap::new(),
            ast_functions: Vec::new(),
            ast_tests: Vec::new(),
            ast_constants: Vec::new(),
            ast_globals: Vec::new(),
            constant_ids: HashMap::new(),
            constant_types: Vec::new(),
            global_ids: HashMap::new(),
            global_types: Vec::new(),
            checking_global_initializer: false,
            checking_constant: false,
            edges: Vec::new(),
            function_value_uses: Vec::new(),
            indirect_calls: Vec::new(),
            next_indirect_call: 0,
            sort_specializations: std::collections::HashSet::new(),
            sort_scratch_specializations: std::collections::HashSet::new(),
            suppress_function_value_effect_check: false,
            locals: Vec::new(),
            scope_ids: Vec::new(),
            next_scope: 0,
            next_local: 0,
            current_function: 0,
            current_return: Ty::Unit,
            current_is_test: false,
            loop_depth: 0,
            loop_names: Vec::new(),
            loop_outer_depths: Vec::new(),
            conditional_depth: 0,
            moved_locals: std::collections::HashSet::new(),
            ascii_lengths: HashMap::new(),
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
        let byte_ty = Ty(checker.types.len());
        checker.types.push(TType {
            name: "byte".to_owned(),
            kind: TTypeKind::Refinement {
                base: Ty::Int,
                min: 0,
                max: 255,
                policy: RefinePolicy::Checked,
            },
            span: Span::default(),
        });
        checker.type_ids.insert("byte".to_owned(), byte_ty);
        let io_error_ty = Ty(checker.types.len());
        checker.types.push(TType {
            name: "IoError".to_owned(),
            kind: TTypeKind::Enum(vec![
                TCase {
                    name: "NotFound".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "NoPermission".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "TooLarge".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "TooMany".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "NameTooLong".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "BadPath".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "Outside".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "Other".to_owned(),
                    payload: vec![Ty::Int],
                    span: Span::default(),
                },
            ]),
            span: Span::default(),
        });
        checker.type_ids.insert("IoError".to_owned(), io_error_ty);
        let file_kind_ty = Ty(checker.types.len());
        checker.types.push(TType {
            name: "FileKind".to_owned(),
            kind: TTypeKind::Enum(vec![
                TCase {
                    name: "File".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "Directory".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
                TCase {
                    name: "Other".to_owned(),
                    payload: Vec::new(),
                    span: Span::default(),
                },
            ]),
            span: Span::default(),
        });
        checker.type_ids.insert("FileKind".to_owned(), file_kind_ty);
        for (name, capability) in [
            ("Env", CapabilityKind::Env),
            ("Fs", CapabilityKind::Fs),
            ("Out", CapabilityKind::Out),
            ("Arg", CapabilityKind::Arg),
            ("Args", CapabilityKind::Args),
        ] {
            let ty = Ty(checker.types.len());
            checker.types.push(TType {
                name: name.to_owned(),
                kind: TTypeKind::Capability(capability),
                span: Span::default(),
            });
            checker.type_ids.insert(name.to_owned(), ty);
        }
        let path_ty = Ty(checker.types.len());
        checker.types.push(TType {
            name: "Path".to_owned(),
            kind: TTypeKind::List {
                element: byte_ty,
                capacity: 4096,
            },
            span: Span::default(),
        });
        checker.type_ids.insert("Path".to_owned(), path_ty);
        let dir_entry_ty = Ty(checker.types.len());
        checker.types.push(TType {
            name: "DirEntry".to_owned(),
            kind: TTypeKind::Struct(vec![
                TField {
                    name: "name".to_owned(),
                    ty: path_ty,
                },
                TField {
                    name: "kind".to_owned(),
                    ty: file_kind_ty,
                },
            ]),
            span: Span::default(),
        });
        checker.type_ids.insert("DirEntry".to_owned(), dir_entry_ty);
        checker
    }

    fn run(mut self) -> Result<TProgram, CheckError> {
        self.register_type_names()?;
        self.fill_type_aliases()?;
        self.fill_enum_cases()?;
        self.fill_struct_fields()?;
        self.register_globals()?;
        self.check_recursive_value_types()?;
        self.check_all_type_sizes()?;
        for program in self.programs.clone() {
            for constant in program.constants {
                if self.constant_ids.contains_key(&constant.name)
                    || self.global_ids.contains_key(&constant.name)
                {
                    return Err(CheckError {
                        span: constant.span,
                        message: format!("constant '{}' is declared more than once", constant.name),
                    });
                }
                let id = self.ast_constants.len();
                let saved_pending = self.pending_owner.take();
                if constant.ty.name == "pool" {
                    let owner = self.fresh_owner(constant.name.clone());
                    self.pending_owner = Some((constant.name.clone(), owner));
                }
                let ty = self.parse_type(&constant.ty)?;
                self.pending_owner = saved_pending;
                if self.type_contains_capability(ty) {
                    return Err(CheckError { span: constant.ty.span, message: "capabilities cannot be stored in constants; receive them through parameters".to_owned() });
                }
                if self.type_contains_pool(ty) {
                    return Err(CheckError {
                        span: constant.ty.span,
                        message: "pool-containing constants are not supported; use a local pool while evaluating a constant function".to_owned(),
                    });
                }
                self.constant_ids.insert(constant.name.clone(), id);
                self.constant_types.push(ty);
                self.ast_constants.push(constant);
            }
        }
        let mut test_names = HashMap::<String, Span>::new();
        for p in self.programs.clone() {
            for function in p.functions {
                let id = self.ast_functions.len();
                if matches!(
                    function.name.as_str(),
                    "print" | "min" | "max" | "sort" | "sort_by" | "binary_search"
                ) {
                    return Err(CheckError {
                        span: function.span,
                        message: format!(
                            "'{}' is a built-in function name and cannot be redeclared",
                            function.name
                        )
                        .to_owned(),
                    });
                }
                if self.global_ids.contains_key(&function.name)
                    || self.constant_ids.contains_key(&function.name)
                {
                    return Err(CheckError {
                        span: function.span,
                        message: format!(
                            "function '{}' conflicts with a global or constant; choose a unique value name",
                            function.name
                        ),
                    });
                }
                if self.signatures.contains_key(&function.name)
                    || self.generic_functions.contains_key(&function.name)
                {
                    return Err(CheckError {
                        span: function.span,
                        message: format!("function '{}' is declared more than once", function.name),
                    });
                }
                if !function.generic_params.is_empty() {
                    self.generic_functions
                        .insert(function.name.clone(), function);
                    continue;
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
                let signature = Signature { id, params, result };
                self.signatures
                    .insert(function.name.clone(), signature.clone());
                self.function_signatures.insert(id, signature);
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
        let mut global_init_exprs = Vec::with_capacity(self.ast_globals.len());
        for id in 0..self.ast_globals.len() {
            global_init_exprs.push(self.check_global_initializer(id)?);
        }
        let mut functions = Vec::with_capacity(self.ast_functions.len() + self.ast_tests.len());
        let mut id = 0;
        while id < self.ast_functions.len() {
            functions.push(self.check_function(id)?);
            id += 1;
        }
        let mut tests = Vec::with_capacity(self.ast_tests.len());
        for index in 0..self.ast_tests.len() {
            let (function, test) = self.check_test(index)?;
            tests.push(test);
            functions.push(function);
        }
        let mut constant_exprs = Vec::with_capacity(self.ast_constants.len());
        for id in 0..self.ast_constants.len() {
            constant_exprs.push(self.check_constant_expr(id)?);
        }
        self.validate_function_effect_paths()?;
        let mut direct_call_graph = vec![Vec::new(); functions.len()];
        for edge in &self.edges {
            direct_call_graph[edge.from].push(TCallEdge {
                target: edge.to,
                span: edge.span,
            });
        }
        let (call_graph, indirect_targets) =
            self.resolve_indirect_calls(&functions, direct_call_graph)?;
        self.check_recursion(&call_graph, &functions)?;
        self.check_recursive_regions(&functions, &call_graph)?;
        let constants = crate::const_eval::evaluate_constants(
            &constant_exprs,
            &functions,
            &call_graph,
            &self.types,
        )?;
        let globals =
            self.finish_globals(global_init_exprs, &constants, &functions, &call_graph)?;
        let global_init_order =
            self.global_initialization_order(&globals, &functions, &call_graph)?;
        self.check_global_access_contracts(&functions, &call_graph, &indirect_targets)?;
        let (globals, global_state_bytes) = self.layout_globals(globals)?;
        let mut function_type_targets = vec![Vec::new(); self.types.len()];
        for usage in &self.function_value_uses {
            let targets = &mut function_type_targets[usage.function_ty.0];
            if !targets.contains(&usage.function) {
                targets.push(usage.function);
            }
        }
        for site in &self.indirect_calls {
            if let Some(candidates) = indirect_targets.get(&site.id) {
                let targets = &mut function_type_targets[site.function_ty.0];
                for candidate in candidates {
                    if !targets.contains(candidate) {
                        targets.push(*candidate);
                    }
                }
            }
        }
        let typed = TProgram {
            functions,
            tests,
            constants,
            globals,
            global_init_order,
            global_state_bytes,
            job_headroom_bytes: 256 * 1024 * 1024,
            globals_budget_bytes: 64 * 1024 * 1024,
            recursion_budget_bytes: 0,
            capabilities: {
                let mut capabilities = self
                    .package_capabilities
                    .iter()
                    .cloned()
                    .collect::<Vec<_>>();
                capabilities.sort();
                capabilities
            },
            files: self.files,
            call_graph,
            function_type_targets,
            types: self.types,
        };
        Ok(typed)
    }

    fn check_constant_expr(&mut self, id: usize) -> Result<TConstExpr, CheckError> {
        let declaration = self.ast_constants[id].clone();
        self.current_function = 0;
        self.current_return = self.constant_types[id];
        self.current_is_test = false;
        self.checking_constant = true;
        self.loop_depth = 0;
        self.loop_names.clear();
        self.loop_outer_depths.clear();
        self.conditional_depth = 0;
        self.moved_locals.clear();
        self.ascii_lengths.clear();
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
                    "int" | "long" | "bool" | "Ascii" | "Option" | "Result" | "Full"
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
            let saved_generic_owners = self.current_generic_owners.clone();
            let mut generic_owners = HashMap::new();
            for parameter in &declaration.generic_params {
                let owner = self.fresh_owner(format!("{}.{}", declaration.name, parameter));
                generic_owners.insert(parameter.clone(), owner);
            }
            if !generic_owners.is_empty() {
                self.generic_struct_owners
                    .insert(ty, generic_owners.clone());
            }
            self.current_generic_owners = generic_owners;
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
                let old_pending = self.pending_owner.take();
                if old_pending.is_none() {
                    let owner = self.fresh_owner(format!("{}.{}", declaration.name, field.name));
                    self.pending_owner =
                        Some((format!("{}.{}", declaration.name, field.name), owner));
                } else {
                    self.pending_owner = old_pending.clone();
                }
                let field_ty = self.parse_type(&field.ty);
                self.pending_owner = old_pending;
                fields.push(TField {
                    name: field.name.clone(),
                    ty: field_ty?,
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
            self.current_generic_owners = saved_generic_owners;
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
                    "int" | "long" | "bool" | "Ascii" | "Option" | "Result" | "Full"
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
        if ty.name == "Id" && ty.args.len() == 1 && ty.const_args.is_empty() {
            let owner = self.owner_from_ast(&ty.args[0])?;
            if ty.range.is_some() {
                return Err(CheckError {
                    span: ty.span,
                    message: "ids cannot be range refined".to_owned(),
                });
            }
            return Ok(self.intern_id(owner, ty.span));
        }
        if ty.name.ends_with(".Id") && ty.args.is_empty() && ty.const_args.is_empty() {
            let owner_path = ty.name.strip_suffix(".Id").unwrap_or(&ty.name);
            let owner = self.resolve_owner_path(owner_path, ty.span)?;
            return Ok(self.intern_id(owner, ty.span));
        }
        let mut result = if let Some(function) = &ty.function {
            self.parse_function_type(function)?
        } else {
            match ty.name.as_str() {
                "Ascii" if ty.args.is_empty() && ty.const_args.len() == 1 && ty.range.is_none() => {
                    let raw_max = self.capacity_value(&ty.const_args[0])?;
                    if raw_max < 0 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: "Ascii maximum cannot be negative; use zero or a positive byte count".to_owned(),
                        });
                    }
                    if raw_max > i64::MAX as i128 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: "Ascii maximum overflows long; reduce the byte count"
                                .to_owned(),
                        });
                    }
                    self.intern_ascii(raw_max as usize, ty.span)
                }
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
                "Option"
                    if ty.args.len() == 1 && ty.const_args.is_empty() && ty.range.is_none() =>
                {
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
                "Result"
                    if ty.args.len() == 2 && ty.const_args.is_empty() && ty.range.is_none() =>
                {
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
                    if self.type_contains_pool(element) {
                        return Err(CheckError {
                        span: ty.args[0].span,
                        message: "pools cannot appear inside array or list elements; each repeated element would need a distinct owner".to_owned(),
                    });
                    }
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
                "queue" | "ring"
                    if ty.args.len() == 1 && ty.const_args.len() == 1 && ty.range.is_none() =>
                {
                    let element = self.parse_type(&ty.args[0])?;
                    if self.type_contains_pool(element) {
                        return Err(CheckError {
                        span: ty.args[0].span,
                        message: "pools cannot appear inside queue or ring elements; each repeated element would need a distinct owner".to_owned(),
                    });
                    }
                    let raw_capacity = self.capacity_value(&ty.const_args[0])?;
                    if raw_capacity < 0 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: format!(
                                "{} capacity cannot be negative; use zero or a positive constant",
                                ty.name
                            ),
                        });
                    }
                    if raw_capacity > i64::MAX as i128 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: "collection size overflows long; reduce a capacity".to_owned(),
                        });
                    }
                    let capacity = usize::try_from(raw_capacity).map_err(|_| CheckError {
                        span: ty.const_args[0].span,
                        message: "collection size overflows long; reduce a capacity".to_owned(),
                    })?;
                    self.intern_collection(
                        if ty.name == "queue" { 2 } else { 3 },
                        element,
                        capacity,
                        format!("{}<{}, {}>", ty.name, self.type_name(element), capacity),
                        ty.span,
                    )
                }
                "grid" if ty.args.len() == 1 && ty.const_args.len() == 2 && ty.range.is_none() => {
                    let element = self.parse_type(&ty.args[0])?;
                    if self.type_contains_pool(element) {
                        return Err(CheckError {
                        span: ty.args[0].span,
                        message: "pools cannot appear inside grid cells; each repeated cell would need a distinct owner".to_owned(),
                    });
                    }
                    let width = self.capacity_value(&ty.const_args[0])?;
                    let height = self.capacity_value(&ty.const_args[1])?;
                    if width < 0 || height < 0 {
                        return Err(CheckError {
                        span: if width < 0 {
                            ty.const_args[0].span
                        } else {
                            ty.const_args[1].span
                        },
                        message:
                            "grid dimensions cannot be negative; use zero or a positive constant"
                                .to_owned(),
                    });
                    }
                    if width > i64::MAX as i128 || height > i64::MAX as i128 {
                        return Err(CheckError {
                            span: if width > i64::MAX as i128 {
                                ty.const_args[0].span
                            } else {
                                ty.const_args[1].span
                            },
                            message: "grid dimensions overflow long; reduce a dimension".to_owned(),
                        });
                    }
                    let capacity = width.checked_mul(height).ok_or_else(|| CheckError {
                        span: ty.span,
                        message: "grid size product overflows long; reduce its dimensions"
                            .to_owned(),
                    })?;
                    if capacity > i64::MAX as i128 {
                        return Err(CheckError {
                            span: ty.span,
                            message: "grid size product overflows long; reduce its dimensions"
                                .to_owned(),
                        });
                    }
                    let width = usize::try_from(width).map_err(|_| CheckError {
                        span: ty.const_args[0].span,
                        message: "grid dimensions overflow long; reduce a dimension".to_owned(),
                    })?;
                    let height = usize::try_from(height).map_err(|_| CheckError {
                        span: ty.const_args[1].span,
                        message: "grid dimensions overflow long; reduce a dimension".to_owned(),
                    })?;
                    let capacity = usize::try_from(capacity).map_err(|_| CheckError {
                        span: ty.span,
                        message: "grid size product overflows long; reduce its dimensions"
                            .to_owned(),
                    })?;
                    self.intern_grid(element, width, height, capacity, ty.span)
                }
                "map" if ty.args.len() == 2 && ty.const_args.len() == 1 && ty.range.is_none() => {
                    let key = self.parse_type(&ty.args[0])?;
                    let value = self.parse_type(&ty.args[1])?;
                    if self.type_contains_pool(key) || self.type_contains_pool(value) {
                        return Err(CheckError {
                        span: ty.span,
                        message: "pools cannot appear in map keys or values; store ids instead and keep their pool alive".to_owned(),
                    });
                    }
                    if !self.type_is_hashable(key, &mut std::collections::HashSet::new()) {
                        return Err(CheckError {
                            span: ty.args[0].span,
                            message: format!(
                                "map key type '{}' is not hashable; use Ascii, integers, bool, enums, ids, or structs built from those types",
                                self.type_name(key)
                            ),
                        });
                    }
                    let raw_capacity = self.capacity_value(&ty.const_args[0])?;
                    if raw_capacity < 0 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message:
                                "map capacity cannot be negative; use zero or a positive constant"
                                    .to_owned(),
                        });
                    }
                    if raw_capacity > i64::MAX as i128 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: "collection size overflows long; reduce a capacity".to_owned(),
                        });
                    }
                    let capacity = usize::try_from(raw_capacity).map_err(|_| CheckError {
                        span: ty.const_args[0].span,
                        message: "collection size overflows long; reduce a capacity".to_owned(),
                    })?;
                    self.intern_map(key, value, capacity, ty.span)
                }
                "set" if ty.args.len() == 1 && ty.const_args.len() == 1 && ty.range.is_none() => {
                    let key = self.parse_type(&ty.args[0])?;
                    if self.type_contains_pool(key) {
                        return Err(CheckError {
                        span: ty.span,
                        message: "pools cannot appear in set elements; store ids instead and keep their pool alive".to_owned(),
                    });
                    }
                    if !self.type_is_hashable(key, &mut std::collections::HashSet::new()) {
                        return Err(CheckError {
                            span: ty.args[0].span,
                            message: format!(
                                "set element type '{}' is not hashable; use Ascii, integers, bool, enums, ids, or structs built from those types",
                                self.type_name(key)
                            ),
                        });
                    }
                    let raw_capacity = self.capacity_value(&ty.const_args[0])?;
                    if raw_capacity < 0 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message:
                                "set capacity cannot be negative; use zero or a positive constant"
                                    .to_owned(),
                        });
                    }
                    if raw_capacity > i64::MAX as i128 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: "collection size overflows long; reduce a capacity".to_owned(),
                        });
                    }
                    let capacity = usize::try_from(raw_capacity).map_err(|_| CheckError {
                        span: ty.const_args[0].span,
                        message: "collection size overflows long; reduce a capacity".to_owned(),
                    })?;
                    self.intern_set(key, capacity, ty.span)
                }
                "pool"
                    if (ty.args.len() == 1 || ty.args.len() == 2)
                        && ty.const_args.len() == 1
                        && ty.range.is_none() =>
                {
                    let element = self.parse_type(&ty.args[0])?;
                    if self.type_contains_pool(element) {
                        return Err(CheckError {
                        span: ty.args[0].span,
                        message: "a pool element cannot itself contain a pool; fixed slots cannot give nested pools distinct owners".to_owned(),
                    });
                    }
                    let capacity = self.capacity_value(&ty.const_args[0])?;
                    if capacity < 0 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message:
                                "pool capacity cannot be negative; use zero or a positive constant"
                                    .to_owned(),
                        });
                    }
                    if capacity > i64::MAX as i128 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message: "collection size overflows long; reduce a capacity".to_owned(),
                        });
                    }
                    if capacity > (u32::MAX as i128) + 1 {
                        return Err(CheckError {
                            span: ty.const_args[0].span,
                            message:
                                "pool capacity exceeds the 32-bit slot limit; reduce the capacity"
                                    .to_owned(),
                        });
                    }
                    let capacity = usize::try_from(capacity).map_err(|_| CheckError {
                        span: ty.const_args[0].span,
                        message: "collection size overflows long; reduce a capacity".to_owned(),
                    })?;
                    let owner = if ty.args.len() == 2 {
                        self.owner_from_ast(&ty.args[1])?
                    } else if let Some((_, owner)) = &self.pending_owner {
                        *owner
                    } else {
                        return Err(CheckError {
                        span: ty.span,
                        message: "a pool type needs an owner; declare it as a named local or write the owner parameter as the third type argument"
                            .to_owned(),
                    });
                    };
                    self.intern_pool(element, capacity, owner, ty.span)
                }
                name if !ty.args.is_empty() && ty.const_args.is_empty() && ty.range.is_none() => {
                    let Some(base) = self.type_ids.get(name).copied() else {
                        return Err(CheckError {
                            span: ty.span,
                            message: format!("unknown type '{}'; declare it with struct", name),
                        });
                    };
                    self.instantiate_generic_struct(base, &ty.args, ty.span)?
                }
                "Option" | "Result" | "list" | "map" | "set" | "pool" => {
                    return Err(CheckError {
                    span: ty.span,
                    message: match ty.name.as_str() {
                        "list" => {
                            "list types use list<T, capacity>; the capacity must be a constant"
                                .to_owned()
                        }
                        "map" => "map types use map<K, V, capacity>; the capacity must be a constant".to_owned(),
                        "set" => "set types use set<K, capacity>; the capacity must be a constant".to_owned(),
                        "pool" => {
                            "pool types use pool<T, capacity> or pool<T, capacity, P>; the capacity must be a constant"
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
            }
        };
        for cap_expr in &ty.array_caps {
            if self.type_contains_pool(result) {
                return Err(CheckError {
                    span: cap_expr.span,
                    message: "pools cannot appear inside array or list elements; each repeated element would need a distinct owner".to_owned(),
                });
            }
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
        if self.type_contains_capability(result)
            && !matches!(self.types[result.0].kind, TTypeKind::Capability(_))
        {
            return Err(CheckError {
                span: ty.span,
                message: "capabilities cannot be stored in structs, enums, or collections; pass them as parameters and keep them in locals".to_owned(),
            });
        }
        Ok(result)
    }

    fn parse_function_type(&mut self, function: &FunctionTypeAst) -> Result<Ty, CheckError> {
        let params = function
            .params
            .iter()
            .map(|param| {
                let ty = self.parse_type(&param.ty)?;
                if param.mode == ParamMode::Grow && !self.is_ascii(ty) {
                    return Err(CheckError {
                        span: param.span,
                        message: "grow parameters are for Ascii builders; use read or write for other types".to_owned(),
                    });
                }
                Ok(TFunctionTypeParam {
                    ty,
                    mode: param.mode,
                })
            })
            .collect::<Result<Vec<_>, CheckError>>()?;
        let result = function
            .result
            .as_deref()
            .map(|result| self.parse_type(result))
            .transpose()?
            .unwrap_or(Ty::Unit);
        if self.type_contains_pool(result) {
            return Err(CheckError {
                span: function
                    .result
                    .as_ref()
                    .map(|result| result.span)
                    .unwrap_or(function.span),
                message: "a function value cannot return a value containing a pool; pool owners cannot escape a function".to_owned(),
            });
        }
        let mut effects = TFunctionEffects::default();
        let mut effect_path_spans = Vec::new();
        for effect in &function.effects {
            match effect {
                FunctionEffectAst::Out { .. } => effects.out = true,
                FunctionEffectAst::Env { .. } => effects.env = true,
                FunctionEffectAst::FsRead { .. } => effects.fs_read = true,
                FunctionEffectAst::FsWrite { .. } => effects.fs_write = true,
                FunctionEffectAst::Reads { path, span, .. } => {
                    if !effects.reads.contains(path) {
                        effects.reads.push(path.clone());
                    }
                    effect_path_spans.push((path.clone(), *span));
                }
                FunctionEffectAst::Writes { path, span, .. } => {
                    if !effects.writes.contains(path) {
                        effects.writes.push(path.clone());
                    }
                    effect_path_spans.push((path.clone(), *span));
                }
            }
        }
        effects.reads.sort();
        effects.writes.sort();
        let ty = self.intern_function_type(params, result, effects, function.span);
        for (path, span) in effect_path_spans {
            self.function_effect_spans.entry((ty, path)).or_insert(span);
        }
        Ok(ty)
    }

    fn intern_function_type(
        &mut self,
        params: Vec<TFunctionTypeParam>,
        result: Ty,
        effects: TFunctionEffects,
        span: Span,
    ) -> Ty {
        let key = (params.clone(), result, effects.clone());
        if let Some(ty) = self.function_type_ids.get(&key) {
            return *ty;
        }
        let params_text = params
            .iter()
            .map(|param| {
                format!(
                    "{}{}",
                    match param.mode {
                        ParamMode::Read => "",
                        ParamMode::Write => "write ",
                        ParamMode::Grow => "grow ",
                    },
                    self.type_name(param.ty)
                )
            })
            .collect::<Vec<_>>()
            .join(", ");
        let mut effect_text = Vec::new();
        if effects.out {
            effect_text.push("out".to_owned());
        }
        if effects.env {
            effect_text.push("env".to_owned());
        }
        if effects.fs_read {
            effect_text.push("fs.read".to_owned());
        }
        if effects.fs_write {
            effect_text.push("fs.write".to_owned());
        }
        effect_text.extend(effects.reads.iter().map(|path| format!("reads {path}")));
        effect_text.extend(effects.writes.iter().map(|path| format!("writes {path}")));
        let suffix = if effect_text.is_empty() {
            String::new()
        } else {
            format!(" effects {}", effect_text.join(", "))
        };
        let id = Ty(self.types.len());
        let supports_append = self.is_ascii(result)
            || matches!(
                self.types.get(result.0).map(|definition| &definition.kind),
                Some(TTypeKind::Result(ok, _)) if self.is_ascii(*ok)
            );
        self.types.push(TType {
            name: format!("fn({params_text}) -> {}{suffix}", self.type_name(result)),
            kind: TTypeKind::Function {
                params,
                result,
                supports_append,
                effects,
                data_stack_requirement: 0,
            },
            span,
        });
        self.function_type_ids.insert(key, id);
        id
    }

    fn fresh_owner(&mut self, label: impl Into<String>) -> usize {
        let id = self.next_owner;
        self.next_owner += 1;
        self.owner_labels.insert(id, label.into());
        id
    }

    fn localize_embedded_pool_owners(
        &mut self,
        ty: Ty,
        root_name: &str,
        span: Span,
    ) -> Result<Ty, CheckError> {
        fn collect(
            checker: &Checker,
            ty: Ty,
            path: &mut Vec<String>,
            active: &mut std::collections::HashSet<Ty>,
            owners: &mut Vec<(usize, String)>,
        ) {
            if !active.insert(ty) {
                return;
            }
            match &checker.types[ty.0].kind {
                TTypeKind::Pool { owner, .. } => {
                    owners.push((*owner, path.join(".")));
                }
                TTypeKind::Struct(fields) => {
                    for field in fields {
                        path.push(field.name.clone());
                        collect(checker, field.ty, path, active, owners);
                        path.pop();
                    }
                }
                TTypeKind::Option(inner) => collect(checker, *inner, path, active, owners),
                TTypeKind::Result(ok, err) => {
                    collect(checker, *ok, path, active, owners);
                    collect(checker, *err, path, active, owners);
                }
                TTypeKind::Enum(cases) => {
                    for case in cases {
                        for payload in &case.payload {
                            collect(checker, *payload, path, active, owners);
                        }
                    }
                }
                TTypeKind::Array { .. } | TTypeKind::List { .. } => {}
                _ => {}
            }
            active.remove(&ty);
        }

        let mut declarations = Vec::new();
        collect(
            self,
            ty,
            &mut Vec::new(),
            &mut std::collections::HashSet::new(),
            &mut declarations,
        );
        let generic_owners = self
            .generic_struct_owners
            .values()
            .flat_map(|owners| owners.values().copied())
            .chain(self.current_generic_owners.values().copied())
            .chain(self.global_owner_paths.values().copied())
            .collect::<std::collections::HashSet<_>>();
        let mut substitutions = HashMap::new();
        for (old, path) in declarations {
            if generic_owners.contains(&old) || substitutions.contains_key(&old) {
                continue;
            }
            let field_path = if path.is_empty() {
                root_name.to_owned()
            } else {
                format!("{root_name}.{path}")
            };
            let owner = self.fresh_owner(field_path);
            self.owner_scope_depths
                .insert(owner, self.scope_ids.len().saturating_sub(1));
            if self.global_ids.contains_key(root_name) {
                let field_path = if path.is_empty() {
                    root_name.to_owned()
                } else {
                    format!("{root_name}.{path}")
                };
                self.global_owner_paths.insert(field_path, owner);
            }
            substitutions.insert(old, owner);
        }
        if substitutions.is_empty() {
            return Ok(ty);
        }
        let mut memo = HashMap::new();
        self.substitute_owner_type(ty, &substitutions, &mut memo, span)
    }

    fn type_contains_pool(&self, ty: Ty) -> bool {
        fn visit(checker: &Checker, ty: Ty, seen: &mut std::collections::HashSet<Ty>) -> bool {
            if !seen.insert(ty) {
                return false;
            }
            match &checker.types[ty.0].kind {
                TTypeKind::Pool { .. } => true,
                TTypeKind::Struct(fields) => {
                    fields.iter().any(|field| visit(checker, field.ty, seen))
                }
                TTypeKind::Enum(cases) => cases
                    .iter()
                    .flat_map(|case| case.payload.iter())
                    .any(|ty| visit(checker, *ty, seen)),
                TTypeKind::Option(inner) => visit(checker, *inner, seen),
                TTypeKind::Result(ok, err) => {
                    visit(checker, *ok, seen) || visit(checker, *err, seen)
                }
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. } => visit(checker, *element, seen),
                TTypeKind::Map { key, value, .. } => {
                    visit(checker, *key, seen) || visit(checker, *value, seen)
                }
                TTypeKind::Set { key, .. } => visit(checker, *key, seen),
                _ => false,
            }
        }
        visit(self, ty, &mut std::collections::HashSet::new())
    }

    fn type_contains_ascii(&self, ty: Ty) -> bool {
        fn visit(checker: &Checker, ty: Ty, seen: &mut std::collections::HashSet<Ty>) -> bool {
            if !seen.insert(ty) {
                return false;
            }
            match &checker.types[ty.0].kind {
                TTypeKind::Ascii { .. } => true,
                TTypeKind::Struct(fields) => {
                    fields.iter().any(|field| visit(checker, field.ty, seen))
                }
                TTypeKind::Enum(cases) => cases
                    .iter()
                    .flat_map(|case| case.payload.iter())
                    .any(|ty| visit(checker, *ty, seen)),
                TTypeKind::Option(inner) => visit(checker, *inner, seen),
                TTypeKind::Result(ok, err) => {
                    visit(checker, *ok, seen) || visit(checker, *err, seen)
                }
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. }
                | TTypeKind::Pool { element, .. } => visit(checker, *element, seen),
                TTypeKind::Map { key, value, .. } => {
                    visit(checker, *key, seen) || visit(checker, *value, seen)
                }
                TTypeKind::Set { key, .. } => visit(checker, *key, seen),
                _ => false,
            }
        }
        visit(self, ty, &mut std::collections::HashSet::new())
    }

    fn type_contains_capability(&self, ty: Ty) -> bool {
        fn visit(checker: &Checker, ty: Ty, seen: &mut std::collections::HashSet<Ty>) -> bool {
            if !seen.insert(ty) {
                return false;
            }
            match &checker.types[ty.0].kind {
                TTypeKind::Capability(_) => true,
                TTypeKind::Struct(fields) => {
                    fields.iter().any(|field| visit(checker, field.ty, seen))
                }
                TTypeKind::Enum(cases) => cases
                    .iter()
                    .flat_map(|case| &case.payload)
                    .any(|ty| visit(checker, *ty, seen)),
                TTypeKind::Option(inner) => visit(checker, *inner, seen),
                TTypeKind::Result(ok, err) => {
                    visit(checker, *ok, seen) || visit(checker, *err, seen)
                }
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. }
                | TTypeKind::Pool { element, .. } => visit(checker, *element, seen),
                TTypeKind::Map { key, value, .. } => {
                    visit(checker, *key, seen) || visit(checker, *value, seen)
                }
                TTypeKind::Set { key, .. } => visit(checker, *key, seen),
                _ => false,
            }
        }
        visit(self, ty, &mut std::collections::HashSet::new())
    }

    fn owners_in_type(&self, ty: Ty) -> std::collections::HashSet<usize> {
        fn visit(
            checker: &Checker,
            ty: Ty,
            seen: &mut std::collections::HashSet<Ty>,
            owners: &mut std::collections::HashSet<usize>,
        ) {
            if !seen.insert(ty) {
                return;
            }
            match &checker.types[ty.0].kind {
                TTypeKind::Id { owner } => {
                    owners.insert(*owner);
                }
                TTypeKind::Pool { element, owner, .. } => {
                    owners.insert(*owner);
                    visit(checker, *element, seen, owners);
                }
                TTypeKind::Struct(fields) => {
                    for field in fields {
                        visit(checker, field.ty, seen, owners);
                    }
                }
                TTypeKind::Enum(cases) => {
                    for case in cases {
                        for payload in &case.payload {
                            visit(checker, *payload, seen, owners);
                        }
                    }
                }
                TTypeKind::Option(inner) => visit(checker, *inner, seen, owners),
                TTypeKind::Result(ok, err) => {
                    visit(checker, *ok, seen, owners);
                    visit(checker, *err, seen, owners);
                }
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. } => visit(checker, *element, seen, owners),
                TTypeKind::Map { key, value, .. } => {
                    visit(checker, *key, seen, owners);
                    visit(checker, *value, seen, owners);
                }
                TTypeKind::Set { key, .. } => visit(checker, *key, seen, owners),
                TTypeKind::Function { params, result, .. } => {
                    for param in params {
                        visit(checker, param.ty, seen, owners);
                    }
                    visit(checker, *result, seen, owners);
                }
                _ => {}
            }
        }
        let mut owners = std::collections::HashSet::new();
        visit(self, ty, &mut std::collections::HashSet::new(), &mut owners);
        owners
    }

    fn fresh_pool_value(&self, value: &TExpr) -> bool {
        if !self.type_contains_pool(value.ty) {
            return true;
        }
        match &value.kind {
            TExprKind::EmptyPool => true,
            TExprKind::StructConstruct { fields } => fields.iter().all(|(_, field)| {
                !self.type_contains_pool(field.ty) || self.fresh_pool_value(field)
            }),
            TExprKind::Construct { args, .. } => args
                .iter()
                .all(|field| !self.type_contains_pool(field.ty) || self.fresh_pool_value(field)),
            _ => false,
        }
    }

    fn check_owner_lifetime(
        &self,
        ty: Ty,
        destination_depth: Option<usize>,
        span: Span,
    ) -> Result<(), CheckError> {
        for owner in self.owners_in_type(ty) {
            if self.current_external_owners.contains(&owner) {
                continue;
            }
            let owner_depth = self.owner_scope_depths.get(&owner).copied().unwrap_or(0);
            if destination_depth.is_none_or(|depth| owner_depth > depth) {
                let label = self
                    .owner_labels
                    .get(&owner)
                    .map(String::as_str)
                    .unwrap_or("local pool");
                return Err(CheckError {
                    span,
                    message: format!(
                        "pool owner '{}' does not live long enough for this value; ids cannot outlive their pool",
                        label
                    ),
                });
            }
        }
        Ok(())
    }

    fn owner_from_ast(&self, owner_ast: &TypeAst) -> Result<usize, CheckError> {
        self.resolve_owner_path(&owner_ast.name, owner_ast.span)
    }

    fn resolve_owner_path(&self, path: &str, span: Span) -> Result<usize, CheckError> {
        if let Some(owner) = self.global_owner_paths.get(path) {
            return Ok(*owner);
        }
        if let Some(owner) = self.current_generic_owners.get(path) {
            return Ok(*owner);
        }
        if let Some((name, owner)) = &self.pending_owner {
            if name == path || name.rsplit('.').next() == Some(path) {
                return Ok(*owner);
            }
        }
        if !path.contains('.') {
            if let Some(binding) = self.find_binding(path) {
                if let Some(owner) = binding.owner {
                    return Ok(owner);
                }
            }
        } else {
            let mut parts = path.split('.');
            if let Some(root) = parts.next() {
                let root_ty = self
                    .find_binding(root)
                    .map(|binding| binding.ty)
                    .or_else(|| {
                        self.global_ids
                            .get(root)
                            .and_then(|id| self.global_types.get(*id))
                            .and_then(|ty| *ty)
                    });
                if let Some(mut ty) = root_ty {
                    for part in parts {
                        let TTypeKind::Struct(fields) = &self.types[ty.0].kind else {
                            return Err(CheckError {
                                span,
                                message: format!("'{}' is not a pool owner path", path),
                            });
                        };
                        let Some(field) = fields.iter().find(|field| field.name == part) else {
                            return Err(CheckError {
                                span,
                                message: format!(
                                    "unknown owner path '{}'; check the field name",
                                    path
                                ),
                            });
                        };
                        ty = field.ty;
                    }
                    if let TTypeKind::Pool { owner, .. } = self.types[ty.0].kind {
                        return Ok(owner);
                    }
                }
            }
        }
        Err(CheckError {
            span,
            message: format!(
                "unknown pool owner '{}'; use a pool name or owner parameter",
                path
            ),
        })
    }

    fn intern_id(&mut self, owner: usize, span: Span) -> Ty {
        if let Some(ty) = self.id_ids.get(&owner) {
            return *ty;
        }
        let label = self
            .owner_labels
            .get(&owner)
            .cloned()
            .unwrap_or_else(|| "P".to_owned());
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!("Id<{label}>"),
            kind: TTypeKind::Id { owner },
            span,
        });
        self.id_ids.insert(owner, ty);
        ty
    }

    fn intern_pool(&mut self, element: Ty, capacity: usize, owner: usize, span: Span) -> Ty {
        let key = (element, capacity, owner);
        if let Some(ty) = self.pool_ids.get(&key) {
            return *ty;
        }
        let label = self
            .owner_labels
            .get(&owner)
            .cloned()
            .unwrap_or_else(|| "P".to_owned());
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!("pool<{}, {}, {}>", self.type_name(element), capacity, label),
            kind: TTypeKind::Pool {
                element,
                capacity,
                owner,
            },
            span,
        });
        self.pool_ids.insert(key, ty);
        ty
    }

    fn instantiate_generic_struct(
        &mut self,
        base: Ty,
        args: &[TypeAst],
        span: Span,
    ) -> Result<Ty, CheckError> {
        let Some(params) = self.generic_struct_owners.get(&base).cloned() else {
            return Err(CheckError {
                span,
                message: format!("'{}' is not a generic struct", self.type_name(base)),
            });
        };
        if args.len() != params.len() {
            return Err(CheckError {
                span,
                message: format!(
                    "struct '{}' expects {} owner parameter(s), got {}",
                    self.type_name(base),
                    params.len(),
                    args.len()
                ),
            });
        }
        let owners = args
            .iter()
            .map(|arg| self.owner_from_ast(arg))
            .collect::<Result<Vec<_>, _>>()?;
        let cache_key = (base, owners.clone());
        if let Some(ty) = self.struct_specialization_ids.get(&cache_key) {
            return Ok(*ty);
        }
        let substitutions = params
            .keys()
            .zip(owners.iter())
            .map(|(name, owner)| (*params.get(name).unwrap(), *owner))
            .collect::<HashMap<_, _>>();
        let TTypeKind::Struct(fields) = self.types[base.0].kind.clone() else {
            return Err(CheckError {
                span,
                message: format!("'{}' is not a struct", self.type_name(base)),
            });
        };
        let mut copied = Vec::with_capacity(fields.len());
        for field in fields {
            copied.push(TField {
                name: field.name,
                ty: self.substitute_owner_type(
                    field.ty,
                    &substitutions,
                    &mut HashMap::new(),
                    span,
                )?,
            });
        }
        let label = args
            .iter()
            .map(|arg| {
                self.owner_labels
                    .get(&self.owner_from_ast(arg).unwrap_or(0))
                    .cloned()
                    .unwrap_or_else(|| arg.name.clone())
            })
            .collect::<Vec<_>>()
            .join(", ");
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!("{}<{}>", self.types[base.0].name, label),
            kind: TTypeKind::Struct(copied),
            span,
        });
        self.specialized_struct_base.insert(ty, base);
        self.specialized_struct_owners.insert(ty, owners);
        self.struct_specialization_ids.insert(cache_key, ty);
        Ok(ty)
    }

    fn substitute_owner_type(
        &mut self,
        ty: Ty,
        substitutions: &HashMap<usize, usize>,
        memo: &mut HashMap<Ty, Ty>,
        span: Span,
    ) -> Result<Ty, CheckError> {
        if let Some(found) = memo.get(&ty) {
            return Ok(*found);
        }
        let kind = self.types[ty.0].kind.clone();
        let result = match kind {
            TTypeKind::Id { owner } => {
                self.intern_id(*substitutions.get(&owner).unwrap_or(&owner), span)
            }
            TTypeKind::Option(inner) => {
                let inner = self.substitute_owner_type(inner, substitutions, memo, span)?;
                self.option_type(inner, span)
            }
            TTypeKind::Result(ok, err) => {
                let ok = self.substitute_owner_type(ok, substitutions, memo, span)?;
                let err = self.substitute_owner_type(err, substitutions, memo, span)?;
                self.intern_generic(
                    2,
                    ok,
                    err,
                    format!("Result<{}, {}>", self.type_name(ok), self.type_name(err)),
                    span,
                    TTypeKind::Result(ok, err),
                )
            }
            TTypeKind::List { element, capacity } => {
                let element = self.substitute_owner_type(element, substitutions, memo, span)?;
                self.intern_collection(
                    1,
                    element,
                    capacity,
                    format!("list<{}, {}>", self.type_name(element), capacity),
                    span,
                )
            }
            TTypeKind::Queue { element, capacity } => {
                let element = self.substitute_owner_type(element, substitutions, memo, span)?;
                self.intern_collection(
                    2,
                    element,
                    capacity,
                    format!("queue<{}, {}>", self.type_name(element), capacity),
                    span,
                )
            }
            TTypeKind::Ring { element, capacity } => {
                let element = self.substitute_owner_type(element, substitutions, memo, span)?;
                self.intern_collection(
                    3,
                    element,
                    capacity,
                    format!("ring<{}, {}>", self.type_name(element), capacity),
                    span,
                )
            }
            TTypeKind::Grid {
                element,
                width,
                height,
                capacity,
            } => {
                let element = self.substitute_owner_type(element, substitutions, memo, span)?;
                self.intern_grid(element, width, height, capacity, span)
            }
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => {
                let key = self.substitute_owner_type(key, substitutions, memo, span)?;
                let value = self.substitute_owner_type(value, substitutions, memo, span)?;
                self.intern_map(key, value, capacity, span)
            }
            TTypeKind::Set { key, capacity } => {
                let key = self.substitute_owner_type(key, substitutions, memo, span)?;
                self.intern_set(key, capacity, span)
            }
            TTypeKind::Array { element, capacity } => {
                let element = self.substitute_owner_type(element, substitutions, memo, span)?;
                self.intern_collection(
                    0,
                    element,
                    capacity,
                    format!("{}[{}]", self.type_name(element), capacity),
                    span,
                )
            }
            TTypeKind::Pool {
                element,
                capacity,
                owner,
            } => {
                let element = self.substitute_owner_type(element, substitutions, memo, span)?;
                self.intern_pool(
                    element,
                    capacity,
                    *substitutions.get(&owner).unwrap_or(&owner),
                    span,
                )
            }
            TTypeKind::Struct(fields) => {
                let mut replaced = Vec::with_capacity(fields.len());
                for field in &fields {
                    replaced.push(TField {
                        name: field.name.clone(),
                        ty: self.substitute_owner_type(field.ty, substitutions, memo, span)?,
                    });
                }
                if replaced
                    .iter()
                    .zip(fields.iter())
                    .all(|(a, b)| a.ty == b.ty)
                {
                    ty
                } else {
                    let base = self.specialized_struct_base.get(&ty).copied().unwrap_or(ty);
                    let owners = self
                        .specialized_struct_owners
                        .get(&ty)
                        .cloned()
                        .unwrap_or_default()
                        .iter()
                        .map(|owner| *substitutions.get(owner).unwrap_or(owner))
                        .collect::<Vec<_>>();
                    if !owners.is_empty() {
                        if let Some(existing) = self
                            .struct_specialization_ids
                            .get(&(base, owners.clone()))
                            .copied()
                        {
                            existing
                        } else {
                            let labels = owners
                                .iter()
                                .map(|owner| {
                                    self.owner_labels
                                        .get(owner)
                                        .cloned()
                                        .unwrap_or_else(|| "P".to_owned())
                                })
                                .collect::<Vec<_>>()
                                .join(", ");
                            let new_ty = Ty(self.types.len());
                            self.types.push(TType {
                                name: format!("{}<{}>", self.types[base.0].name, labels),
                                kind: TTypeKind::Struct(replaced),
                                span,
                            });
                            self.specialized_struct_base.insert(new_ty, base);
                            self.specialized_struct_owners
                                .insert(new_ty, owners.clone());
                            self.struct_specialization_ids
                                .insert((base, owners), new_ty);
                            new_ty
                        }
                    } else {
                        let new_ty = Ty(self.types.len());
                        self.types.push(TType {
                            name: format!("{}<owner>", self.types[ty.0].name),
                            kind: TTypeKind::Struct(replaced),
                            span,
                        });
                        self.specialized_struct_base.insert(new_ty, base);
                        if let Some(owners) = self.specialized_struct_owners.get(&ty).cloned() {
                            self.specialized_struct_owners.insert(new_ty, owners);
                        }
                        new_ty
                    }
                }
            }
            _ => ty,
        };
        memo.insert(ty, result);
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
            kind: match kind {
                0 => TTypeKind::Array { element, capacity },
                1 => TTypeKind::List { element, capacity },
                2 => TTypeKind::Queue { element, capacity },
                _ => TTypeKind::Ring { element, capacity },
            },
            span,
        });
        self.collection_ids.insert((kind, element, capacity), ty);
        ty
    }

    fn intern_grid(
        &mut self,
        element: Ty,
        width: usize,
        height: usize,
        capacity: usize,
        span: Span,
    ) -> Ty {
        if let Some(ty) = self.grid_ids.get(&(element, width, height)) {
            return *ty;
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!("grid<{}, {}, {}>", self.type_name(element), width, height),
            kind: TTypeKind::Grid {
                element,
                width,
                height,
                capacity,
            },
            span,
        });
        self.grid_ids.insert((element, width, height), ty);
        ty
    }

    fn intern_map(&mut self, key: Ty, value: Ty, capacity: usize, span: Span) -> Ty {
        if let Some(ty) = self.map_ids.get(&(key, value, capacity)) {
            return *ty;
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!(
                "map<{}, {}, {}>",
                self.type_name(key),
                self.type_name(value),
                capacity
            ),
            kind: TTypeKind::Map {
                key,
                value,
                capacity,
            },
            span,
        });
        self.map_ids.insert((key, value, capacity), ty);
        ty
    }

    fn intern_set(&mut self, key: Ty, capacity: usize, span: Span) -> Ty {
        if let Some(ty) = self.set_ids.get(&(key, capacity)) {
            return *ty;
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: format!("set<{}, {}>", self.type_name(key), capacity),
            kind: TTypeKind::Set { key, capacity },
            span,
        });
        self.set_ids.insert((key, capacity), ty);
        ty
    }

    fn type_is_hashable(&self, ty: Ty, active: &mut std::collections::HashSet<Ty>) -> bool {
        if !active.insert(ty) {
            return false;
        }
        let hashable = match &self.types[ty.0].kind {
            TTypeKind::Refinement { base, .. } => self.type_is_hashable(*base, active),
            TTypeKind::Int
            | TTypeKind::Long
            | TTypeKind::Bool
            | TTypeKind::Ascii { .. }
            | TTypeKind::Id { .. } => true,
            TTypeKind::Struct(fields) => fields.iter().all(|field| {
                !self.type_contains_ascii(field.ty) && self.type_is_hashable(field.ty, active)
            }),
            TTypeKind::Enum(cases) => cases.iter().all(|case| {
                case.payload.iter().all(|payload| {
                    !self.type_contains_ascii(*payload) && self.type_is_hashable(*payload, active)
                })
            }),
            _ => false,
        };
        active.remove(&ty);
        hashable
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
                    if let Some(value) = checker.current_generic_capacities.get(name) {
                        return Some(*value as i128);
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
            TTypeKind::Ascii { .. } => 16,
            TTypeKind::Struct(fields) => {
                let mut size = 0u128;
                for field in fields {
                    size = checked_add(size, self.type_size_checked(field.ty, cache, span)?)?;
                }
                size
            }
            TTypeKind::Array { element, capacity }
            | TTypeKind::List { element, capacity }
            | TTypeKind::Queue { element, capacity }
            | TTypeKind::Ring { element, capacity }
            | TTypeKind::Grid {
                element, capacity, ..
            } => {
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
                if matches!(
                    self.types[ty.0].kind,
                    TTypeKind::List { .. } | TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
                ) {
                    let metadata = if matches!(self.types[ty.0].kind, TTypeKind::List { .. }) {
                        8
                    } else {
                        16
                    };
                    checked_add(metadata, payload)?
                } else {
                    payload
                }
            }
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => {
                let key_size = self.type_size_checked(*key, cache, span)?;
                let value_size = self.type_size_checked(*value, cache, span)?;
                let per_entry = checked_add(17, checked_add(key_size, value_size)?)?;
                checked_add(16, checked_mul(*capacity as u128, per_entry)?)?
            }
            TTypeKind::Set { key, capacity } => {
                let key_size = self.type_size_checked(*key, cache, span)?;
                let per_entry = checked_add(17, key_size)?;
                checked_add(16, checked_mul(*capacity as u128, per_entry)?)?
            }
            TTypeKind::Function { .. } => 8,
            TTypeKind::Pool {
                element, capacity, ..
            } => {
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
                // occupied flags, generations, reusable-slot stack, active and free counts.
                checked_add(16 + (*capacity as u128) * 9, payload)?
            }
            TTypeKind::Id { .. } | TTypeKind::Capability(_) => 8,
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
            if self.type_contains_capability(Ty(id)) {
                match &definition.kind {
                    TTypeKind::Struct(_)
                    | TTypeKind::Enum(_)
                    | TTypeKind::Option(_)
                    | TTypeKind::Result(..)
                    | TTypeKind::Array { .. }
                    | TTypeKind::List { .. }
                    | TTypeKind::Queue { .. }
                    | TTypeKind::Ring { .. }
                    | TTypeKind::Grid { .. }
                    | TTypeKind::Map { .. }
                    | TTypeKind::Set { .. } => {
                        return Err(CheckError { span: definition.span, message: "capabilities cannot be stored in structs, enums, or collections; pass them as parameters and keep them in locals".to_owned() });
                    }
                    _ => {}
                }
            }
            if let TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. } = &definition.kind
            {
                if self.type_contains_pool(*element) {
                    return Err(CheckError {
                        span: definition.span,
                        message: "pools cannot appear inside repeated collection elements; each repeated element would need a distinct owner".to_owned(),
                    });
                }
            }
            match &definition.kind {
                TTypeKind::Map { key, value, .. } => {
                    if self.type_contains_pool(*key) || self.type_contains_pool(*value) {
                        return Err(CheckError {
                            span: definition.span,
                            message: "pools cannot appear in map keys or values; store ids instead and keep their pool alive".to_owned(),
                        });
                    }
                    if !self.type_is_hashable(*key, &mut std::collections::HashSet::new()) {
                        return Err(CheckError {
                            span: definition.span,
                            message: format!(
                                "map key type '{}' is not hashable; use Ascii, integers, bool, enums, ids, or structs built from those types",
                                self.type_name(*key)
                            ),
                        });
                    }
                }
                TTypeKind::Set { key, .. } => {
                    if self.type_contains_pool(*key) {
                        return Err(CheckError {
                            span: definition.span,
                            message: "pools cannot appear in set elements; store ids instead and keep their pool alive".to_owned(),
                        });
                    }
                    if !self.type_is_hashable(*key, &mut std::collections::HashSet::new()) {
                        return Err(CheckError {
                            span: definition.span,
                            message: format!(
                                "set element type '{}' is not hashable; use Ascii, integers, bool, enums, ids, or structs built from those types",
                                self.type_name(*key)
                            ),
                        });
                    }
                }
                _ => {}
            }
            let mut cache = vec![None; self.types.len()];
            let size = self.type_size_checked(Ty(id), &mut cache, definition.span)?;
            if size > i64::MAX as u128 {
                return Err(CheckError { span: definition.span, message: "collection size overflows long; reduce a capacity or the nested element size".to_owned() });
            }
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

    fn intern_ascii(&mut self, max_bytes: usize, span: Span) -> Ty {
        let name = format!("Ascii max {max_bytes}");
        if let Some(ty) = self.type_ids.get(&name) {
            return *ty;
        }
        let ty = Ty(self.types.len());
        self.types.push(TType {
            name: name.clone(),
            kind: TTypeKind::Ascii { max_bytes },
            span,
        });
        self.type_ids.insert(name, ty);
        ty
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

    fn ascii_max(&self, ty: Ty) -> Option<usize> {
        match self.types.get(ty.0).map(|definition| &definition.kind) {
            Some(TTypeKind::Ascii { max_bytes }) => Some(*max_bytes),
            _ => None,
        }
    }

    fn ascii_option_pair(&self, left: Ty, right: Ty) -> bool {
        match (
            self.types.get(left.0).map(|ty| &ty.kind),
            self.types.get(right.0).map(|ty| &ty.kind),
        ) {
            (Some(TTypeKind::Option(left)), Some(TTypeKind::Option(right))) => {
                self.is_ascii(*left) && self.is_ascii(*right)
            }
            _ => false,
        }
    }

    fn is_ascii(&self, ty: Ty) -> bool {
        self.ascii_max(ty).is_some()
    }

    fn expression_may_be_ascii(&mut self, expr: &Expr) -> bool {
        if self
            .natural_expr_type_inner(expr, None)
            .is_some_and(|ty| self.is_ascii(ty))
        {
            return true;
        }
        match &expr.kind {
            ExprKind::ByteString(_) => true,
            ExprKind::Name(name) => self
                .visible_value_type(name)
                .is_some_and(|ty| self.is_ascii(ty)),
            ExprKind::Call { name, .. } => {
                if matches!(name.as_str(), "str" | "ascii_upper") {
                    return true;
                }
                let direct = self
                    .signatures
                    .get(name)
                    .is_some_and(|signature| self.is_ascii(signature.result));
                let indirect = self
                    .visible_value_type(name)
                    .and_then(
                        |ty| match self.types.get(ty.0).map(|definition| &definition.kind) {
                            Some(TTypeKind::Function { result, .. }) => Some(*result),
                            _ => None,
                        },
                    )
                    .is_some_and(|ty| self.is_ascii(ty));
                direct || indirect
            }
            ExprKind::MethodCall { receiver, name, .. } => {
                (name == "empty"
                    && matches!(&receiver.kind, ExprKind::Name(value) if value == "Ascii"))
                    || self.expression_may_be_ascii(receiver)
            }
            ExprKind::Take(value) | ExprKind::Try(value) => self.expression_may_be_ascii(value),
            ExprKind::Binary {
                op: BinaryOp::Add,
                left,
                right,
                ..
            } => self.expression_may_be_ascii(left) || self.expression_may_be_ascii(right),
            ExprKind::Fit { value, .. } | ExprKind::Cast { value, .. } => {
                self.expression_may_be_ascii(value)
            }
            ExprKind::If {
                then_block,
                else_block,
                ..
            } => {
                then_block
                    .tail
                    .as_deref()
                    .is_some_and(|tail| self.expression_may_be_ascii(tail))
                    || else_block.as_ref().is_some_and(|block| {
                        block
                            .tail
                            .as_deref()
                            .is_some_and(|tail| self.expression_may_be_ascii(tail))
                    })
            }
            ExprKind::Match { arms, .. } => arms.iter().any(|arm| {
                arm.body
                    .tail
                    .as_deref()
                    .is_some_and(|tail| self.expression_may_be_ascii(tail))
            }),
            _ => false,
        }
    }

    fn ascii_length_range(&self, expr: &TExpr) -> Option<(usize, usize)> {
        let max_bytes = self.ascii_max(expr.ty)?;
        let range = match &expr.kind {
            TExprKind::ByteString(bytes) => (bytes.len(), bytes.len()),
            TExprKind::AsciiEmpty => (0, 0),
            TExprKind::Local(id) => self
                .ascii_lengths
                .get(id)
                .copied()
                .unwrap_or((0, max_bytes)),
            TExprKind::AsciiUpper(value) | TExprKind::AsciiCast(value) | TExprKind::Take(value) => {
                self.ascii_length_range(value).unwrap_or((0, max_bytes))
            }
            TExprKind::AsciiFit { value, .. } => {
                self.ascii_length_range(value).unwrap_or((0, max_bytes))
            }
            TExprKind::Binary {
                op: BinaryOp::Add,
                left,
                right,
                ..
            } if self.is_ascii(left.ty) && self.is_ascii(right.ty) => {
                let left = self
                    .ascii_length_range(left)
                    .unwrap_or((0, self.ascii_max(left.ty).unwrap_or(0)));
                let right = self
                    .ascii_length_range(right)
                    .unwrap_or((0, self.ascii_max(right.ty).unwrap_or(0)));
                (
                    left.0.saturating_add(right.0),
                    left.1.saturating_add(right.1).min(max_bytes),
                )
            }
            TExprKind::AsciiFormat(value) => {
                let (lo, hi) = self.expr_range(value).unwrap_or_else(|| {
                    self.refinement(value.ty)
                        .map(|(_, lo, hi, _)| (lo, hi))
                        .unwrap_or_else(|| integer_bounds(self.base_type(value.ty)).unwrap())
                });
                let max_abs = lo.unsigned_abs().max(hi.unsigned_abs());
                let digits = if max_abs == 0 {
                    1
                } else {
                    max_abs.ilog10() as usize + 1
                };
                let sign = usize::from(lo < 0);
                (1, digits.saturating_add(sign).min(max_bytes))
            }
            _ => (0, max_bytes),
        };
        Some(range)
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
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. } => {
                    vec![*element]
                }
                TTypeKind::Map { key, value, .. } => vec![*key, *value],
                TTypeKind::Set { key, .. } => vec![*key],
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
                span: Span {
                    file: 0,
                    line: 1,
                    col: 1,
                    start_offset: 0,
                    end_offset: 0,
                },
                message: "package must define 'fn main()'; add an entry point that takes no arguments and returns ()".to_owned(),
            });
        };
        let function = &self.ast_functions[sig.id];
        let env_ty = self.type_ids["Env"];
        let result_ok = if sig.result == Ty::Unit {
            true
        } else {
            match &self.types[self.base_type(sig.result).0].kind {
                TTypeKind::Result(ok, error) => *ok == Ty::Unit && self.is_printable_type(*error),
                _ => false,
            }
        };
        if !(sig.params.is_empty() || (sig.params.len() == 1 && sig.params[0].ty == env_ty))
            || !result_ok
        {
            return Err(CheckError { span: function.span, message: "'main' must take no arguments or one Env parameter, and return () or Result<(), E> with a printable error; use 'fn main()' or 'fn main(env: Env)'".to_owned() });
        }
        Ok(())
    }

    fn is_printable_type(&self, ty: Ty) -> bool {
        let ty = self.base_type(ty);
        matches!(ty, Ty::Int | Ty::Long | Ty::Bool)
            || self.is_ascii(ty)
            || self.types[ty.0].is_sum()
            || matches!(
                self.types[ty.0].kind,
                TTypeKind::Struct(_)
                    | TTypeKind::Array { .. }
                    | TTypeKind::List { .. }
                    | TTypeKind::Queue { .. }
                    | TTypeKind::Ring { .. }
                    | TTypeKind::Grid { .. }
                    | TTypeKind::Map { .. }
                    | TTypeKind::Set { .. }
                    | TTypeKind::Pool { .. }
                    | TTypeKind::Function { .. }
            )
    }

    fn result_error_type(&self, ty: Ty) -> Option<Ty> {
        match &self.types[self.base_type(ty).0].kind {
            TTypeKind::Result(ok, error) if *ok == Ty::Unit => Some(*error),
            _ => None,
        }
    }

    fn require_handled_result(&self, expr: &TExpr, span: Span) -> Result<(), CheckError> {
        let ty = self.base_type(expr.ty);
        let TTypeKind::Result(_, error_ty) = &self.types[ty.0].kind else {
            return Ok(());
        };
        if matches!(
            &expr.kind,
            TExprKind::CollectionOp {
                op: CollectionOp::Push | CollectionOp::Insert,
                proven_success: true,
                ..
            } | TExprKind::PoolOp {
                op: PoolOp::Add,
                proven_success: true,
                ..
            } | TExprKind::MapOp {
                op: MapOp::Set,
                proven_success: true,
                ..
            } | TExprKind::SetOp {
                op: SetOp::Add,
                proven_success: true,
                ..
            }
        ) {
            return Ok(());
        }
        let is_collection_result = matches!(
            &expr.kind,
            TExprKind::CollectionOp {
                op: CollectionOp::Push | CollectionOp::Insert,
                ..
            } | TExprKind::PoolOp {
                op: PoolOp::Add,
                ..
            } | TExprKind::MapOp { op: MapOp::Set, .. }
                | TExprKind::SetOp { op: SetOp::Add, .. }
        );
        let full_ty = self.type_ids["Full"];
        let message = if is_collection_result && *error_ty == full_ty {
            "this collection operation returns a Result with error type Full; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
        } else {
            "this Result value is unused; handle it with '?', 'match', or '??' where supported"
        };
        Err(CheckError {
            span,
            message: message.to_owned(),
        })
    }

    fn check_function(&mut self, id: usize) -> Result<TFunction, CheckError> {
        let function = self.ast_functions[id].clone();
        let signature = self.function_signatures[&id].clone();
        if self.type_contains_pool(signature.result) {
            return Err(CheckError {
                span: function.span,
                message: "a value containing a pool cannot be returned; pool owners cannot escape a function".to_owned(),
            });
        }
        let saved_external_owners = std::mem::take(&mut self.current_external_owners);
        self.current_external_owners = saved_external_owners.clone();
        let saved_generic_owners = std::mem::replace(
            &mut self.current_generic_owners,
            self.function_owner_substitutions
                .get(&id)
                .cloned()
                .unwrap_or_default(),
        );
        let saved_generic_capacities = std::mem::replace(
            &mut self.current_generic_capacities,
            self.function_capacity_substitutions
                .get(&id)
                .cloned()
                .unwrap_or_default(),
        );
        self.current_function = id;
        self.current_return = signature.result;
        self.current_is_test = false;
        self.facts.clear();
        self.collection_counts.clear();
        self.loop_push_proofs.clear();
        self.active_views.clear();
        self.view_bindings.clear();
        self.loop_depth = 0;
        self.loop_names.clear();
        self.loop_outer_depths.clear();
        self.conditional_depth = 0;
        self.moved_locals.clear();
        self.ascii_lengths.clear();
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.next_scope = 1;
        self.scope_ids.clear();
        self.scope_ids.push(0);
        let mut params = Vec::new();
        for (i, param) in function.params.iter().enumerate() {
            let ty = signature.params[i].ty;
            if param.mode == ParamMode::Grow && !self.is_ascii(ty) {
                return Err(CheckError {
                    span: param.span,
                    message:
                        "grow parameters are for Ascii builders; use read or write for other types"
                            .to_owned(),
                });
            }
            let binding = self.declare_mode(
                &param.name,
                ty,
                param.mode != ParamMode::Read,
                param.mode,
                param.span,
                false,
            )?;
            if self.type_contains_pool(ty)
                && !matches!(self.types[ty.0].kind, TTypeKind::Pool { .. })
                && param.mode == ParamMode::Read
            {
                return Err(CheckError {
                    span: param.span,
                    message: "a value containing a pool cannot be passed by value; borrow the pool directly or pass the enclosing value as write".to_owned(),
                });
            }
            self.current_external_owners.extend(self.owners_in_type(ty));
            params.push(TParam {
                id: binding.id,
                name: binding.name,
                ty,
                mode: param.mode,
                span: param.span,
            });
            if let Some(max_bytes) = self.ascii_max(ty) {
                self.ascii_lengths.insert(binding.id, (0, max_bytes));
            }
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
        self.current_external_owners = saved_external_owners;
        self.current_generic_owners = saved_generic_owners;
        self.current_generic_capacities = saved_generic_capacities;
        Ok(TFunction {
            id,
            name: function.name,
            params,
            result: signature.result,
            body,
            span: function.span,
            is_test: false,
            recursive: function.recursive,
        })
    }

    fn register_globals(&mut self) -> Result<(), CheckError> {
        let declarations = self
            .programs
            .iter()
            .flat_map(|program| program.globals.clone())
            .collect::<Vec<_>>();
        let mut names = HashMap::<String, Span>::new();
        for declaration in &declarations {
            if let Some(previous) = names.insert(declaration.name.clone(), declaration.span) {
                return Err(CheckError {
                    span: declaration.span,
                    message: format!(
                        "global '{}' is declared more than once (first on line {})",
                        declaration.name, previous.line
                    ),
                });
            }
            if self.constant_ids.contains_key(&declaration.name)
                || self
                    .programs
                    .iter()
                    .flat_map(|program| program.constants.iter())
                    .any(|constant| constant.name == declaration.name)
            {
                return Err(CheckError {
                    span: declaration.span,
                    message: format!(
                        "global '{}' conflicts with a constant; choose a unique value name",
                        declaration.name
                    ),
                });
            }
            let id = self.global_ids.len();
            self.global_ids.insert(declaration.name.clone(), id);
            self.global_types.push(None);
            let owner = self.fresh_owner(declaration.name.clone());
            self.owner_scope_depths.insert(owner, 0);
            self.global_owner_paths
                .insert(declaration.name.clone(), owner);
        }

        // Owner arguments on a global struct name the concrete pool paths in that
        // instance, such as App<app.nodes>. Register them before instantiating the
        // type so fields can refer to the same owner while the type is built.
        for declaration in &declarations {
            let Some(base) = self.type_ids.get(&declaration.ty.name).copied() else {
                continue;
            };
            let Some(parameters) = self.generic_struct_owners.get(&base) else {
                continue;
            };
            if parameters.len() != declaration.ty.args.len() {
                continue;
            }
            for argument in &declaration.ty.args {
                let path = argument.name.clone();
                if !self.global_owner_paths.contains_key(&path) {
                    let owner = self.fresh_owner(path.clone());
                    self.owner_scope_depths.insert(owner, 0);
                    self.global_owner_paths.insert(path, owner);
                }
            }
        }

        for declaration in &declarations {
            let id = self.global_ids[&declaration.name];
            let saved_pending = self.pending_owner.take();
            if declaration.ty.name == "pool" {
                let owner = self.global_owner_paths[&declaration.name];
                self.pending_owner = Some((declaration.name.clone(), owner));
            }
            let ty = self.parse_type(&declaration.ty);
            self.pending_owner = saved_pending;
            let mut ty = ty?;
            if self.type_contains_capability(ty) {
                return Err(CheckError { span: declaration.ty.span, message: "capabilities cannot be stored in globals; receive them through parameters and keep them in locals".to_owned() });
            }
            if self.type_contains_pool(ty) {
                ty = self.localize_embedded_pool_owners(ty, &declaration.name, declaration.span)?;
            }
            self.global_types[id] = Some(ty);
        }
        self.ast_globals = declarations;
        Ok(())
    }

    fn check_global_initializer(&mut self, id: usize) -> Result<TExpr, CheckError> {
        let declaration = self.ast_globals[id].clone();
        let ty = self.global_types[id].expect("registered global type");
        self.current_function = self.ast_functions.len() + self.ast_tests.len();
        self.current_return = ty;
        self.current_is_test = false;
        self.checking_constant = false;
        self.checking_global_initializer = true;
        self.loop_depth = 0;
        self.loop_names.clear();
        self.loop_outer_depths.clear();
        self.conditional_depth = 0;
        self.moved_locals.clear();
        self.ascii_lengths.clear();
        self.facts.clear();
        self.collection_counts.clear();
        self.loop_push_proofs.clear();
        self.active_views.clear();
        self.view_bindings.clear();
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.scope_ids.clear();
        self.scope_ids.push(0);
        self.current_external_owners = self
            .global_types
            .iter()
            .flatten()
            .flat_map(|global_ty| self.owners_in_type(*global_ty))
            .collect();
        let initializer = self.check_store(&declaration.value, ty);
        self.locals.clear();
        self.checking_global_initializer = false;
        initializer
    }

    fn finish_globals(
        &self,
        initializers: Vec<TExpr>,
        constants: &[TConstant],
        functions: &[TFunction],
        call_graph: &[Vec<TCallEdge>],
    ) -> Result<Vec<TGlobal>, CheckError> {
        let function_effects = infer_global_effects(functions, call_graph);
        let mut globals = Vec::with_capacity(initializers.len());
        for (id, initializer) in initializers.into_iter().enumerate() {
            let declaration = &self.ast_globals[id];
            let mut effects = GlobalEffects::default();
            collect_global_expr_effects(&initializer, &mut effects, functions);
            close_global_effects(&mut effects, &function_effects);
            if effects.out || effects.env || effects.fs_read || effects.fs_write {
                return Err(CheckError {
                    span: declaration.value.span,
                    message: format!(
                        "global '{}' initializer cannot use effect '{}'; initializers must be effect free",
                        declaration.name,
                        if effects.fs_read {
                            "fs.read"
                        } else if effects.fs_write {
                            "fs.write"
                        } else if effects.env {
                            "env"
                        } else {
                            "out"
                        }
                    ),
                });
            }
            if !effects.writes.is_empty() {
                let access = self.global_path_name(&effects.writes[0].path);
                return Err(CheckError {
                    span: declaration.value.span,
                    message: format!(
                        "global '{}' initializer cannot write global '{}'; build the value in its initializer",
                        declaration.name, access
                    ),
                });
            }
            let ty = self.global_types[id].expect("registered global type");
            let initializer = if effects.reads.is_empty() {
                TGlobalInitializer::Constant(crate::const_eval::evaluate_expression(
                    &declaration.name,
                    &initializer,
                    functions,
                    call_graph,
                    &self.types,
                    constants,
                )?)
            } else {
                TGlobalInitializer::Runtime(initializer)
            };
            globals.push(TGlobal {
                id,
                name: declaration.name.clone(),
                ty,
                initializer,
                span: declaration.span,
                offset: 0,
                size_bytes: 0,
            });
        }
        Ok(globals)
    }

    fn global_initialization_order(
        &self,
        globals: &[TGlobal],
        functions: &[TFunction],
        call_graph: &[Vec<TCallEdge>],
    ) -> Result<Vec<usize>, CheckError> {
        let function_effects = infer_global_effects(functions, call_graph);
        let mut dependencies = vec![Vec::<usize>::new(); globals.len()];
        for global in globals {
            let TGlobalInitializer::Runtime(expr) = &global.initializer else {
                continue;
            };
            let mut effects = GlobalEffects::default();
            collect_global_expr_effects(expr, &mut effects, functions);
            close_global_effects(&mut effects, &function_effects);
            dependencies[global.id] = effects.reads.into_iter().map(|path| path.global).collect();
            dependencies[global.id].sort_unstable();
            dependencies[global.id].dedup();
        }
        fn visit(
            id: usize,
            globals: &[TGlobal],
            dependencies: &[Vec<usize>],
            state: &mut [u8],
            stack: &mut Vec<usize>,
            order: &mut Vec<usize>,
        ) -> Result<(), Vec<usize>> {
            if state[id] == 2 {
                return Ok(());
            }
            if state[id] == 1 {
                let start = stack.iter().position(|entry| *entry == id).unwrap_or(0);
                let mut cycle = stack[start..].to_vec();
                cycle.push(id);
                return Err(cycle);
            }
            state[id] = 1;
            stack.push(id);
            for dependency in &dependencies[id] {
                visit(*dependency, globals, dependencies, state, stack, order)?;
            }
            stack.pop();
            state[id] = 2;
            if matches!(globals[id].initializer, TGlobalInitializer::Runtime(_)) {
                order.push(id);
            }
            Ok(())
        }
        let mut state = vec![0; globals.len()];
        let mut stack = Vec::new();
        let mut order = Vec::new();
        for id in 0..globals.len() {
            if let Err(cycle) = visit(
                id,
                globals,
                &dependencies,
                &mut state,
                &mut stack,
                &mut order,
            ) {
                let names = cycle
                    .iter()
                    .map(|entry| globals[*entry].name.clone())
                    .collect::<Vec<_>>();
                return Err(CheckError {
                    span: globals[id].span,
                    message: format!("global initialization cycle: {}", names.join(" -> ")),
                });
            }
        }
        Ok(order)
    }

    fn check_global_access_contracts(
        &self,
        functions: &[TFunction],
        call_graph: &[Vec<TCallEdge>],
        indirect_targets: &HashMap<usize, Vec<usize>>,
    ) -> Result<(), CheckError> {
        let effects = infer_global_effects(functions, call_graph);
        for function in functions {
            let mut active_views = Vec::new();
            let mut check = |call: &TExpr, views: &[GlobalPath]| {
                if let TExprKind::Call {
                    target: CallTarget::SortBy { .. },
                    args,
                    ..
                } = &call.kind
                {
                    if let Some(input_path) = args.first().and_then(global_path_from_expr) {
                        let expression = &args[1];
                        let mut expression_effects = GlobalEffects::default();
                        collect_global_expr_effects(expression, &mut expression_effects, functions);
                        let mut add_indirect_targets = |nested: &TExpr, _views: &[GlobalPath]| {
                            let nested_callsite = match &nested.kind {
                                TExprKind::IndirectCall { callsite_id, .. } => Some(*callsite_id),
                                TExprKind::Call {
                                    target: CallTarget::SortBy { callsite_id, .. },
                                    ..
                                } => Some(*callsite_id),
                                _ => None,
                            };
                            if let Some(nested_callsite) = nested_callsite {
                                for target in
                                    indirect_targets.get(&nested_callsite).into_iter().flatten()
                                {
                                    expression_effects.add_call(*target);
                                }
                            }
                            Ok(())
                        };
                        visit_global_calls_expr(
                            expression,
                            &mut Vec::new(),
                            &mut add_indirect_targets,
                        )?;
                        close_global_effects(&mut expression_effects, &effects);
                        if let Some(access_path) = expression_effects
                            .reads
                            .iter()
                            .chain(expression_effects.writes.iter().map(|write| &write.path))
                            .find(|path| global_paths_overlap(&input_path, path))
                        {
                            return Err(CheckError {
                                span: expression.span,
                                message: format!(
                                    "sort_by context accesses '{}' while sorting '{}'; pass a separate value",
                                    self.global_path_name(access_path),
                                    self.global_path_name(&input_path)
                                ),
                            });
                        }
                    }
                }
                let calls = match &call.kind {
                    TExprKind::Call {
                        target: CallTarget::Function(target),
                        args,
                        ..
                    } => vec![(
                        *target,
                        args.as_slice(),
                        functions[*target]
                            .params
                            .iter()
                            .map(|param| param.mode)
                            .collect::<Vec<_>>(),
                    )],
                    TExprKind::OptionalCall {
                        function_id, args, ..
                    } => vec![(
                        *function_id,
                        args.as_slice(),
                        functions[*function_id]
                            .params
                            .iter()
                            .skip(1)
                            .map(|param| param.mode)
                            .collect::<Vec<_>>(),
                    )],
                    TExprKind::IndirectCall {
                        callsite_id,
                        args,
                        params,
                        ..
                    } => indirect_targets
                        .get(callsite_id)
                        .into_iter()
                        .flatten()
                        .map(|target| {
                            (
                                *target,
                                args.as_slice(),
                                params.iter().map(|param| param.mode).collect(),
                            )
                        })
                        .collect(),
                    _ => Vec::new(),
                };
                for (target, args, modes) in calls {
                    let Some(callee_effects) = effects.get(target) else {
                        continue;
                    };
                    let Some(callee) = functions.get(target) else {
                        continue;
                    };
                    for (argument, mode) in args.iter().zip(modes) {
                        if mode != ParamMode::Write {
                            continue;
                        }
                        let Some(argument_path) = global_path_from_expr(argument) else {
                            continue;
                        };
                        if callee_effects
                            .reads
                            .iter()
                            .chain(callee_effects.writes.iter().map(|write| &write.path))
                            .any(|path| global_paths_overlap(&argument_path, path))
                        {
                            return Err(CheckError {
                                span: call.span,
                                message: format!(
                                    "write argument '{}' overlaps hidden global access in '{}'; pass separate fields or remove the by-name access",
                                    self.global_path_name(&argument_path),
                                    callee.name
                                ),
                            });
                        }
                    }
                    for view in views {
                        if let Some(write) = callee_effects
                            .structural_writes
                            .iter()
                            .find(|write| global_path_is_prefix(write, view))
                        {
                            return Err(CheckError {
                                span: call.span,
                                message: format!(
                                    "cannot call '{}' while viewing '{}'; the call can structurally change that global",
                                    callee.name,
                                    self.global_path_name(write)
                                ),
                            });
                        }
                    }
                }
                Ok(())
            };
            visit_global_calls_block(&function.body, &mut active_views, &mut check)?;
        }
        Ok(())
    }

    fn layout_globals(&self, mut globals: Vec<TGlobal>) -> Result<(Vec<TGlobal>, u64), CheckError> {
        let mut offset = 0u128;
        let mut cache = vec![None; self.types.len()];
        for global in &mut globals {
            offset = offset.checked_add(7).ok_or_else(|| CheckError {
                span: global.span,
                message: "global state size overflows long; reduce its capacity".to_owned(),
            })? & !7;
            global.offset = u64::try_from(offset).map_err(|_| CheckError {
                span: global.span,
                message: "global state size overflows long; reduce its capacity".to_owned(),
            })?;
            let size = self.type_size_checked(global.ty, &mut cache, global.span)?;
            let aligned = size.checked_add(7).ok_or_else(|| CheckError {
                span: global.span,
                message: "global state size overflows long; reduce its capacity".to_owned(),
            })? & !7;
            global.size_bytes = u64::try_from(aligned).map_err(|_| CheckError {
                span: global.span,
                message: "global state size overflows long; reduce its capacity".to_owned(),
            })?;
            offset = offset.checked_add(aligned).ok_or_else(|| CheckError {
                span: global.span,
                message: "global state size overflows long; reduce its capacity".to_owned(),
            })?;
        }
        let total = u64::try_from(offset).map_err(|_| CheckError {
            span: globals
                .first()
                .map_or(Span::default(), |global| global.span),
            message: "global state size overflows long; reduce its capacity".to_owned(),
        })?;
        Ok((globals, total))
    }

    fn global_path_name(&self, path: &GlobalPath) -> String {
        let mut name = self
            .ast_globals
            .get(path.global)
            .map(|global| global.name.clone())
            .unwrap_or_else(|| "<global>".to_owned());
        let Some(mut ty) = self.global_types.get(path.global).and_then(|ty| *ty) else {
            return name;
        };
        for index in &path.fields {
            let TTypeKind::Struct(fields) = &self.types[ty.0].kind else {
                break;
            };
            let Some(field) = fields.get(*index) else {
                break;
            };
            name.push('.');
            name.push_str(&field.name);
            ty = field.ty;
        }
        name
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
        self.loop_names.clear();
        self.loop_outer_depths.clear();
        self.conditional_depth = 0;
        self.moved_locals.clear();
        self.ascii_lengths.clear();
        self.next_local = 0;
        self.locals.clear();
        self.locals.push(HashMap::new());
        self.next_scope = 1;
        self.scope_ids.clear();
        self.scope_ids.push(0);
        let mut params = Vec::new();
        if test.params.len() > 1
            || test
                .params
                .iter()
                .any(|param| param.ty.name != "Env" || param.mode != ParamMode::Read)
        {
            return Err(CheckError { span: test.span, message: "tests may take one read-only Env parameter; use 'test \"name\" (env: Env) { ... }'".to_owned() });
        }
        for param in &test.params {
            let ty = self.parse_type(&param.ty)?;
            let binding =
                self.declare_mode(&param.name, ty, false, ParamMode::Read, param.span, false)?;
            params.push(TParam {
                id: binding.id,
                name: binding.name,
                ty,
                mode: ParamMode::Read,
                span: param.span,
            });
        }
        let body = self.check_block(&test.body, false, None)?;
        let mut test_result = Ty::Unit;
        if body.falls_through {
            if let Some(tail) = &body.tail {
                if tail.ty != Ty::Unit && tail.ty != Ty::Never {
                    let Some(error_ty) = self.result_error_type(tail.ty) else {
                        return Err(CheckError {
                            span: tail.span,
                            message: format!(
                                "test '{}' ends with {}; remove the value or use it in a statement",
                                test.name,
                                self.type_name(tail.ty)
                            ),
                        });
                    };
                    if !self.is_printable_type(error_ty) {
                        return Err(CheckError {
                            span: tail.span,
                            message: format!(
                                "test '{}' returns a Result with an error type that cannot be printed",
                                test.name
                            ),
                        });
                    }
                    test_result = tail.ty;
                }
            }
        }
        self.locals.clear();
        self.current_is_test = false;
        Ok((
            TFunction {
                id,
                name: format!("__nl_test_{index}"),
                params,
                result: test_result,
                body,
                span: test.span,
                is_test: true,
                recursive: false,
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
                let unhandled_collection = match &typed.kind {
                    TExprKind::CollectionOp {
                        op: CollectionOp::Push | CollectionOp::Insert,
                        proven_success,
                        ..
                    }
                    | TExprKind::PoolOp {
                        op: PoolOp::Add,
                        proven_success,
                        ..
                    }
                    | TExprKind::MapOp {
                        op: MapOp::Set,
                        proven_success,
                        ..
                    }
                    | TExprKind::SetOp {
                        op: SetOp::Add,
                        proven_success,
                        ..
                    } => Some(*proven_success),
                    _ => None,
                };
                if let Some(proven_success) = unhandled_collection {
                    if !proven_success {
                        let message = if matches!(&typed.kind, TExprKind::PoolOp { .. }) {
                            "this pool add returns Result<Id, Full>; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
                        } else {
                            "this collection operation returns a Result with error type Full; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
                        };
                        return Err(CheckError {
                            span: expr.span,
                            message: message.to_owned(),
                        });
                    }
                    statements.push(TStmt {
                        kind: TStmtKind::Expr(typed),
                        span: expr.span,
                    });
                    None
                } else {
                    self.require_handled_result(&typed, expr.span)?;
                    Some(Box::new(self.coerce_store(typed, Ty::Unit)?))
                }
            } else if let Some(target) = expected {
                Some(Box::new(self.check_store(expr, target)?))
            } else {
                let typed = self.check_expr(expr, None)?;
                let unhandled = match &typed.kind {
                    TExprKind::CollectionOp {
                        op: CollectionOp::Push | CollectionOp::Insert,
                        proven_success,
                        ..
                    }
                    | TExprKind::PoolOp {
                        op: PoolOp::Add,
                        proven_success,
                        ..
                    }
                    | TExprKind::MapOp {
                        op: MapOp::Set,
                        proven_success,
                        ..
                    }
                    | TExprKind::SetOp {
                        op: SetOp::Add,
                        proven_success,
                        ..
                    } => Some(*proven_success),
                    _ => None,
                };
                if unhandled == Some(false) {
                    let message = if matches!(&typed.kind, TExprKind::PoolOp { .. }) {
                        "this pool add returns Result<Id, Full>; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
                    } else {
                        "this collection operation returns a Result with error type Full; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
                    };
                    return Err(CheckError {
                        span: expr.span,
                        message: message.to_owned(),
                    });
                }
                Some(Box::new(typed))
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
                if annotation.is_none()
                    && self.loop_depth > 0
                    && matches!(
                        &value.kind,
                        ExprKind::MethodCall { receiver, name, args, .. }
                            if name == "empty"
                                && args.is_empty()
                                && matches!(&receiver.kind, ExprKind::Name(type_name) if type_name == "Ascii")
                    )
                {
                    let loop_name = self.loop_names.last().map(String::as_str).unwrap_or("loop");
                    return Err(CheckError {
                        span: stmt.span,
                        message: format!(
                            "builder '{name}' in loop '{loop_name}' has no inferred Ascii maximum; declare it as 'Ascii max N' and use try_append while handling Full, or prove the loop bound and bytes added per iteration against its declared maximum"
                        ),
                    });
                }
                let old_pending = self.pending_owner.take();
                let pending = annotation.as_ref().is_some_and(|ty| ty.name == "pool");
                if pending {
                    let owner = self.fresh_owner(name.clone());
                    self.owner_scope_depths
                        .insert(owner, self.scope_ids.len().saturating_sub(1));
                    self.pending_owner = Some((name.clone(), owner));
                }
                let parsed_annotated = annotation
                    .as_ref()
                    .map(|ty| self.parse_type(ty))
                    .transpose();
                let declared_owner = self.pending_owner.as_ref().map(|(_, owner)| *owner);
                self.pending_owner = old_pending;
                let mut annotated = parsed_annotated?;
                if !pending {
                    if let Some(ty) = annotated {
                        if self.type_contains_pool(ty) {
                            annotated =
                                Some(self.localize_embedded_pool_owners(ty, name, stmt.span)?);
                        }
                    }
                }
                let typed_value = if let Some(target) = annotated {
                    self.check_store(value, target)?
                } else {
                    self.check_expr(value, None)?
                };
                if typed_value.ty == Ty::Unit || typed_value.ty == Ty::Never {
                    return Err(CheckError { span: value.span, message: "a binding needs a value; functions and if expressions used here must return int, long, or bool".to_owned() });
                }
                let ty = annotated.unwrap_or(typed_value.ty);
                let scope_depth = self.scope_ids.len().saturating_sub(1);
                if self.type_contains_pool(ty) && !self.fresh_pool_value(&typed_value) {
                    return Err(CheckError {
                        span: value.span,
                        message: "a value containing a pool cannot be copied; initialize a fresh pool owner".to_owned(),
                    });
                }
                if let TExprKind::Take(source) = &typed_value.kind {
                    if self
                        .ascii_max(source.ty)
                        .zip(self.ascii_max(ty))
                        .is_some_and(|(reserved, declared)| declared > reserved)
                    {
                        return Err(CheckError {
                            span: annotation.as_ref().map_or(value.span, |ty| ty.span),
                            message: format!(
                                "take cannot widen an Ascii builder from max {} to max {}; copy it into a newly reserved builder instead",
                                self.ascii_max(source.ty).unwrap_or(0),
                                self.ascii_max(ty).unwrap_or(0)
                            ),
                        });
                    }
                }
                self.check_owner_lifetime(typed_value.ty, Some(scope_depth), value.span)?;
                if let TExprKind::Take(source) = &typed_value.kind {
                    if let TExprKind::Local(source_id) = source.kind {
                        if self
                            .binding_by_id(source_id)
                            .is_some_and(|source| source.scope_depth > scope_depth)
                        {
                            return Err(CheckError {
                                span: value.span,
                                message: "cannot move a builder out of its enclosing scope; its reserved region ends before the new owner's scope".to_owned(),
                            });
                        }
                    }
                }
                if let TTypeKind::Pool { owner, .. } = self.types[ty.0].kind {
                    if let Some(declared_owner) = declared_owner {
                        if owner != declared_owner {
                            return Err(CheckError {
                                span: annotation.as_ref().map_or(stmt.span, |ty| ty.span),
                                message: format!(
                                    "a new pool '{}' cannot be attached to owner '{}'; declare the owner in its own pool type",
                                    name,
                                    self.owner_labels
                                        .get(&owner)
                                        .map(String::as_str)
                                        .unwrap_or("another pool")
                                ),
                            });
                        }
                    }
                }
                let binding = self.declare(name, ty, *mutable, stmt.span, false)?;
                if self.is_ascii(ty) {
                    let max_bytes = self.ascii_max(ty).unwrap_or(0);
                    let range = self
                        .ascii_length_range(&typed_value)
                        .unwrap_or((0, max_bytes));
                    self.ascii_lengths.insert(binding.id, range);
                }
                if let Some(range) = self.expr_range(&typed_value) {
                    self.facts.insert((binding.id, Vec::new()), range);
                }
                self.record_nested_facts(binding.id, &[], &typed_value);
                if matches!(
                    self.types[ty.0].kind,
                    TTypeKind::List { .. }
                        | TTypeKind::Queue { .. }
                        | TTypeKind::Ring { .. }
                        | TTypeKind::Pool { .. }
                        | TTypeKind::Map { .. }
                        | TTypeKind::Set { .. }
                ) {
                    let key = CollectionCountKey {
                        root: binding.id,
                        fields: Vec::new(),
                    };
                    if matches!(
                        &typed_value.kind,
                        TExprKind::EmptyList
                            | TExprKind::EmptyPool
                            | TExprKind::EmptyMap
                            | TExprKind::EmptySet
                            | TExprKind::EmptyQueue
                            | TExprKind::EmptyRing
                    ) {
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
                        && (!places_proven_prefix(&view, &target_place)
                            || (*op == AssignOp::Set
                                && view.path.len() == target_place.path.len()
                                && matches!(
                                    view.path.last(),
                                    Some(TProjection::Index { is_map: true, .. })
                                )))
                }) {
                    return Err(CheckError {
                        span: stmt.span,
                        message:
                            "cannot replace or modify storage that contains a live collection view"
                                .to_owned(),
                    });
                }
                if *op == AssignOp::Set && self.type_contains_pool(place.ty) {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "a value containing a pool cannot be replaced or assigned; pool copies and resets are not supported".to_owned(),
                    });
                }
                let (typed_value, assigned_range, assigned_ascii_range) = if *op == AssignOp::Set {
                    let stored = self.check_store(value, place.ty)?;
                    let range = self.expr_range(&stored);
                    let ascii_range = self
                        .is_ascii(place.ty)
                        .then(|| self.ascii_length_range(&stored))
                        .flatten();
                    (stored, range, ascii_range)
                } else if self.is_ascii(place.ty) {
                    if *op != AssignOp::Add {
                        return Err(CheckError {
                            span: stmt.span,
                            message: "Ascii supports '+=' for append; use an explicit value assignment for replacement".to_owned(),
                        });
                    }
                    if place.root < self.function_param_count()
                        && self
                            .binding_by_id(place.root)
                            .is_some_and(|binding| binding.mode != ParamMode::Grow)
                    {
                        return Err(CheckError {
                            span: stmt.span,
                            message: "appending through a parameter requires 'grow' mode; 'write' cannot increase its length".to_owned(),
                        });
                    }
                    let typed_value = self.check_expr(value, None)?;
                    if !self.is_ascii(typed_value.ty) {
                        return Err(CheckError {
                            span: value.span,
                            message: format!(
                                "Ascii '+=' needs an Ascii value; found {}",
                                self.type_name(typed_value.ty)
                            ),
                        });
                    }
                    let max_bytes = self.ascii_max(place.ty).unwrap_or(0);
                    let left_range = if place.path.is_empty() {
                        self.ascii_lengths
                            .get(&place.root)
                            .copied()
                            .unwrap_or((0, max_bytes))
                    } else {
                        (0, max_bytes)
                    };
                    let right_range = self
                        .ascii_length_range(&typed_value)
                        .unwrap_or((0, self.ascii_max(typed_value.ty).unwrap_or(0)));
                    let new_range = (
                        left_range.0.saturating_add(right_range.0),
                        left_range.1.saturating_add(right_range.1),
                    );
                    if new_range.1 > max_bytes {
                        return Err(CheckError {
                            span: stmt.span,
                            message: format!(
                                "cannot prove this append fits Ascii max {}; use '{}.try_append(value)' and handle Full",
                                max_bytes,
                                target_name(target)
                            ),
                        });
                    }
                    (typed_value, None, Some(new_range))
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
                    (typed_value, range, None)
                };
                let destination_depth = self
                    .binding_by_id(place.root)
                    .map(|binding| binding.scope_depth)
                    .unwrap_or(0);
                if *op == AssignOp::Set
                    && self.is_ascii(place.ty)
                    && self.binding_by_id(place.root).is_some_and(|binding| {
                        binding.id < self.function_param_count() && binding.mode == ParamMode::Write
                    })
                {
                    let maximum = self.ascii_max(place.ty).unwrap_or(0);
                    let current = self
                        .ascii_lengths
                        .get(&place.root)
                        .copied()
                        .unwrap_or((0, maximum));
                    let assigned = assigned_ascii_range.unwrap_or((0, maximum));
                    if assigned.1 > current.0 {
                        return Err(CheckError {
                            span: stmt.span,
                            message: "a write Ascii parameter may not increase its existing length; use 'grow' when appending or replacing with longer text".to_owned(),
                        });
                    }
                }
                self.check_owner_lifetime(typed_value.ty, Some(destination_depth), value.span)?;
                if *op != AssignOp::Set {
                    if self.is_ascii(place.ty) {
                        // ASCII appends were proved above and are emitted as a direct append.
                    } else {
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
                }
                let place_fields = place_field_path(&place);
                let nested_facts = place_fields.as_deref().map_or_else(Vec::new, |fields| {
                    self.nested_facts_for_value(fields, &typed_value)
                });
                self.invalidate_place(&place);
                if self.is_ascii(place.ty) && place.path.is_empty() {
                    if *op == AssignOp::Set {
                        let max_bytes = self.ascii_max(place.ty).unwrap_or(0);
                        self.ascii_lengths
                            .insert(place.root, assigned_ascii_range.unwrap_or((0, max_bytes)));
                    } else if let Some(range) = assigned_ascii_range {
                        self.ascii_lengths.insert(place.root, range);
                    }
                }
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
                        if self.type_contains_pool(self.current_return) {
                            return Err(CheckError {
                                span: expr.span,
                                message: "a value containing a pool cannot be returned; pool owners cannot escape a function".to_owned(),
                            });
                        }
                        let value = self.check_store(expr, self.current_return)?;
                        if typed_expr_contains_take(&value) {
                            return Err(CheckError {
                                span: expr.span,
                                message: "cannot move a builder out of its enclosing scope; its reserved region ends before the returned value's scope".to_owned(),
                            });
                        }
                        self.check_owner_lifetime(value.ty, None, expr.span)?;
                        Some(value)
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
                    if matches!(
                        typed.kind,
                        TExprKind::CollectionOp {
                            op: CollectionOp::Push | CollectionOp::Insert,
                            proven_success: false,
                            ..
                        } | TExprKind::PoolOp {
                            op: PoolOp::Add,
                            proven_success: false,
                            ..
                        } | TExprKind::MapOp {
                            op: MapOp::Set,
                            proven_success: false,
                            ..
                        } | TExprKind::SetOp {
                            op: SetOp::Add,
                            proven_success: false,
                            ..
                        }
                    ) {
                        let message = if matches!(&typed.kind, TExprKind::PoolOp { .. }) {
                            "this pool add returns Result<Id, Full>; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
                        } else {
                            "this collection operation returns a Result with error type Full; handle it with '?', 'match', or '??' where supported, or write 'discard' when dropping Full is intended"
                        };
                        return Err(CheckError {
                            span: expr.span,
                            message: message.to_owned(),
                        });
                    }
                    self.require_handled_result(&typed, expr.span)?;
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
                let before_ascii_lengths = self.ascii_lengths.clone();
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
                self.loop_outer_depths
                    .push(self.scope_ids.len().saturating_sub(1));
                self.loop_depth += 1;
                self.loop_names.push(name.clone());
                let typed_body = self.check_block(body, true, None)?;
                if let Some(tail) = typed_body.tail.as_deref() {
                    self.require_handled_result(tail, tail.span)?;
                }
                let after_body_counts = self.collection_counts.clone();
                let after_body_ascii_lengths = self.ascii_lengths.clone();
                self.check_loop_ascii_growth(
                    &before_ascii_lengths,
                    &after_body_ascii_lengths,
                    &typed_body,
                    iteration_bound,
                    stmt.span,
                )?;
                self.loop_depth -= 1;
                self.loop_names.pop();
                self.loop_outer_depths.pop();
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
                second_index_name,
                collection,
                body,
            } => {
                let typed_collection = self.check_expr(collection, None)?;
                let (
                    element,
                    capacity,
                    is_list,
                    is_pool,
                    is_map,
                    is_set,
                    is_grid,
                    pool_owner,
                    map_key,
                ) = match self.types[typed_collection.ty.0].kind {
                    TTypeKind::Array { element, capacity } => (
                        element, capacity, false, false, false, false, false, None, None,
                    ),
                    TTypeKind::List { element, capacity } => (
                        element, capacity, true, false, false, false, false, None, None,
                    ),
                    TTypeKind::Queue { element, capacity }
                    | TTypeKind::Ring { element, capacity } => (
                        element, capacity, true, false, false, false, false, None, None,
                    ),
                    TTypeKind::Pool {
                        element,
                        capacity,
                        owner,
                    } => (
                        element,
                        capacity,
                        false,
                        true,
                        false,
                        false,
                        false,
                        Some(owner),
                        None,
                    ),
                    TTypeKind::Map {
                        key,
                        value,
                        capacity,
                    } => (
                        value,
                        capacity,
                        false,
                        false,
                        true,
                        false,
                        false,
                        None,
                        Some(key),
                    ),
                    TTypeKind::Set { key, capacity } => {
                        (key, capacity, false, false, false, true, false, None, None)
                    }
                    TTypeKind::Grid {
                        element, capacity, ..
                    } => (
                        element, capacity, false, false, false, false, true, None, None,
                    ),
                    _ => {
                        return Err(CheckError {
                            span: collection.span,
                            message: format!(
                                "{} is not a fixed collection; collection loops need an array, list, pool, map, set, queue, ring, or grid",
                                self.type_name(typed_collection.ty)
                            ),
                        });
                    }
                };
                if is_map && index_name.is_none() {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "map iteration needs both value and key names: use 'for value, key in map'".to_owned(),
                    });
                }
                if is_set && index_name.is_some() {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "set iteration binds one key: use 'for key in set'".to_owned(),
                    });
                }
                if is_grid && (index_name.is_none() || second_index_name.is_none()) {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "grid iteration needs cell, x, and y names: use 'for cell, x, y in grid'".to_owned(),
                    });
                }
                if !is_grid && second_index_name.is_some() {
                    return Err(CheckError {
                        span: stmt.span,
                        message: "only a grid loop has three bindings; use 'for value, index in collection'".to_owned(),
                    });
                }
                let source = self.resolve_place(collection).map_err(|_| CheckError {
                    span: collection.span,
                    message: "collection iteration needs a local, parameter, or field place; bind the value to a local first".to_owned(),
                })?;
                let writable = self.place_is_mutable(&source) && !is_set;
                let before_counts = self.collection_counts.clone();
                let before_ascii_lengths = self.ascii_lengths.clone();
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
                    let index_ty = if let Some(key) = map_key {
                        key
                    } else if let Some(owner) = pool_owner {
                        self.intern_id(owner, stmt.span)
                    } else {
                        Ty::Long
                    };
                    Some(
                        self.declare(index_name, index_ty, false, stmt.span, true)?
                            .id,
                    )
                } else {
                    None
                };
                let second_index_id = if let Some(second_index_name) = second_index_name {
                    Some(
                        self.declare(second_index_name, Ty::Long, false, stmt.span, true)?
                            .id,
                    )
                } else {
                    None
                };
                let index_expr = TExpr {
                    kind: TExprKind::Local(counter_id),
                    ty: Ty::Long,
                    span: stmt.span,
                };
                let mut element_place = source.clone();
                element_place.path.push(TProjection::Index {
                    index: index_expr,
                    constant: None,
                    capacity,
                    is_list,
                    is_pool,
                    is_map,
                    proven: true,
                    grid: None,
                });
                element_place.ty = element;
                if is_set {
                    self.active_views.push(source.clone());
                } else {
                    self.view_bindings.insert(binding.id, element_place.clone());
                    self.active_views.push(element_place);
                }
                self.loop_outer_depths
                    .push(self.scope_ids.len().saturating_sub(1));
                self.loop_depth += 1;
                self.loop_names.push(name.clone());
                let typed_body = self.check_block(body, true, None)?;
                if let Some(tail) = typed_body.tail.as_deref() {
                    self.require_handled_result(tail, tail.span)?;
                }
                let after_body_counts = self.collection_counts.clone();
                let after_body_ascii_lengths = self.ascii_lengths.clone();
                self.check_loop_ascii_growth(
                    &before_ascii_lengths,
                    &after_body_ascii_lengths,
                    &typed_body,
                    Some(iterations),
                    stmt.span,
                )?;
                self.loop_depth -= 1;
                self.loop_names.pop();
                self.loop_outer_depths.pop();
                self.active_views.pop();
                if !is_set {
                    self.view_bindings.remove(&binding.id);
                }
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
                    is_pool,
                    is_map,
                    is_set,
                    is_grid,
                    second_index_id,
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
                    } | TExprKind::PoolOp {
                        op: PoolOp::Add,
                        ..
                    } | TExprKind::MapOp { op: MapOp::Set, .. }
                        | TExprKind::SetOp { op: SetOp::Add, .. }
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
            StmtKind::Block(block) => {
                let typed = self.check_block(block, true, None)?;
                if let Some(tail) = typed.tail.as_deref() {
                    self.require_handled_result(tail, tail.span)?;
                }
                TStmtKind::Block(typed)
            }
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
            ExprKind::ByteString(_) => None,
            ExprKind::Name(name) if shadowed_counter == Some(name.as_str()) => None,
            ExprKind::Name(name) if self.current_generic_capacities.contains_key(name) => {
                let value = self.current_generic_capacities[name];
                Some(if value <= i32::MAX as usize {
                    Ty::Int
                } else {
                    Ty::Long
                })
            }
            ExprKind::Name(name) => self.find_binding(name).map(|binding| binding.ty),
            ExprKind::ListLiteral
            | ExprKind::PoolLiteral
            | ExprKind::MapLiteral
            | ExprKind::SetLiteral
            | ExprKind::QueueLiteral
            | ExprKind::RingLiteral => None,
            ExprKind::Call { name, .. } => {
                if name == "print" {
                    Some(Ty::Unit)
                } else if name == "sort" || name == "sort_by" {
                    Some(Ty::Unit)
                } else if let Some(value_ty) = self.visible_value_type(name) {
                    match self.types.get(value_ty.0).map(|ty| &ty.kind) {
                        Some(TTypeKind::Function { result, .. }) => Some(*result),
                        _ => None,
                    }
                } else {
                    self.signatures.get(name).map(|signature| signature.result)
                }
            }
            ExprKind::IndirectCall { callee, .. } => {
                let function_ty = self.natural_expr_type_inner(callee, shadowed_counter)?;
                match self.types.get(function_ty.0).map(|ty| &ty.kind) {
                    Some(TTypeKind::Function { result, .. }) => Some(*result),
                    _ => None,
                }
            }
            ExprKind::ToLong { .. } => Some(Ty::Long),
            ExprKind::Cast { ty, .. } => self.parse_type(ty).ok(),
            ExprKind::Unary { op, value, .. } => match op {
                UnaryOp::Not => Some(Ty::Bool),
                UnaryOp::Neg => self.natural_expr_type_inner(value, shadowed_counter),
            },
            ExprKind::Take(value) => self.natural_expr_type_inner(value, shadowed_counter),
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
                    TTypeKind::Array { element, .. }
                    | TTypeKind::List { element, .. }
                    | TTypeKind::Queue { element, .. }
                    | TTypeKind::Ring { element, .. }
                    | TTypeKind::Grid { element, .. } => Some(element),
                    _ => None,
                }
            }
            ExprKind::GridIndex { receiver, .. } => {
                let receiver_ty = self.natural_expr_type_inner(receiver, shadowed_counter)?;
                match self.types[receiver_ty.0].kind {
                    TTypeKind::Grid { element, .. } => Some(element),
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
                    (TTypeKind::Array { .. }, "len")
                    | (TTypeKind::Grid { .. }, "width" | "height")
                    | (
                        TTypeKind::List { .. } | TTypeKind::Queue { .. } | TTypeKind::Ring { .. },
                        "count",
                    ) => Some(Ty::Long),
                    (
                        TTypeKind::List { element, .. }
                        | TTypeKind::Queue { element, .. }
                        | TTypeKind::Ring { element, .. },
                        "pop" | "peek",
                    ) => Some(self.option_type(element, expr.span)),
                    (TTypeKind::Ring { .. }, "push") => Some(Ty::Unit),
                    (TTypeKind::List { .. } | TTypeKind::Queue { .. }, "push") => {
                        let full_ty = self.type_ids["Full"];
                        Some(self.intern_generic(
                            2,
                            Ty::Unit,
                            full_ty,
                            "Result<(), Full>".to_owned(),
                            expr.span,
                            TTypeKind::Result(Ty::Unit, full_ty),
                        ))
                    }
                    (TTypeKind::Pool { element, .. }, "get" | "remove") => {
                        Some(self.option_type(element, expr.span))
                    }
                    (TTypeKind::Pool { .. }, "contains") => Some(Ty::Bool),
                    (TTypeKind::Pool { .. }, "count") => Some(Ty::Long),
                    (TTypeKind::Pool { owner, .. }, "add") => {
                        let id_ty = self.intern_id(owner, expr.span);
                        let full_ty = self.type_ids["Full"];
                        Some(self.intern_generic(
                            2,
                            id_ty,
                            full_ty,
                            format!("Result<{}, Full>", self.type_name(id_ty)),
                            expr.span,
                            TTypeKind::Result(id_ty, full_ty),
                        ))
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
            ExprKind::Take(value) => {
                self.collect_loop_constraints_expr(value, counter, expected, constraints)
            }
            ExprKind::ByteString(_) => {}
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
            ExprKind::IndirectCall { callee, args } => {
                self.collect_loop_constraints_expr(callee, counter, None, constraints);
                for arg in args {
                    self.collect_loop_constraints_expr(arg, counter, None, constraints);
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
            ExprKind::GridIndex { receiver, x, y, .. } => {
                self.collect_loop_constraints_expr(receiver, counter, None, constraints);
                self.collect_loop_constraints_expr(x, counter, Some(Ty::Long), constraints);
                self.collect_loop_constraints_expr(y, counter, Some(Ty::Long), constraints);
            }
            ExprKind::ListLiteral
            | ExprKind::PoolLiteral
            | ExprKind::MapLiteral
            | ExprKind::SetLiteral
            | ExprKind::QueueLiteral
            | ExprKind::RingLiteral => {}
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
        if matches!(&receiver.kind, ExprKind::Name(type_name) if type_name == "Ascii")
            && name == "empty"
        {
            if !args.is_empty() {
                return Err(CheckError {
                    span: method_span,
                    message: "Ascii.empty() takes no arguments".to_owned(),
                });
            }
            let Some(ty) = expected.filter(|ty| self.is_ascii(*ty)) else {
                return Err(CheckError {
                    span: method_span,
                    message: "Ascii.empty() needs a maximum from its destination; add an Ascii max N annotation".to_owned(),
                });
            };
            return Ok((TExprKind::AsciiEmpty, ty));
        }
        let typed_collection = self.check_expr(receiver, None)?;
        if let Some(max_bytes) = self.ascii_max(typed_collection.ty) {
            match name {
                "len" if args.is_empty() => {
                    let range = TypeRangeAst {
                        lower: 0,
                        upper: max_bytes as i128,
                        inclusive: true,
                        span: method_span,
                    };
                    let result = self.intern_refinement(
                        Ty::Long,
                        range,
                        RefinePolicy::Checked,
                        method_span,
                    )?;
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Method {
                            kind: MethodKind::AsciiLen,
                            receiver: Box::new(typed_collection),
                        },
                        result,
                    ));
                }
                "try_append" => {
                    if args.len() != 1 {
                        return Err(CheckError {
                            span: method_span,
                            message: "Ascii.try_append(value) takes one Ascii value".to_owned(),
                        });
                    }
                    let place = self.resolve_place(receiver).map_err(|_| CheckError {
                        span: receiver.span,
                        message:
                            "Ascii.try_append needs a mutable builder; use a var or grow parameter"
                                .to_owned(),
                    })?;
                    if !self.place_is_mutable(&place) {
                        return Err(CheckError {
                            span: receiver.span,
                            message:
                                "Ascii.try_append needs a mutable builder; declare it with var"
                                    .to_owned(),
                        });
                    }
                    if place.root < self.function_param_count()
                        && self
                            .binding_by_id(place.root)
                            .is_some_and(|binding| binding.mode != ParamMode::Grow)
                    {
                        return Err(CheckError {
                            span: receiver.span,
                            message: "Ascii.try_append through a parameter requires 'grow' mode; 'write' cannot increase its length".to_owned(),
                        });
                    }
                    self.ascii_lengths.remove(&place.root);
                    let argument = self.check_expr(&args[0], None)?;
                    if !self.is_ascii(argument.ty) {
                        return Err(CheckError {
                            span: args[0].span,
                            message: format!(
                                "try_append needs Ascii; found {}",
                                self.type_name(argument.ty)
                            ),
                        });
                    }
                    let full = self.type_ids["Full"];
                    let result = self.intern_generic(
                        2,
                        Ty::Unit,
                        full,
                        "Result<(), Full>".to_owned(),
                        method_span,
                        TTypeKind::Result(Ty::Unit, full),
                    );
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::AsciiTryAppend {
                            receiver: Box::new(typed_collection),
                            argument: Box::new(argument),
                        },
                        result,
                    ));
                }
                _ => {}
            }
        }
        if let TTypeKind::Capability(kind) = self.types[typed_collection.ty.0].kind {
            match kind {
                CapabilityKind::Env if name == "args" => {
                    if !args.is_empty() {
                        return Err(CheckError {
                            span: method_span,
                            message: "Env.args() takes no arguments".to_owned(),
                        });
                    }
                    self.require_manifest_capability("env", method_span)?;
                    let result = self.type_ids["Args"];
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Call {
                            target: CallTarget::EnvArgs,
                            args: vec![typed_collection],
                            effect: Effect::None,
                        },
                        result,
                    ));
                }
                CapabilityKind::Args if name == "count" && args.is_empty() => {
                    let result = Ty::Long;
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Call {
                            target: CallTarget::ArgsCount,
                            args: vec![typed_collection],
                            effect: Effect::None,
                        },
                        result,
                    ));
                }
                CapabilityKind::Args if name == "get" => {
                    if args.len() != 1 {
                        return Err(CheckError {
                            span: method_span,
                            message: "Args.get(index) takes one long index".to_owned(),
                        });
                    }
                    let index = self.check_expr(&args[0], Some(Ty::Long))?;
                    let result = self.option_type(self.type_ids["Arg"], method_span);
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Call {
                            target: CallTarget::ArgsGet,
                            args: vec![typed_collection, index],
                            effect: Effect::None,
                        },
                        result,
                    ));
                }
                CapabilityKind::Arg if matches!(name, "count" | "len") && args.is_empty() => {
                    let result = Ty::Long;
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Call {
                            target: CallTarget::ArgLength,
                            args: vec![typed_collection],
                            effect: Effect::None,
                        },
                        result,
                    ));
                }
                CapabilityKind::Arg if name == "get" => {
                    if args.len() != 1 {
                        return Err(CheckError {
                            span: method_span,
                            message: "Arg.get(index) takes one long index".to_owned(),
                        });
                    }
                    let index = self.check_expr(&args[0], Some(Ty::Long))?;
                    let result = self.option_type(self.type_ids["byte"], method_span);
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Call {
                            target: CallTarget::ArgByte,
                            args: vec![typed_collection, index],
                            effect: Effect::None,
                        },
                        result,
                    ));
                }
                CapabilityKind::Fs => {
                    self.require_manifest_capability("fs", method_span)?;
                    let path = |checker: &mut Checker, expr: &Expr| -> Result<TExpr, CheckError> {
                        if matches!(expr.kind, ExprKind::ByteString(_)) {
                            return checker.check_expr(expr, Some(checker.type_ids["Path"]));
                        }
                        let typed = checker.check_expr(expr, None)?;
                        if typed.ty == checker.type_ids["Arg"] || checker.is_byte_list(typed.ty) {
                            Ok(typed)
                        } else {
                            Err(CheckError {
                                span: expr.span,
                                message: "filesystem paths must be Arg or a bounded byte list"
                                    .to_owned(),
                            })
                        }
                    };
                    let io_error = self.type_ids["IoError"];
                    match name {
                        "read" => {
                            if args.len() != 2 {
                                return Err(CheckError {
                                    span: method_span,
                                    message:
                                        "fs.read(path, buffer) takes a path and a write byte list"
                                            .to_owned(),
                                });
                            }
                            let typed_path = path(self, &args[0])?;
                            let typed_buffer = self.check_expr(&args[1], None)?;
                            if !self.is_byte_list(typed_buffer.ty) {
                                return Err(CheckError {
                                    span: args[1].span,
                                    message: "fs.read buffer must be a bounded byte list"
                                        .to_owned(),
                                });
                            }
                            let place = self.resolve_place(&args[1]).map_err(|_| CheckError {
                                span: args[1].span,
                                message:
                                    "fs.read buffer must be a mutable list passed by write mode"
                                        .to_owned(),
                            })?;
                            if !self.place_is_mutable(&place) {
                                return Err(CheckError { span: args[1].span, message: "fs.read buffer must be mutable; use var or a write parameter".to_owned() });
                            }
                            let result = self.intern_generic(
                                2,
                                Ty::Unit,
                                io_error,
                                "Result<(), IoError>".to_owned(),
                                span,
                                TTypeKind::Result(Ty::Unit, io_error),
                            );
                            if let Some(want) = expected {
                                self.type_mismatch(result, want, span)?;
                            }
                            return Ok((
                                TExprKind::Call {
                                    target: CallTarget::FsRead,
                                    args: vec![typed_collection, typed_path, typed_buffer],
                                    effect: Effect::None,
                                },
                                result,
                            ));
                        }
                        "list" => {
                            if args.len() != 2 {
                                return Err(CheckError { span: method_span, message: "fs.list(dir, entries) takes a directory and a write list of DirEntry".to_owned() });
                            }
                            let typed_dir = path(self, &args[0])?;
                            let typed_entries = self.check_expr(&args[1], None)?;
                            let TTypeKind::List { element, .. } =
                                self.types[typed_entries.ty.0].kind
                            else {
                                return Err(CheckError {
                                    span: args[1].span,
                                    message: "fs.list output must be a bounded list<DirEntry, N>"
                                        .to_owned(),
                                });
                            };
                            if element != self.type_ids["DirEntry"] {
                                return Err(CheckError {
                                    span: args[1].span,
                                    message: "fs.list output must be a bounded list<DirEntry, N>"
                                        .to_owned(),
                                });
                            }
                            let place = self.resolve_place(&args[1]).map_err(|_| CheckError {
                                span: args[1].span,
                                message:
                                    "fs.list output must be mutable; use var or a write parameter"
                                        .to_owned(),
                            })?;
                            if !self.place_is_mutable(&place) {
                                return Err(CheckError { span: args[1].span, message: "fs.list output must be mutable; use var or a write parameter".to_owned() });
                            }
                            let result = self.intern_generic(
                                2,
                                Ty::Unit,
                                io_error,
                                "Result<(), IoError>".to_owned(),
                                span,
                                TTypeKind::Result(Ty::Unit, io_error),
                            );
                            if let Some(want) = expected {
                                self.type_mismatch(result, want, span)?;
                            }
                            return Ok((
                                TExprKind::Call {
                                    target: CallTarget::FsList,
                                    args: vec![typed_collection, typed_dir, typed_entries],
                                    effect: Effect::None,
                                },
                                result,
                            ));
                        }
                        "write" => {
                            if args.len() != 2 {
                                return Err(CheckError {
                                    span: method_span,
                                    message: "fs.write(path, data) takes a path and a byte list"
                                        .to_owned(),
                                });
                            }
                            let typed_path = path(self, &args[0])?;
                            let typed_data = path(self, &args[1])?;
                            let result = self.intern_generic(
                                2,
                                Ty::Unit,
                                io_error,
                                "Result<(), IoError>".to_owned(),
                                span,
                                TTypeKind::Result(Ty::Unit, io_error),
                            );
                            if let Some(want) = expected {
                                self.type_mismatch(result, want, span)?;
                            }
                            return Ok((
                                TExprKind::Call {
                                    target: CallTarget::FsWrite,
                                    args: vec![typed_collection, typed_path, typed_data],
                                    effect: Effect::None,
                                },
                                result,
                            ));
                        }
                        "join" => {
                            if args.len() != 2 {
                                return Err(CheckError {
                                    span: method_span,
                                    message: "fs.join(dir, name) takes two bounded paths"
                                        .to_owned(),
                                });
                            }
                            let dir = path(self, &args[0])?;
                            let name = path(self, &args[1])?;
                            let path_ty = self.type_ids["Path"];
                            let result = self.intern_generic(
                                2,
                                path_ty,
                                io_error,
                                "Result<Path, IoError>".to_owned(),
                                span,
                                TTypeKind::Result(path_ty, io_error),
                            );
                            if let Some(want) = expected {
                                self.type_mismatch(result, want, span)?;
                            }
                            return Ok((
                                TExprKind::Call {
                                    target: CallTarget::FsJoin,
                                    args: vec![typed_collection, dir, name],
                                    effect: Effect::None,
                                },
                                result,
                            ));
                        }
                        _ => {
                            return Err(CheckError {
                                span: method_span,
                                message: "Fs supports read, list, write, and join".to_owned(),
                            });
                        }
                    }
                }
                CapabilityKind::Out => {
                    self.require_manifest_capability("out", method_span)?;
                    let target = match name {
                        "write" => CallTarget::OutWrite,
                        "line" => CallTarget::OutLine,
                        "int" => CallTarget::OutInt,
                        "long" => CallTarget::OutLong,
                        _ => {
                            return Err(CheckError {
                                span: method_span,
                                message: "Out supports write, line, int, and long".to_owned(),
                            });
                        }
                    };
                    let value = if matches!(target, CallTarget::OutInt) {
                        self.check_expr(
                            args.first().ok_or_else(|| CheckError {
                                span: method_span,
                                message: "out.int(n) takes one int".to_owned(),
                            })?,
                            Some(Ty::Int),
                        )?
                    } else if matches!(target, CallTarget::OutLong) {
                        self.check_expr(
                            args.first().ok_or_else(|| CheckError {
                                span: method_span,
                                message: "out.long(n) takes one long".to_owned(),
                            })?,
                            Some(Ty::Long),
                        )?
                    } else if let Some(arg) = args.first() {
                        if args.len() != 1 {
                            return Err(CheckError {
                                span: method_span,
                                message: format!("out.{}(data) takes one byte list", name),
                            });
                        }
                        if matches!(arg.kind, ExprKind::ByteString(_)) {
                            self.check_expr(arg, Some(self.type_ids["Path"]))?
                        } else {
                            let typed = self.check_expr(arg, None)?;
                            if typed.ty != self.type_ids["Arg"] && !self.is_byte_list(typed.ty) {
                                return Err(CheckError {
                                    span: arg.span,
                                    message:
                                        "out.write and out.line require Arg or a bounded byte list"
                                            .to_owned(),
                                });
                            }
                            typed
                        }
                    } else {
                        return Err(CheckError {
                            span: method_span,
                            message: format!("out.{} takes one argument", name),
                        });
                    };
                    if args.len() != 1 {
                        return Err(CheckError {
                            span: method_span,
                            message: format!("out.{} takes one argument", name),
                        });
                    }
                    let io_error = self.type_ids["IoError"];
                    let result = self.intern_generic(
                        2,
                        Ty::Unit,
                        io_error,
                        "Result<(), IoError>".to_owned(),
                        span,
                        TTypeKind::Result(Ty::Unit, io_error),
                    );
                    if let Some(want) = expected {
                        self.type_mismatch(result, want, span)?;
                    }
                    return Ok((
                        TExprKind::Call {
                            target,
                            args: vec![typed_collection, value],
                            effect: Effect::None,
                        },
                        result,
                    ));
                }
                _ => {}
            }
        }
        // The parser represents `value.field(args)` as a method call when the
        // field name also belongs to the built-in method vocabulary. Give a
        // function-typed struct field precedence in that case so function
        // fields remain callable with the ordinary call syntax.
        if let TTypeKind::Struct(fields) = &self.types[typed_collection.ty.0].kind {
            if let Some((field_index, field)) = fields
                .iter()
                .enumerate()
                .find(|(_, field)| field.name == name && self.is_function_type(field.ty))
            {
                let callee = TExpr {
                    kind: TExprKind::Field {
                        receiver: Box::new(typed_collection),
                        field_index,
                    },
                    ty: field.ty,
                    span: method_span,
                };
                return self.check_indirect_call(callee, args, method_span, expected);
            }
        }
        if let TTypeKind::Pool {
            element,
            capacity,
            owner,
        } = self.types[typed_collection.ty.0].kind
        {
            let op = match name {
                "add" => PoolOp::Add,
                "get" => PoolOp::Get,
                "remove" => PoolOp::Remove,
                "contains" => PoolOp::Contains,
                "count" => PoolOp::Count,
                _ => {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "no method '{}' on {}; available methods: add, get, remove, contains, count",
                            name,
                            self.type_name(typed_collection.ty)
                        ),
                    });
                }
            };
            let expected_args = usize::from(op != PoolOp::Count);
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
            let mut receiver_place = if matches!(op, PoolOp::Add | PoolOp::Remove) {
                let place = self.resolve_place(receiver).map_err(|_| CheckError {
                    span: receiver.span,
                    message: "a pool mutation needs a var, write parameter, or writable pool view"
                        .to_owned(),
                })?;
                if !self.place_is_mutable(&place) {
                    return Err(CheckError {
                        span: receiver.span,
                        message:
                            "a pool mutation needs mutable storage; use var or pass it as write"
                                .to_owned(),
                    });
                }
                if op == PoolOp::Remove
                    && self.active_views.iter().any(|view| {
                        places_may_prefix(
                            &self.canonical_place(&place),
                            &self.canonical_place(view),
                        )
                    })
                {
                    return Err(CheckError {
                        span: method_span,
                        message: "cannot remove from a pool while a collection view is live; collect ids and remove after the loop".to_owned(),
                    });
                }
                Some(place)
            } else {
                None
            };
            let typed_args = match op {
                PoolOp::Add => vec![self.check_store(&args[0], element)?],
                PoolOp::Get | PoolOp::Remove | PoolOp::Contains => {
                    let id_ty = self.intern_id(owner, args[0].span);
                    vec![self.check_store(&args[0], id_ty)?]
                }
                PoolOp::Count => Vec::new(),
            };
            let result = match op {
                PoolOp::Add => {
                    let id_ty = self.intern_id(owner, method_span);
                    let full_ty = self.type_ids["Full"];
                    self.intern_generic(
                        2,
                        id_ty,
                        full_ty,
                        format!("Result<{}, Full>", self.type_name(id_ty)),
                        method_span,
                        TTypeKind::Result(id_ty, full_ty),
                    )
                }
                PoolOp::Get | PoolOp::Remove => self.option_type(element, method_span),
                PoolOp::Contains => Ty::Bool,
                PoolOp::Count => self.intern_refinement(
                    Ty::Long,
                    TypeRangeAst {
                        lower: 0,
                        upper: capacity as i128,
                        inclusive: true,
                        span: method_span,
                    },
                    RefinePolicy::Checked,
                    method_span,
                )?,
            };
            if let Some(want) = expected {
                self.type_mismatch(result, want, span)?;
            }
            let count_key = receiver_place
                .as_ref()
                .and_then(|place| self.collection_count_key(place));
            let loop_proven = count_key.as_ref().is_some_and(|key| {
                self.loop_push_proofs
                    .iter()
                    .any(|proofs| proofs.contains(key))
            });
            let count_proven = loop_proven
                || (self.loop_depth == 0
                    && count_key
                        .as_ref()
                        .and_then(|key| self.collection_counts.get(key))
                        .is_some_and(|count| *count < capacity));
            let proven_success = op == PoolOp::Add && count_proven;
            if let Some(place) = receiver_place.as_mut() {
                if op == PoolOp::Add {
                    if let Some(key) = count_key {
                        let count = self.collection_counts.get(&key).copied().unwrap_or(0);
                        if proven_success {
                            self.collection_counts
                                .insert(key, count.saturating_add(1).min(capacity));
                        } else {
                            self.collection_counts.insert(key, capacity);
                        }
                    }
                } else if op == PoolOp::Remove {
                    self.invalidate_collection_counts(place);
                }
                self.invalidate_place(place);
            }
            return Ok((
                TExprKind::PoolOp {
                    op,
                    receiver: Box::new(typed_collection),
                    args: typed_args,
                    capacity,
                    proven_success,
                },
                result,
            ));
        }
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
        if let TTypeKind::Grid { width, height, .. } = self.types[typed_collection.ty.0].kind {
            let value = match name {
                "width" => width,
                "height" => height,
                _ => {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "no method '{}' on {}; available methods: width and height",
                            name,
                            self.type_name(typed_collection.ty)
                        ),
                    });
                }
            };
            if !args.is_empty() {
                return Err(CheckError {
                    span: method_span,
                    message: format!(
                        "method '{}.{}' takes no arguments",
                        self.type_name(typed_collection.ty),
                        name
                    ),
                });
            }
            if let Some(want) = expected {
                self.type_mismatch(Ty::Long, want, span)?;
            }
            return Ok((
                TExprKind::CollectionOp {
                    op: if name == "width" {
                        CollectionOp::Width
                    } else {
                        CollectionOp::Height
                    },
                    receiver: Box::new(typed_collection),
                    args: Vec::new(),
                    capacity: value,
                    proven_success: true,
                },
                Ty::Long,
            ));
        }
        if let TTypeKind::Map {
            key,
            value,
            capacity,
        } = self.types[typed_collection.ty.0].kind
        {
            let op = match name {
                "get" => MapOp::Get,
                "set" => MapOp::Set,
                "remove" => MapOp::Remove,
                "contains" => MapOp::Contains,
                "count" => MapOp::Count,
                _ => {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "no method '{}' on {}; available methods: get, set, remove, contains, count",
                            name,
                            self.type_name(typed_collection.ty)
                        ),
                    });
                }
            };
            let expected_args = match op {
                MapOp::Set => 2,
                MapOp::Count => 0,
                _ => 1,
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
            let mut receiver_place = if matches!(op, MapOp::Set | MapOp::Remove) {
                let place = self.resolve_place(receiver).map_err(|_| CheckError {
                    span: receiver.span,
                    message: "a map mutation needs a var, write parameter, or writable map view"
                        .to_owned(),
                })?;
                if !self.place_is_mutable(&place) {
                    return Err(CheckError {
                        span: receiver.span,
                        message:
                            "a map mutation needs mutable storage; use var or pass it as write"
                                .to_owned(),
                    });
                }
                if self.active_views.iter().any(|view| {
                    let receiver = self.canonical_place(&place);
                    let view = self.canonical_place(view);
                    places_may_prefix(&receiver, &view) || places_may_prefix(&view, &receiver)
                }) {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "cannot call '{}.{}' while a map view is live; move the mutation after the loop",
                            self.type_name(typed_collection.ty),
                            name
                        ),
                    });
                }
                Some(place)
            } else {
                None
            };
            let typed_args = match op {
                MapOp::Set => vec![
                    self.check_store(&args[0], key)?,
                    self.check_store(&args[1], value)?,
                ],
                MapOp::Get | MapOp::Remove | MapOp::Contains => {
                    vec![self.check_store(&args[0], key)?]
                }
                MapOp::Count => Vec::new(),
            };
            let result = match op {
                MapOp::Get | MapOp::Remove => self.option_type(value, method_span),
                MapOp::Set => {
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
                MapOp::Contains => Ty::Bool,
                MapOp::Count => self.intern_refinement(
                    Ty::Long,
                    TypeRangeAst {
                        lower: 0,
                        upper: capacity as i128,
                        inclusive: true,
                        span: method_span,
                    },
                    RefinePolicy::Checked,
                    method_span,
                )?,
            };
            if let Some(want) = expected {
                self.type_mismatch(result, want, span)?;
            }
            let count_key = receiver_place
                .as_ref()
                .and_then(|place| self.collection_count_key(place));
            let count_proven = count_key
                .as_ref()
                .and_then(|key| self.collection_counts.get(key))
                .is_some_and(|count| *count < capacity);
            let proven_success = op == MapOp::Set && count_proven;
            if let Some(place) = receiver_place.as_mut() {
                if op == MapOp::Set {
                    if let Some(key) = count_key {
                        if proven_success {
                            let current = self.collection_counts.get(&key).copied().unwrap_or(0);
                            self.collection_counts
                                .insert(key, current.saturating_add(1).min(capacity));
                        } else {
                            self.collection_counts.insert(key, capacity);
                        }
                    }
                } else {
                    self.invalidate_collection_counts(place);
                }
                self.invalidate_place(place);
            }
            return Ok((
                TExprKind::MapOp {
                    op,
                    receiver: Box::new(typed_collection),
                    args: typed_args,
                    capacity,
                    proven_success,
                },
                result,
            ));
        }
        if let TTypeKind::Set { key, capacity } = self.types[typed_collection.ty.0].kind {
            let op = match name {
                "add" => SetOp::Add,
                "remove" => SetOp::Remove,
                "contains" => SetOp::Contains,
                "count" => SetOp::Count,
                _ => {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "no method '{}' on {}; available methods: add, remove, contains, count",
                            name,
                            self.type_name(typed_collection.ty)
                        ),
                    });
                }
            };
            let expected_args = usize::from(op != SetOp::Count);
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
            let mut receiver_place = if matches!(op, SetOp::Add | SetOp::Remove) {
                let place = self.resolve_place(receiver).map_err(|_| CheckError {
                    span: receiver.span,
                    message: "a set mutation needs mutable storage; use var or pass it as write"
                        .to_owned(),
                })?;
                if !self.place_is_mutable(&place) {
                    return Err(CheckError {
                        span: receiver.span,
                        message:
                            "a set mutation needs mutable storage; use var or pass it as write"
                                .to_owned(),
                    });
                }
                if self.active_views.iter().any(|view| {
                    let receiver = self.canonical_place(&place);
                    let view = self.canonical_place(view);
                    places_may_prefix(&receiver, &view) || places_may_prefix(&view, &receiver)
                }) {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "cannot call '{}.{}' while a set view is live; move the mutation after the loop",
                            self.type_name(typed_collection.ty),
                            name
                        ),
                    });
                }
                Some(place)
            } else {
                None
            };
            let typed_args = if op == SetOp::Add || op == SetOp::Remove || op == SetOp::Contains {
                vec![self.check_store(&args[0], key)?]
            } else {
                Vec::new()
            };
            let result = match op {
                SetOp::Add => {
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
                SetOp::Remove | SetOp::Contains => Ty::Bool,
                SetOp::Count => self.intern_refinement(
                    Ty::Long,
                    TypeRangeAst {
                        lower: 0,
                        upper: capacity as i128,
                        inclusive: true,
                        span: method_span,
                    },
                    RefinePolicy::Checked,
                    method_span,
                )?,
            };
            if let Some(want) = expected {
                self.type_mismatch(result, want, span)?;
            }
            let count_key = receiver_place
                .as_ref()
                .and_then(|place| self.collection_count_key(place));
            let count_proven = count_key
                .as_ref()
                .and_then(|key| self.collection_counts.get(key))
                .is_some_and(|count| *count < capacity);
            let proven_success = op == SetOp::Add && count_proven;
            if let Some(place) = receiver_place.as_mut() {
                if op == SetOp::Add {
                    if let Some(key) = count_key {
                        if proven_success {
                            let current = self.collection_counts.get(&key).copied().unwrap_or(0);
                            self.collection_counts
                                .insert(key, current.saturating_add(1).min(capacity));
                        } else {
                            self.collection_counts.insert(key, capacity);
                        }
                    }
                } else {
                    self.invalidate_collection_counts(place);
                }
                self.invalidate_place(place);
            }
            return Ok((
                TExprKind::SetOp {
                    op,
                    receiver: Box::new(typed_collection),
                    args: typed_args,
                    capacity,
                    proven_success,
                },
                result,
            ));
        }
        if let Some((element, capacity, is_queue, is_ring)) =
            match self.types[typed_collection.ty.0].kind {
                TTypeKind::List { element, capacity } => Some((element, capacity, false, false)),
                TTypeKind::Queue { element, capacity } => Some((element, capacity, true, false)),
                TTypeKind::Ring { element, capacity } => Some((element, capacity, false, true)),
                _ => None,
            }
        {
            let op = match name {
                "push" if is_ring => CollectionOp::RingPush,
                "push" => CollectionOp::Push,
                "pop" => CollectionOp::Pop,
                "peek" if is_queue || is_ring => CollectionOp::Peek,
                "insert" if !is_queue && !is_ring => CollectionOp::Insert,
                "remove" if !is_queue && !is_ring => CollectionOp::Remove,
                "count" => CollectionOp::Count,
                "clear" if !is_queue && !is_ring => CollectionOp::Clear,
                _ => {
                    return Err(CheckError {
                        span: method_span,
                        message: format!(
                            "no method '{}' on {}; queues and rings support push, pop, peek, and count; lists support push, pop, insert, remove, count, and clear",
                            name,
                            self.type_name(typed_collection.ty)
                        ),
                    });
                }
            };
            let expected_args = match op {
                CollectionOp::Push | CollectionOp::RingPush | CollectionOp::Remove => 1,
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
            if op == CollectionOp::Count || op == CollectionOp::Peek {
                let result = if op == CollectionOp::Count {
                    self.intern_refinement(
                        Ty::Long,
                        TypeRangeAst {
                            lower: 0,
                            upper: capacity as i128,
                            inclusive: true,
                            span: method_span,
                        },
                        RefinePolicy::Checked,
                        method_span,
                    )?
                } else {
                    self.option_type(element, method_span)
                };
                if let Some(want) = expected {
                    self.type_mismatch(result, want, span)?;
                }
                return Ok((
                    TExprKind::CollectionOp {
                        op,
                        receiver: Box::new(typed_collection),
                        args: Vec::new(),
                        capacity,
                        proven_success: true,
                    },
                    result,
                ));
            }
            let mut receiver_place = self.resolve_place(receiver).map_err(|_| CheckError {
                span: receiver.span,
                message: "a collection mutation needs a var, write parameter, or writable collection view".to_owned(),
            })?;
            if !self.place_is_mutable(&receiver_place) {
                return Err(CheckError {
                    span: receiver.span,
                    message:
                        "a collection mutation needs mutable storage; use var or pass it as write"
                            .to_owned(),
                });
            }
            let count_key = self.collection_count_key(&receiver_place);
            let ring_push_safe = op == CollectionOp::RingPush
                && count_key.as_ref().is_some_and(|key| {
                    self.loop_push_proofs
                        .iter()
                        .any(|proofs| proofs.contains(key))
                        || (self.loop_depth == 0
                            && self
                                .collection_counts
                                .get(key)
                                .is_some_and(|count| *count < capacity))
                });
            let structural_view_block = matches!(
                op,
                CollectionOp::Pop
                    | CollectionOp::Insert
                    | CollectionOp::Remove
                    | CollectionOp::Clear
            );
            if (structural_view_block || (op == CollectionOp::RingPush && !ring_push_safe))
                && self.active_views.iter().any(|view| {
                    let view = self.canonical_place(view);
                    let receiver = self.canonical_place(&receiver_place);
                    places_may_prefix(&receiver, &view) || places_may_prefix(&view, &receiver)
                })
            {
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
                CollectionOp::Push | CollectionOp::RingPush => {
                    typed_args.push(self.check_store(&args[0], element)?)
                }
                CollectionOp::Insert => {
                    typed_args.push(self.check_collection_index(&args[0])?);
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
                CollectionOp::RingPush | CollectionOp::Clear => Ty::Unit,
                CollectionOp::Remove => element,
                CollectionOp::Count
                | CollectionOp::Len
                | CollectionOp::Width
                | CollectionOp::Height => Ty::Long,
                CollectionOp::Peek => unreachable!("peek handled above"),
            };
            if let Some(want) = expected {
                self.type_mismatch(result, want, span)?;
            }
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
                CollectionOp::RingPush => {
                    if let Some(key) = count_key {
                        let current = self
                            .collection_counts
                            .get(&key)
                            .copied()
                            .unwrap_or(capacity);
                        self.collection_counts
                            .insert(key, current.saturating_add(1).min(capacity));
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
                CollectionOp::Count
                | CollectionOp::Len
                | CollectionOp::Width
                | CollectionOp::Height
                | CollectionOp::Peek => {}
            }
            self.invalidate_place(&receiver_place);
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

    fn require_manifest_capability(&self, capability: &str, span: Span) -> Result<(), CheckError> {
        if self.package_capabilities.contains(capability) {
            Ok(())
        } else {
            Err(CheckError {
                span,
                message: format!(
                    "package manifest must grant capability '{}' in the 'capabilities' key",
                    capability
                ),
            })
        }
    }

    fn is_byte_type(&self, ty: Ty) -> bool {
        self.type_ids.get("byte") == Some(&ty)
    }

    fn is_byte_list(&self, ty: Ty) -> bool {
        matches!(self.types.get(ty.0).map(|ty| &ty.kind), Some(TTypeKind::List { element, .. }) if self.is_byte_type(*element))
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
            TTypeKind::Capability(_) => {
                return Err(CheckError {
                    span,
                    message:
                        "capabilities cannot be constructed in code; receive one as a parameter"
                            .to_owned(),
                });
            }
            TTypeKind::List { .. } => TExpr {
                kind: TExprKind::EmptyList,
                ty,
                span,
            },
            TTypeKind::Queue { .. } => TExpr {
                kind: TExprKind::EmptyQueue,
                ty,
                span,
            },
            TTypeKind::Ring { .. } => TExpr {
                kind: TExprKind::EmptyRing,
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
            TTypeKind::Grid {
                element, capacity, ..
            } => {
                if capacity == 0 {
                    TExpr {
                        kind: TExprKind::EmptyGrid,
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
                        TTypeKind::Array { .. }
                            | TTypeKind::List { .. }
                            | TTypeKind::Queue { .. }
                            | TTypeKind::Ring { .. }
                            | TTypeKind::Grid { .. }
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

    fn instantiate_generic_function(
        &mut self,
        name: &str,
        args: &[Expr],
        span: Span,
    ) -> Result<(usize, HashMap<String, usize>), CheckError> {
        let function = self.generic_functions[name].clone();
        if args.len() != function.params.len() {
            return Err(CheckError {
                span,
                message: format!(
                    "function '{}' takes {} argument(s), but got {}",
                    name,
                    function.params.len(),
                    args.len()
                ),
            });
        }
        let generic_names = function
            .generic_params
            .iter()
            .cloned()
            .collect::<std::collections::HashSet<_>>();
        let mut owner_substitutions = HashMap::<String, usize>::new();
        let mut capacity_substitutions = HashMap::<String, usize>::new();
        for (parameter, argument) in function.params.iter().zip(args) {
            let Some(actual_ty) = self.natural_expr_type(argument) else {
                continue;
            };
            self.unify_generic_type(
                &parameter.ty,
                actual_ty,
                &generic_names,
                &mut owner_substitutions,
                &mut capacity_substitutions,
                argument.span,
            )?;
        }
        for parameter in &function.generic_params {
            if !owner_substitutions.contains_key(parameter)
                && !capacity_substitutions.contains_key(parameter)
            {
                return Err(CheckError {
                    span,
                    message: format!(
                        "cannot infer generic parameter '{}'; pass a pool or id that determines it",
                        parameter
                    ),
                });
            }
        }
        let capacity_key = function
            .generic_params
            .iter()
            .filter_map(|parameter| capacity_substitutions.get(parameter).copied())
            .collect::<Vec<_>>();
        let key = function
            .generic_params
            .iter()
            .filter_map(|parameter| {
                capacity_substitutions
                    .get(parameter)
                    .map(|capacity| format!("{}=capacity{}", parameter, capacity))
            })
            .collect::<Vec<_>>();
        if let Some(id) = self
            .generic_specializations
            .get(&(name.to_owned(), key.clone()))
        {
            return Ok((*id, owner_substitutions));
        }
        let capacity_identity = (name.to_owned(), capacity_key.clone());
        if !self.capacity_instantiations.contains(&capacity_identity)
            && self.capacity_instantiations.len() >= 10_000
        {
            return Err(CheckError {
                span,
                message: "generic capacity instantiation limit (10,000) exceeded; reduce the number of distinct capacity arguments".to_owned(),
            });
        }
        self.capacity_instantiations.insert(capacity_identity);
        let mut owner_placeholders = HashMap::new();
        for parameter in &function.generic_params {
            if !owner_substitutions.contains_key(parameter) {
                continue;
            }
            let placeholder_key = (name.to_owned(), parameter.clone());
            let placeholder = if let Some(owner) = self
                .generic_function_owner_placeholders
                .get(&placeholder_key)
                .copied()
            {
                owner
            } else {
                let owner = self.fresh_owner(format!("{name}.{parameter}"));
                self.generic_function_owner_placeholders
                    .insert(placeholder_key, owner);
                owner
            };
            owner_placeholders.insert(parameter.clone(), placeholder);
        }
        let id = self.ast_functions.len();
        let previous_owners =
            std::mem::replace(&mut self.current_generic_owners, owner_placeholders.clone());
        let previous_capacities = std::mem::replace(
            &mut self.current_generic_capacities,
            capacity_substitutions.clone(),
        );
        let params = function
            .params
            .iter()
            .map(|parameter| {
                Ok(ParamSignature {
                    ty: self.parse_type(&parameter.ty)?,
                    mode: parameter.mode,
                })
            })
            .collect::<Result<Vec<_>, CheckError>>();
        let result = function
            .result
            .as_ref()
            .map(|result| self.parse_type(result))
            .transpose();
        self.current_generic_owners = previous_owners;
        self.current_generic_capacities = previous_capacities;
        let params = params?;
        let result = result?.unwrap_or(Ty::Unit);
        if self.type_contains_pool(result) {
            return Err(CheckError {
                span: function.span,
                message: "a value containing a pool cannot be returned; pool owners cannot escape a function".to_owned(),
            });
        }
        let mut specialized = function;
        specialized.generic_params.clear();
        specialized.name = format!("{}$instance{}", name, id);
        self.ast_functions.push(specialized);
        self.function_signatures
            .insert(id, Signature { id, params, result });
        self.function_owner_substitutions
            .insert(id, owner_placeholders);
        self.function_capacity_substitutions
            .insert(id, capacity_substitutions);
        self.generic_specializations
            .insert((name.to_owned(), key), id);
        Ok((id, owner_substitutions))
    }

    fn substitute_signature_owners(
        &mut self,
        signature: Signature,
        substitutions: &HashMap<usize, usize>,
        span: Span,
    ) -> Result<Signature, CheckError> {
        if substitutions.is_empty() {
            return Ok(signature);
        }
        let mut memo = HashMap::new();
        let mut params = Vec::with_capacity(signature.params.len());
        for parameter in signature.params {
            params.push(ParamSignature {
                ty: self.substitute_owner_type(parameter.ty, substitutions, &mut memo, span)?,
                mode: parameter.mode,
            });
        }
        let result =
            self.substitute_owner_type(signature.result, substitutions, &mut memo, span)?;
        Ok(Signature {
            id: signature.id,
            params,
            result,
        })
    }

    fn unify_generic_type(
        &self,
        pattern: &TypeAst,
        actual: Ty,
        generic_names: &std::collections::HashSet<String>,
        owners: &mut HashMap<String, usize>,
        capacities: &mut HashMap<String, usize>,
        span: Span,
    ) -> Result<(), CheckError> {
        let owner_pattern = |ast: &TypeAst| {
            generic_names.contains(&ast.name) && ast.args.is_empty() && ast.const_args.is_empty()
        };
        let bind_owner = |parameter: &str,
                          owner: usize,
                          owners: &mut HashMap<String, usize>|
         -> Result<(), CheckError> {
            if let Some(previous) = owners.insert(parameter.to_owned(), owner) {
                if previous != owner {
                    let expected = self
                        .owner_labels
                        .get(&previous)
                        .map(String::as_str)
                        .unwrap_or("one pool");
                    let got = self
                        .owner_labels
                        .get(&owner)
                        .map(String::as_str)
                        .unwrap_or("another pool");
                    return Err(CheckError {
                        span,
                        message: format!(
                            "generic owner '{}' was inferred as both '{}' and '{}'; pass ids from one pool",
                            parameter, expected, got
                        ),
                    });
                }
            }
            Ok(())
        };
        let bind_capacity = |parameter: &str,
                             capacity: usize,
                             capacities: &mut HashMap<String, usize>|
         -> Result<(), CheckError> {
            if let Some(previous) = capacities.insert(parameter.to_owned(), capacity) {
                if previous != capacity {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "generic capacity '{}' was inferred as both {} and {}; pass pools with matching capacities",
                            parameter, previous, capacity
                        ),
                    });
                }
            }
            Ok(())
        };

        match pattern.name.as_str() {
            "pool" => {
                let TTypeKind::Pool {
                    element,
                    capacity,
                    owner,
                } = self.types[actual.0].kind
                else {
                    return Ok(());
                };
                if let Some(Expr {
                    kind: ExprKind::Name(parameter),
                    ..
                }) = pattern.const_args.first()
                {
                    if generic_names.contains(parameter) {
                        bind_capacity(parameter, capacity, capacities)?;
                    }
                }
                if let Some(owner_ast) = pattern.args.get(1).filter(|owner| owner_pattern(owner)) {
                    bind_owner(&owner_ast.name, owner, owners)?;
                }
                if let Some(element_pattern) = pattern.args.first() {
                    self.unify_generic_type(
                        element_pattern,
                        element,
                        generic_names,
                        owners,
                        capacities,
                        span,
                    )?;
                }
            }
            "Id" => {
                if let TTypeKind::Id { owner } = self.types[actual.0].kind {
                    if let Some(owner_ast) =
                        pattern.args.first().filter(|owner| owner_pattern(owner))
                    {
                        bind_owner(&owner_ast.name, owner, owners)?;
                    }
                }
            }
            "Option" => {
                if let (TTypeKind::Option(actual), Some(pattern)) =
                    (&self.types[actual.0].kind, pattern.args.first())
                {
                    self.unify_generic_type(
                        pattern,
                        *actual,
                        generic_names,
                        owners,
                        capacities,
                        span,
                    )?;
                }
            }
            "Result" => {
                if let TTypeKind::Result(ok, err) = self.types[actual.0].kind {
                    if let Some(pattern) = pattern.args.first() {
                        self.unify_generic_type(
                            pattern,
                            ok,
                            generic_names,
                            owners,
                            capacities,
                            span,
                        )?;
                    }
                    if let Some(pattern) = pattern.args.get(1) {
                        self.unify_generic_type(
                            pattern,
                            err,
                            generic_names,
                            owners,
                            capacities,
                            span,
                        )?;
                    }
                }
            }
            name if !pattern.args.is_empty() => {
                if let Some(base) = self.type_ids.get(name).copied() {
                    let actual_base = self
                        .specialized_struct_base
                        .get(&actual)
                        .copied()
                        .unwrap_or(actual);
                    if actual_base == base {
                        let actual_owners = self
                            .specialized_struct_owners
                            .get(&actual)
                            .cloned()
                            .unwrap_or_default();
                        let params = self
                            .struct_decls
                            .get(&base)
                            .map(|declaration| declaration.generic_params.clone())
                            .unwrap_or_default();
                        for ((pattern, parameter), owner) in
                            pattern.args.iter().zip(params).zip(actual_owners)
                        {
                            if owner_pattern(pattern) {
                                bind_owner(&parameter, owner, owners)?;
                            }
                        }
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn visible_value_type(&self, name: &str) -> Option<Ty> {
        self.find_binding(name)
            .map(|binding| binding.ty)
            .or_else(|| {
                self.global_ids
                    .get(name)
                    .and_then(|id| self.global_types.get(*id).and_then(|ty| *ty))
            })
            .or_else(|| {
                self.constant_ids
                    .get(name)
                    .and_then(|id| self.constant_types.get(*id).copied())
            })
    }

    fn check_indirect_call(
        &mut self,
        callee: TExpr,
        args: &[Expr],
        span: Span,
        expected: Option<Ty>,
    ) -> Result<(TExprKind, Ty), CheckError> {
        let (params, result) = match &self.types[callee.ty.0].kind {
            TTypeKind::Function { params, result, .. } => (params.clone(), *result),
            _ => {
                return Err(CheckError {
                    span,
                    message: format!(
                        "value of type {} cannot be called; use a function-typed value",
                        self.type_name(callee.ty)
                    ),
                });
            }
        };
        if args.len() != params.len() {
            return Err(CheckError {
                span,
                message: format!(
                    "function value takes {} argument(s), but got {}",
                    params.len(),
                    args.len()
                ),
            });
        }
        let typed_params = params.clone();
        let mut typed_args = Vec::with_capacity(args.len());
        let mut places = Vec::<(Option<TPlace>, ParamMode)>::new();
        for (arg, param) in args.iter().zip(params) {
            let place = self.resolve_place(arg).ok();
            for (previous, previous_mode) in &places {
                if (param.mode != ParamMode::Read || *previous_mode != ParamMode::Read)
                    && previous.as_ref().zip(place.as_ref()).is_some_and(|(a, b)| {
                        places_overlap(&self.canonical_place(a), &self.canonical_place(b))
                    })
                {
                    return Err(CheckError {
                        span: arg.span,
                        message: "arguments overlap, and at least one is passed as write; pass separate fields or a copy".to_owned(),
                    });
                }
            }
            if param.mode != ParamMode::Read {
                let Some(place) = place.clone() else {
                    return Err(CheckError {
                        span: arg.span,
                        message: "a write argument must be an assignable place".to_owned(),
                    });
                };
                if !self.place_is_mutable(&place) {
                    return Err(CheckError {
                        span: arg.span,
                        message: "a write argument must be a var, a field of a var, or another write parameter".to_owned(),
                    });
                }
                let canonical = self.canonical_place(&place);
                let write_collection = matches!(
                    self.types[place.ty.0].kind,
                    TTypeKind::Map { .. } | TTypeKind::Set { .. }
                );
                if self.active_views.iter().any(|view| {
                    let view = self.canonical_place(view);
                    let replaces_map_value = view.path.len() == canonical.path.len()
                        && view.path.last().is_some_and(|projection| {
                            matches!(projection, TProjection::Index { is_map: true, .. })
                        });
                    places_overlap(&view, &canonical)
                        && (write_collection
                            || replaces_map_value
                            || !places_proven_prefix(&view, &canonical))
                }) {
                    return Err(CheckError {
                        span: arg.span,
                        message: "cannot pass storage containing a live collection view as write"
                            .to_owned(),
                    });
                }
                if param.mode == ParamMode::Grow {
                    let actual_max = self.ascii_max(place.ty);
                    let expected_max = self.ascii_max(param.ty);
                    if actual_max
                        .zip(expected_max)
                        .is_none_or(|(actual, expected)| actual < expected)
                    {
                        return Err(CheckError {
                            span: arg.span,
                            message: format!(
                                "grow argument needs an Ascii builder with at least {} bytes reserved; found {}",
                                expected_max.unwrap_or(0),
                                self.type_name(place.ty)
                            ),
                        });
                    }
                } else if place.ty != param.ty {
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
                if param.mode == ParamMode::Grow {
                    self.ascii_lengths.remove(&place.root);
                }
                typed_args.push(if param.mode == ParamMode::Grow {
                    self.check_expr(arg, None)?
                } else {
                    self.check_expr(arg, Some(param.ty))?
                });
            } else {
                typed_args.push(self.check_store(arg, param.ty)?);
            }
            places.push((place, param.mode));
        }
        if let Some(want) = expected {
            self.type_mismatch(result, want, span)?;
        }
        let callsite_id = self.next_indirect_call;
        self.next_indirect_call += 1;
        if !self.checking_constant
            && !self.checking_global_initializer
            && self.current_function < self.ast_functions.len() + self.ast_tests.len()
        {
            self.indirect_calls.push(IndirectCallSite {
                id: callsite_id,
                from: self.current_function,
                function_ty: callee.ty,
                span,
            });
        }
        Ok((
            TExprKind::IndirectCall {
                callsite_id,
                callee: Box::new(callee),
                args: typed_args,
                params: typed_params,
            },
            result,
        ))
    }

    fn record_sort_specialization(
        &mut self,
        element: Ty,
        capacity: usize,
        span: Span,
    ) -> Result<(), CheckError> {
        self.sort_specializations.insert((element, capacity));
        if self.sort_specializations.len() > 1_000 {
            return Err(CheckError {
                span,
                message: "sorting exceeds the 1,000 element-type/capacity specialization limit; reduce the number of distinct types and capacities".to_owned(),
            });
        }
        Ok(())
    }

    fn check_sort_scratch(
        &mut self,
        storage_ty: Ty,
        _input_place: &TPlace,
        _span: Span,
    ) -> Result<(), CheckError> {
        self.sort_scratch_specializations
            .insert((self.current_function, storage_ty));
        Ok(())
    }

    fn check_sort_input(
        &mut self,
        expr: &Expr,
        input_name: &str,
        span: Span,
        require_write: bool,
        check_natural_order: bool,
    ) -> Result<(TExpr, TPlace, Ty, usize, bool), CheckError> {
        let collection = self.check_expr(expr, None)?;
        let (element, capacity, is_list) = match self.types[collection.ty.0].kind {
            TTypeKind::Array { element, capacity } => (element, capacity, false),
            TTypeKind::List { element, capacity } => (element, capacity, true),
            _ => {
                return Err(CheckError {
                    span,
                    message: format!(
                        "{} expects a list<T, N> or array T[N]; found {}",
                        input_name,
                        self.type_name(collection.ty)
                    ),
                });
            }
        };
        if check_natural_order {
            let base = self.base_type(element);
            let naturally_ordered = matches!(
                self.types[base.0].kind,
                TTypeKind::Int | TTypeKind::Long | TTypeKind::Bool
            ) || matches!(&self.types[base.0].kind, TTypeKind::Enum(cases) if cases.iter().all(|case| case.payload.is_empty()));
            if !naturally_ordered {
                return Err(CheckError {
                    span,
                    message: format!(
                        "sort supports integer, bool, and payload-free enum elements; use sort_by for {}",
                        self.type_name(element)
                    ),
                });
            }
        }
        let place = self.resolve_place(expr).map_err(|_| CheckError {
            span: expr.span,
            message: "sorting needs a writable list or array place; use var or pass it as write"
                .to_owned(),
        })?;
        if require_write && !self.place_is_mutable(&place) {
            return Err(CheckError {
                span: expr.span,
                message: "sorting needs mutable storage; use var or pass it as write".to_owned(),
            });
        }
        if require_write
            && self.active_views.iter().any(|view| {
                let view = self.canonical_place(view);
                let receiver = self.canonical_place(&place);
                places_may_prefix(&receiver, &view) || places_may_prefix(&view, &receiver)
            })
        {
            return Err(CheckError {
                span,
                message: "cannot sort a collection while one of its views is live; move sorting after the loop".to_owned(),
            });
        }
        self.record_sort_specialization(element, capacity, span)?;
        if require_write {
            self.check_sort_scratch(collection.ty, &place, span)?;
        }
        Ok((collection, place, element, capacity, is_list))
    }

    fn sort_callback_type(&mut self, context: Ty, element: Ty, span: Span) -> Ty {
        self.intern_function_type(
            vec![
                TFunctionTypeParam {
                    ty: context,
                    mode: ParamMode::Read,
                },
                TFunctionTypeParam {
                    ty: element,
                    mode: ParamMode::Read,
                },
                TFunctionTypeParam {
                    ty: element,
                    mode: ParamMode::Read,
                },
            ],
            Ty::Bool,
            TFunctionEffects::default(),
            span,
        )
    }

    fn check_sort_builtin(
        &mut self,
        name: &str,
        args: &[Expr],
        span: Span,
    ) -> Result<(TExprKind, Ty), CheckError> {
        match name {
            "sort" => {
                if args.len() != 1 {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "sort takes one writable list or array; got {} arguments",
                            args.len()
                        ),
                    });
                }
                if self.checking_constant || self.checking_global_initializer {
                    return Err(CheckError {
                        span,
                        message: "sort cannot run during constant or global initialization; sort from a function".to_owned(),
                    });
                }
                let (collection, _, _, capacity, is_list) =
                    self.check_sort_input(&args[0], "sort", span, true, true)?;
                Ok((
                    TExprKind::Call {
                        target: CallTarget::Sort { capacity, is_list },
                        args: vec![collection],
                        effect: Effect::None,
                    },
                    Ty::Unit,
                ))
            }
            "sort_by" => {
                if args.len() != 3 {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "sort_by takes a writable list or array, a context, and a comparator; got {} arguments",
                            args.len()
                        ),
                    });
                }
                if self.checking_constant || self.checking_global_initializer {
                    return Err(CheckError {
                        span,
                        message: "sort_by cannot run during constant or global initialization; sort from a function".to_owned(),
                    });
                }
                let (collection, collection_place, element, capacity, is_list) =
                    self.check_sort_input(&args[0], "sort_by", span, true, false)?;
                let context = self.check_expr(&args[1], None)?;
                if self.type_contains_pool(context.ty)
                    && !matches!(self.types[context.ty.0].kind, TTypeKind::Pool { .. })
                {
                    return Err(CheckError {
                        span: args[1].span,
                        message: "sort_by context cannot contain a pool; pass a read-only value or a pool directly".to_owned(),
                    });
                }
                if let Some(context_place) = self.resolve_place(&args[1]).ok() {
                    if places_overlap(
                        &self.canonical_place(&collection_place),
                        &self.canonical_place(&context_place),
                    ) {
                        return Err(CheckError {
                            span: args[1].span,
                            message: "sort_by context overlaps the collection being sorted; pass a separate copy".to_owned(),
                        });
                    }
                }
                let callback_ty = self.sort_callback_type(context.ty, element, args[2].span);
                let comparator_use_start = self.function_value_uses.len();
                let comparator =
                    self.check_expr(&args[2], Some(callback_ty))
                        .map_err(|mut error| {
                            if error.message.contains("extra effect '") {
                                error.message.push_str("; a sort comparator must be pure");
                            }
                            error
                        })?;
                for usage in &mut self.function_value_uses[comparator_use_start..] {
                    usage.sort_comparator = true;
                }
                let callsite_id = self.next_indirect_call;
                self.next_indirect_call += 1;
                if self.current_function < self.ast_functions.len() + self.ast_tests.len() {
                    self.indirect_calls.push(IndirectCallSite {
                        id: callsite_id,
                        from: self.current_function,
                        function_ty: comparator.ty,
                        span: args[2].span,
                    });
                }
                Ok((
                    TExprKind::Call {
                        target: CallTarget::SortBy {
                            callsite_id,
                            capacity,
                            is_list,
                        },
                        args: vec![collection, context, comparator],
                        effect: Effect::None,
                    },
                    Ty::Unit,
                ))
            }
            "binary_search" => {
                if args.len() != 2 {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "binary_search takes a list or array and a key; got {} arguments",
                            args.len()
                        ),
                    });
                }
                let collection = self.check_expr(&args[0], None)?;
                let (element, capacity, is_list) = match self.types[collection.ty.0].kind {
                    TTypeKind::Array { element, capacity } => (element, capacity, false),
                    TTypeKind::List { element, capacity } => (element, capacity, true),
                    _ => {
                        return Err(CheckError {
                            span: args[0].span,
                            message: format!(
                                "binary_search expects an integer list or array; found {}",
                                self.type_name(collection.ty)
                            ),
                        });
                    }
                };
                if !matches!(self.base_type(element), Ty::Int | Ty::Long) {
                    return Err(CheckError {
                        span: args[0].span,
                        message: format!(
                            "binary_search supports integer elements; found {}",
                            self.type_name(element)
                        ),
                    });
                }
                self.record_sort_specialization(element, capacity, span)?;
                let key = self.check_store(&args[1], element)?;
                let result = self.option_type(Ty::Long, span);
                Ok((
                    TExprKind::Call {
                        target: CallTarget::BinarySearch { capacity, is_list },
                        args: vec![collection, key],
                        effect: Effect::None,
                    },
                    result,
                ))
            }
            _ => unreachable!(),
        }
    }

    fn check_expr(&mut self, expr: &Expr, expected: Option<Ty>) -> Result<TExpr, CheckError> {
        match &expr.kind {
            ExprKind::Call {
                name,
                call_span,
                args,
            } => self.check_call_expr(expr, name, call_span, args, expected),
            ExprKind::IndirectCall { callee, args } => {
                let typed_callee = self.check_expr(callee, None)?;
                let checked = self.check_indirect_call(typed_callee, args, expr.span, expected)?;
                self.finish_expr_allow_never(expr, checked, expected)
            }
            ExprKind::MethodCall {
                receiver,
                name,
                method_span,
                args,
            } => {
                let checked = self.check_method_call(
                    receiver,
                    name,
                    *method_span,
                    args,
                    expected,
                    expr.span,
                )?;
                self.finish_expr_allow_never(expr, checked, expected)
            }
            ExprKind::Binary {
                op,
                operator_span,
                left,
                right,
            } => {
                let saved_suppression = self.suppress_function_value_effect_check;
                if matches!(op, BinaryOp::Eq | BinaryOp::Ne) {
                    self.suppress_function_value_effect_check = true;
                }
                let checked = self.check_binary_expr(*op, left, right, expected, *operator_span);
                self.suppress_function_value_effect_check = saved_suppression;
                // The AST span covers the full binary construct. Keep the
                // operator as the diagnostic/runtime anchor, as it was before
                // spans were widened for the syntax tree.
                let mut checked = self.finish_expr_allow_never(expr, checked?, expected)?;
                checked.span = *operator_span;
                Ok(checked)
            }
            ExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                let checked = self.check_if(
                    condition,
                    then_block,
                    else_block.as_ref(),
                    expected,
                    true,
                    expr.span,
                )?;
                self.finish_expr_allow_never(expr, (checked.kind, checked.ty), expected)
            }
            ExprKind::Match { scrutinee, arms } => {
                let checked = self.check_match(scrutinee, arms, expected, expr.span)?;
                self.finish_expr_allow_never(expr, checked, expected)
            }
            _ => self.check_expr_inner(expr, expected),
        }
    }

    #[inline(never)]
    fn check_call_expr(
        &mut self,
        expr: &Expr,
        name: &String,
        call_span: &Span,
        args: &[Expr],
        expected: Option<Ty>,
    ) -> Result<TExpr, CheckError> {
        if !self.generic_functions.contains_key(name) && self.visible_value_type(name).is_none() {
            if let Some(signature) = self.signatures.get(name).cloned() {
                return self
                    .check_direct_function_call(expr, name, call_span, args, expected, signature);
            }
        }
        self.check_call_expr_general(expr, name, call_span, args, expected)
    }

    #[inline(never)]
    fn check_direct_function_call(
        &mut self,
        expr: &Expr,
        name: &String,
        call_span: &Span,
        args: &[Expr],
        expected: Option<Ty>,
        signature: Signature,
    ) -> Result<TExpr, CheckError> {
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
            for (previous, previous_param) in arg_places.iter().zip(signature.params.iter()) {
                if (param.mode != ParamMode::Read || previous_param.mode != ParamMode::Read)
                    && previous.as_ref().zip(place.as_ref()).is_some_and(|(a, b)| {
                        places_overlap(&self.canonical_place(a), &self.canonical_place(b))
                    })
                {
                    return Err(CheckError { span: arg.span, message: "arguments overlap, and at least one is passed as write; pass separate fields or a copy".to_owned() });
                }
            }
            if param.mode != ParamMode::Read {
                let place = place.clone().ok_or_else(|| CheckError {
                    span: arg.span,
                    message: "a write argument must be an assignable place".to_owned(),
                })?;
                if !self.place_is_mutable(&place) {
                    return Err(CheckError { span: arg.span, message: "a write argument must be a var, a field of a var, or another write parameter".to_owned() });
                }
                let canonical = self.canonical_place(&place);
                let write_collection = matches!(
                    self.types[place.ty.0].kind,
                    TTypeKind::Map { .. } | TTypeKind::Set { .. }
                );
                if self.active_views.iter().any(|view| {
                    let view = self.canonical_place(view);
                    let replaces_map_value = view.path.len() == canonical.path.len()
                        && view.path.last().is_some_and(|projection| {
                            matches!(projection, TProjection::Index { is_map: true, .. })
                        });
                    places_overlap(&view, &canonical)
                        && (write_collection
                            || replaces_map_value
                            || !places_proven_prefix(&view, &canonical))
                }) {
                    return Err(CheckError {
                        span: arg.span,
                        message: "cannot pass storage containing a live collection view as write"
                            .to_owned(),
                    });
                }
                let same_embedded_pool_shape = self.type_contains_pool(param.ty)
                    && self.specialized_struct_base.get(&place.ty) == Some(&param.ty)
                    && !self.specialized_struct_owners.contains_key(&place.ty);
                if param.mode == ParamMode::Grow {
                    let actual_max = self.ascii_max(place.ty);
                    let expected_max = self.ascii_max(param.ty);
                    if actual_max
                        .zip(expected_max)
                        .is_none_or(|(actual, expected)| actual < expected)
                    {
                        return Err(CheckError {
                            span: arg.span,
                            message: format!(
                                "grow argument needs an Ascii builder with at least {} bytes reserved; found {}",
                                expected_max.unwrap_or(0),
                                self.type_name(place.ty)
                            ),
                        });
                    }
                } else if place.ty != param.ty && !same_embedded_pool_shape {
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
                if param.mode == ParamMode::Grow {
                    self.ascii_lengths.remove(&place.root);
                }
                if param.mode == ParamMode::Grow {
                    typed_args.push(self.check_expr(arg, None)?);
                } else if same_embedded_pool_shape {
                    typed_args.push(self.check_expr(arg, None)?);
                } else {
                    typed_args.push(self.check_expr(arg, Some(param.ty))?);
                }
            } else {
                typed_args.push(self.check_store(arg, param.ty)?);
            }
            arg_places.push(place);
        }
        if let Some(want) = expected {
            self.type_mismatch(signature.result, want, *call_span)?;
        }
        if !self.checking_constant && !self.checking_global_initializer {
            self.edges.push(Edge {
                from: self.current_function,
                to: signature.id,
                span: *call_span,
            });
        }
        self.finish_expr_allow_never(
            expr,
            (
                TExprKind::Call {
                    target: CallTarget::Function(signature.id),
                    args: typed_args,
                    effect: Effect::None,
                },
                signature.result,
            ),
            expected,
        )
    }

    fn check_call_expr_general(
        &mut self,
        expr: &Expr,
        name: &String,
        call_span: &Span,
        args: &[Expr],
        expected: Option<Ty>,
    ) -> Result<TExpr, CheckError> {
        let (kind, ty) = {
            if let Some(value_ty) = self.visible_value_type(name) {
                if !self.is_function_type(value_ty) {
                    return Err(CheckError {
                        span: *call_span,
                        message: format!(
                            "value '{}' has type {} and cannot be called; use a function-typed value",
                            name,
                            self.type_name(value_ty)
                        ),
                    });
                }
                let name_expr = Expr {
                    kind: ExprKind::Name(name.clone()),
                    span: *call_span,
                };
                let callee = self.check_expr(&name_expr, None)?;
                let (kind, result) =
                    self.check_indirect_call(callee, args, *call_span, expected)?;
                return self.finish_expr(expr, (kind, result), expected);
            }
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
                        message: "default needs an expected type; add a type annotation".to_owned(),
                    });
                };
                let value = self.default_typed_value(target, *call_span)?;
                return self.finish_expr(expr, (value.kind, target), expected);
            } else if name == "str" {
                if args.len() != 1 {
                    return Err(CheckError {
                        span: *call_span,
                        message: "str takes one int or long value".to_owned(),
                    });
                }
                let value = self.check_expr(&args[0], None)?;
                if !self.is_numeric(value.ty) {
                    return Err(CheckError {
                        span: args[0].span,
                        message: format!(
                            "str needs int or long; found {}",
                            self.type_name(value.ty)
                        ),
                    });
                }
                let (lo, hi) = self.expr_range(&value).unwrap_or_else(|| {
                    self.refinement(value.ty)
                        .map(|(_, lo, hi, _)| (lo, hi))
                        .unwrap_or_else(|| integer_bounds(self.base_type(value.ty)).unwrap())
                });
                let max_abs = lo.unsigned_abs().max(hi.unsigned_abs());
                let digits = if max_abs == 0 {
                    1
                } else {
                    max_abs.ilog10() as usize + 1
                };
                let maximum = digits.saturating_add(usize::from(lo < 0));
                let ty = self.intern_ascii(maximum, *call_span);
                if let Some(want) = expected {
                    self.type_mismatch(ty, want, expr.span)?;
                }
                return self.finish_expr(
                    expr,
                    (TExprKind::AsciiFormat(Box::new(value)), ty),
                    expected,
                );
            } else if name == "ascii_upper" {
                if args.len() != 1 {
                    return Err(CheckError {
                        span: *call_span,
                        message: "ascii_upper takes one Ascii value".to_owned(),
                    });
                }
                let value = self.check_expr(&args[0], None)?;
                if !self.is_ascii(value.ty) {
                    return Err(CheckError {
                        span: args[0].span,
                        message: format!(
                            "ascii_upper needs Ascii; found {}",
                            self.type_name(value.ty)
                        ),
                    });
                }
                if let Some(want) = expected {
                    self.type_mismatch(value.ty, want, expr.span)?;
                }
                return self.finish_expr(
                    expr,
                    (TExprKind::AsciiUpper(Box::new(value.clone())), value.ty),
                    expected,
                );
            } else if matches!(name.as_str(), "sort" | "sort_by" | "binary_search") {
                let checked = self.check_sort_builtin(name, args, *call_span)?;
                return self.finish_expr(expr, checked, expected);
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
                let (element, capacity) = match self.types[target.0].kind {
                    TTypeKind::Array { element, capacity }
                    | TTypeKind::Grid {
                        element, capacity, ..
                    } => (element, capacity),
                    _ => {
                        return Err(CheckError {
                                span: *call_span,
                                message: "fill constructs a fixed array or grid; add an array or grid type annotation".to_owned(),
                            });
                    }
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
                if self.base_type(left.ty) != self.base_type(right.ty) || !self.is_numeric(left.ty)
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
                self.require_manifest_capability("out", *call_span)?;
                if args.len() != 1 {
                    return Err(CheckError {
                        span: *call_span,
                        message: format!(
                            "print takes one argument, but got {}; call print(value)",
                            args.len()
                        ),
                    });
                }
                let suppress_value_check = matches!(&args[0].kind, ExprKind::Name(value)
                        if self.signatures.contains_key(value)
                            && self.find_binding(value).is_none()
                            && !self.global_ids.contains_key(value)
                            && !self.constant_ids.contains_key(value));
                let saved_suppression = self.suppress_function_value_effect_check;
                self.suppress_function_value_effect_check |= suppress_value_check;
                let checked_arg = self.check_expr(&args[0], None);
                self.suppress_function_value_effect_check = saved_suppression;
                let arg = checked_arg?;
                if !matches!(self.base_type(arg.ty), Ty::Int | Ty::Long | Ty::Bool)
                    && !self.is_ascii(arg.ty)
                    && !self.types[arg.ty.0].is_sum()
                    && !matches!(self.types[arg.ty.0].kind, TTypeKind::Struct(_))
                    && !matches!(
                        self.types[arg.ty.0].kind,
                        TTypeKind::Array { .. }
                            | TTypeKind::List { .. }
                            | TTypeKind::Queue { .. }
                            | TTypeKind::Ring { .. }
                            | TTypeKind::Grid { .. }
                            | TTypeKind::Map { .. }
                            | TTypeKind::Set { .. }
                            | TTypeKind::Pool { .. }
                            | TTypeKind::Function { .. }
                    )
                {
                    return Err(CheckError {
                            span: args[0].span,
                            message: "print supports int, long, bool, Ascii, enum, struct, array, list, queue, ring, grid, map, set, pool, and function values"
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
                let signature = if self.generic_functions.contains_key(name) {
                    let (id, actual_owners) =
                        self.instantiate_generic_function(name, args, *call_span)?;
                    let placeholders = self
                        .function_owner_substitutions
                        .get(&id)
                        .cloned()
                        .unwrap_or_default();
                    let owner_remap = placeholders
                        .iter()
                        .filter_map(|(parameter, placeholder)| {
                            actual_owners
                                .get(parameter)
                                .map(|actual| (*placeholder, *actual))
                        })
                        .collect::<HashMap<_, _>>();
                    let signature = self.substitute_signature_owners(
                        self.function_signatures[&id].clone(),
                        &owner_remap,
                        *call_span,
                    )?;
                    signature
                } else if let Some(signature) = self.signatures.get(name).cloned() {
                    signature
                } else {
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
                    for (previous, previous_param) in arg_places.iter().zip(signature.params.iter())
                    {
                        if (param.mode == ParamMode::Write
                            || previous_param.mode == ParamMode::Write)
                            && previous.as_ref().zip(place.as_ref()).is_some_and(|(a, b)| {
                                places_overlap(&self.canonical_place(a), &self.canonical_place(b))
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
                        let write_collection = matches!(
                            self.types[place.ty.0].kind,
                            TTypeKind::Map { .. } | TTypeKind::Set { .. }
                        );
                        if self.active_views.iter().any(|view| {
                            let view = self.canonical_place(view);
                            let replaces_map_value = view.path.len() == canonical.path.len()
                                && view.path.last().is_some_and(|projection| {
                                    matches!(projection, TProjection::Index { is_map: true, .. })
                                });
                            places_overlap(&view, &canonical)
                                && (write_collection
                                    || replaces_map_value
                                    || !places_proven_prefix(&view, &canonical))
                        }) {
                            return Err(CheckError {
                                span: arg.span,
                                message:
                                    "cannot pass storage containing a live collection view as write"
                                        .to_owned(),
                            });
                        }
                        let same_embedded_pool_shape = self.type_contains_pool(param.ty)
                            && self.specialized_struct_base.get(&place.ty) == Some(&param.ty)
                            && !self.specialized_struct_owners.contains_key(&place.ty);
                        if place.ty != param.ty && !same_embedded_pool_shape {
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
                        if same_embedded_pool_shape {
                            typed_args.push(self.check_expr(arg, None)?);
                        } else {
                            typed_args.push(self.check_expr(arg, Some(param.ty))?);
                        }
                    } else {
                        typed_args.push(self.check_store(arg, param.ty)?);
                    }
                    arg_places.push(place);
                }
                if let Some(want) = expected {
                    self.type_mismatch(signature.result, want, *call_span)?;
                }
                if !self.checking_constant && !self.checking_global_initializer {
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
        };
        self.finish_expr_allow_never(expr, (kind, ty), expected)
    }

    fn finish_expr_allow_never(
        &self,
        expr: &Expr,
        (kind, ty): (TExprKind, Ty),
        expected: Option<Ty>,
    ) -> Result<TExpr, CheckError> {
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

    fn check_expr_inner(&mut self, expr: &Expr, expected: Option<Ty>) -> Result<TExpr, CheckError> {
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
            ExprKind::ByteString(bytes) => {
                if let Some(ty) = expected.filter(|ty| self.is_byte_list(*ty)) {
                    let TTypeKind::List { capacity, .. } = self.types[ty.0].kind else {
                        unreachable!()
                    };
                    if bytes.len() > capacity {
                        return Err(CheckError {
                            span: expr.span,
                            message: format!(
                                "byte string has {} bytes, exceeding list capacity {}; increase the capacity",
                                bytes.len(),
                                capacity
                            ),
                        });
                    }
                    (TExprKind::ByteString(bytes.clone()), ty)
                } else {
                    if !bytes.is_ascii() {
                        return Err(CheckError {
                            span: expr.span,
                            message: "an Ascii literal may contain only bytes 0 through 127; encode non-ASCII text as Text".to_owned(),
                        });
                    }
                    let ty = self.intern_ascii(bytes.len(), expr.span);
                    if let Some(want) = expected {
                        self.type_mismatch(ty, want, expr.span)?;
                    }
                    (TExprKind::ByteString(bytes.clone()), ty)
                }
            }
            ExprKind::Take(value) => {
                if self.conditional_depth > 0 {
                    return Err(CheckError {
                        span: expr.span,
                        message: "a move inside a branch can have two different owners; move the value before the branch or copy it".to_owned(),
                    });
                }
                let place = self.resolve_place(value).map_err(|_| CheckError {
                    span: value.span,
                    message: "take needs a local Ascii value; use 'let copy = value' to copy it"
                        .to_owned(),
                })?;
                if !place.path.is_empty() || !self.is_ascii(place.ty) {
                    return Err(CheckError {
                        span: value.span,
                        message: "take currently moves a whole local Ascii value; use 'let copy = value' for other values".to_owned(),
                    });
                }
                if place.root < self.function_param_count() {
                    return Err(CheckError {
                        span: value.span,
                        message: "take cannot move a caller-owned parameter; copy it into a local builder first".to_owned(),
                    });
                }
                if self.loop_depth > 0
                    && self.binding_by_id(place.root).is_some_and(|binding| {
                        binding.scope_depth <= *self.loop_outer_depths.last().unwrap_or(&0)
                    })
                {
                    return Err(CheckError {
                        span: expr.span,
                        message: "cannot move a value from outside a loop into its iteration; copy it inside the loop".to_owned(),
                    });
                }
                let typed = self.check_expr(value, None)?;
                self.moved_locals.insert(place.root);
                (TExprKind::Take(Box::new(typed.clone())), typed.ty)
            }
            ExprKind::Name(name) => {
                if let Some(value) = self.current_generic_capacities.get(name).copied() {
                    let ty = expected
                        .filter(|ty| self.is_numeric(*ty))
                        .map(|ty| self.base_type(ty))
                        .unwrap_or(if value <= i32::MAX as usize {
                            Ty::Int
                        } else {
                            Ty::Long
                        });
                    if value > i128::MAX as usize {
                        return Err(CheckError {
                            span: expr.span,
                            message: "generic capacity does not fit long".to_owned(),
                        });
                    }
                    (TExprKind::Integer(value as i128), ty)
                } else if let Some(binding) = self.find_binding(name) {
                    if self.moved_locals.contains(&binding.id) {
                        return Err(CheckError {
                            span: expr.span,
                            message: format!(
                                "'{}' was moved by take and cannot be used again; use the new owner or copy it before moving",
                                name
                            ),
                        });
                    }
                    if let Some(want) = expected {
                        self.type_mismatch(binding.ty, want, expr.span)?;
                    }
                    (TExprKind::Local(binding.id), binding.ty)
                } else if let Some(id) = self.global_ids.get(name).copied() {
                    let ty = self.global_types[id].expect("registered global type");
                    if let Some(want) = expected {
                        self.type_mismatch(ty, want, expr.span)?;
                    }
                    (TExprKind::Global(id), ty)
                } else if let Some(id) = self.constant_ids.get(name).copied() {
                    let ty = self.constant_types[id];
                    if let Some(want) = expected {
                        self.type_mismatch(ty, want, expr.span)?;
                    }
                    (TExprKind::Constant(id), ty)
                } else if let Some(signature) = self.signatures.get(name).cloned() {
                    let params = signature
                        .params
                        .iter()
                        .map(|param| TFunctionTypeParam {
                            ty: param.ty,
                            mode: param.mode,
                        })
                        .collect::<Vec<_>>();
                    let function_ty = self.intern_function_type(
                        params,
                        signature.result,
                        TFunctionEffects::default(),
                        expr.span,
                    );
                    let value_ty = if expected.is_some_and(|want| self.is_function_type(want)) {
                        let want = expected.unwrap();
                        self.type_mismatch(function_ty, want, expr.span)?;
                        want
                    } else {
                        if let Some(want) = expected {
                            self.type_mismatch(function_ty, want, expr.span)?;
                        }
                        function_ty
                    };
                    if !self.suppress_function_value_effect_check {
                        self.function_value_uses.push(FunctionValueUse {
                            function: signature.id,
                            function_ty: value_ty,
                            span: expr.span,
                            sort_comparator: false,
                        });
                    }
                    (TExprKind::FunctionValue(signature.id), value_ty)
                } else if self.generic_functions.contains_key(name) {
                    return Err(CheckError {
                        span: expr.span,
                        message: "owner- or capacity-generic functions cannot be stored as values yet; use a concrete wrapper function".to_owned(),
                    });
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
                if matches!(
                    self.types[typed_receiver.ty.0].kind,
                    TTypeKind::Capability(CapabilityKind::Env)
                ) {
                    let (capability, target, key) = match name.as_str() {
                        "fs" => (self.type_ids["Fs"], CallTarget::EnvFs, "fs"),
                        "out" => (self.type_ids["Out"], CallTarget::EnvOut, "out"),
                        "err" => (self.type_ids["Out"], CallTarget::EnvErr, "out"),
                        _ => {
                            return Err(CheckError {
                                span: *field_span,
                                message: format!(
                                    "Env has no field '{}'; available capabilities are args(), fs, out, and err",
                                    name
                                ),
                            });
                        }
                    };
                    self.require_manifest_capability(key, *field_span)?;
                    if let Some(want) = expected {
                        self.type_mismatch(capability, want, expr.span)?;
                    }
                    (
                        TExprKind::Call {
                            target,
                            args: vec![typed_receiver],
                            effect: Effect::None,
                        },
                        capability,
                    )
                } else {
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
                    let Some(field_index) = fields.iter().position(|field| field.name == *name)
                    else {
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
                        grid: None,
                    },
                    element,
                )
            }
            ExprKind::GridIndex {
                receiver,
                x,
                y,
                x_span,
            } => {
                let typed_receiver = self.check_expr(receiver, None)?;
                let TTypeKind::Grid {
                    element,
                    width,
                    height,
                    capacity,
                } = self.types[typed_receiver.ty.0].kind
                else {
                    return Err(CheckError {
                        span: *x_span,
                        message: format!(
                            "{} needs one index; two indexes are only valid on a grid",
                            self.type_name(typed_receiver.ty)
                        ),
                    });
                };
                let typed_x = self.check_collection_index(x)?;
                let typed_y = self.check_collection_index(y)?;
                let x_range = self.expr_range(&typed_x);
                let y_range = self.expr_range(&typed_y);
                let proven_x = x_range.is_some_and(|(lo, hi)| lo >= 0 && hi < width as i128);
                let proven_y = y_range.is_some_and(|(lo, hi)| lo >= 0 && hi < height as i128);
                if let Some(want) = expected {
                    self.type_mismatch(element, want, expr.span)?;
                }
                (
                    TExprKind::Index {
                        receiver: Box::new(typed_receiver),
                        index: Box::new(TExpr {
                            kind: TExprKind::Integer(0),
                            ty: Ty::Long,
                            span: expr.span,
                        }),
                        capacity,
                        is_list: false,
                        proven: proven_x && proven_y,
                        grid: Some(Box::new(GridIndexInfo {
                            x: typed_x,
                            y: typed_y,
                            width,
                            height,
                            proven_x,
                            proven_y,
                        })),
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
            ExprKind::QueueLiteral => {
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Queue { .. }))
                else {
                    return Err(CheckError {
                        span: expr.span,
                        message: "cannot infer the capacity for 'queue {}'; add a queue<T, N> type annotation".to_owned(),
                    });
                };
                (TExprKind::EmptyQueue, ty)
            }
            ExprKind::RingLiteral => {
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Ring { .. }))
                else {
                    return Err(CheckError {
                        span: expr.span,
                        message: "cannot infer the capacity for 'ring {}'; add a ring<T, N> type annotation".to_owned(),
                    });
                };
                (TExprKind::EmptyRing, ty)
            }
            ExprKind::PoolLiteral => {
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Pool { .. }))
                else {
                    return Err(CheckError {
                        span: expr.span,
                        message: "cannot infer the capacity and owner for 'pool {}'; add a pool<T, N> type annotation".to_owned(),
                    });
                };
                (TExprKind::EmptyPool, ty)
            }
            ExprKind::MapLiteral => {
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Map { .. }))
                else {
                    return Err(CheckError {
                        span: expr.span,
                        message: "cannot infer the key, value, and capacity for 'map {}'; add a map<K, V, N> type annotation".to_owned(),
                    });
                };
                (TExprKind::EmptyMap, ty)
            }
            ExprKind::SetLiteral => {
                let Some(ty) =
                    expected.filter(|ty| matches!(self.types[ty.0].kind, TTypeKind::Set { .. }))
                else {
                    return Err(CheckError {
                        span: expr.span,
                        message: "cannot infer the key and capacity for 'set {}'; add a set<K, N> type annotation".to_owned(),
                    });
                };
                (TExprKind::EmptySet, ty)
            }
            ExprKind::StructInit { name, fields } => {
                let Some(base_ty) = self.type_ids.get(name).copied() else {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!("unknown struct '{}'; declare it with struct", name),
                    });
                };
                let ty = expected
                    .filter(|expected| self.specialized_struct_base.get(expected) == Some(&base_ty))
                    .unwrap_or(base_ty);
                let TTypeKind::Struct(type_fields) = self.types[ty.0].kind.clone() else {
                    return Err(CheckError {
                        span: expr.span,
                        message: format!("'{}' is not a struct type", name),
                    });
                };
                let declaration = self
                    .struct_decls
                    .get(&base_ty)
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
                        TTypeKind::Array { .. }
                            | TTypeKind::List { .. }
                            | TTypeKind::Queue { .. }
                            | TTypeKind::Ring { .. }
                            | TTypeKind::Grid { .. }
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
                if self.is_ascii(target) {
                    let value = self.check_expr(value, None)?;
                    if !self.is_ascii(value.ty) {
                        return Err(CheckError {
                            span: *method_span,
                            message: format!(
                                "fit input must be Ascii; found {}",
                                self.type_name(value.ty)
                            ),
                        });
                    }
                    let option_ty = self.option_type(target, expr.span);
                    if let Some(want) = expected {
                        self.type_mismatch(option_ty, want, expr.span)?;
                    }
                    return Ok(TExpr {
                        kind: TExprKind::AsciiFit {
                            value: Box::new(value),
                            option_ty,
                        },
                        ty: option_ty,
                        span: expr.span,
                    });
                }
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
            ExprKind::Call { .. } => unreachable!("calls use the recursive-safe checker path"),
            ExprKind::IndirectCall { callee, args } => {
                let typed_callee = self.check_expr(callee, None)?;
                self.check_indirect_call(typed_callee, args, expr.span, expected)?
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
                    if !self.checking_constant && !self.checking_global_initializer {
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
                if self.is_ascii(target) {
                    let source = self.check_expr(value, None)?;
                    if !self.is_ascii(source.ty) {
                        return Err(CheckError {
                            span: value.span,
                            message: format!(
                                "cannot cast {} to Ascii; cast from an Ascii value with an explicit maximum",
                                self.type_name(source.ty)
                            ),
                        });
                    }
                    if let Some(want) = expected {
                        self.type_mismatch(target, want, expr.span)?;
                    }
                    let _ = cast_span;
                    (TExprKind::AsciiCast(Box::new(source)), target)
                } else {
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
            } => {
                let saved_suppression = self.suppress_function_value_effect_check;
                if matches!(op, BinaryOp::Eq | BinaryOp::Ne) {
                    self.suppress_function_value_effect_check = true;
                }
                let checked = self.check_binary_expr(*op, left, right, expected, *operator_span);
                self.suppress_function_value_effect_check = saved_suppression;
                checked?
            }
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
                    ..
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
            self.conditional_depth += 1;
            let checked_body = self.check_block(&arm.body, false, expected);
            self.conditional_depth -= 1;
            let typed_body = checked_body?;
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
        if op == BinaryOp::Add
            && (self.expression_may_be_ascii(left) || self.expression_may_be_ascii(right))
        {
            let left_value = self.check_expr(left, None)?;
            let right_value = self.check_expr(right, None)?;
            if self.is_ascii(left_value.ty) || self.is_ascii(right_value.ty) {
                if !self.is_ascii(left_value.ty) || !self.is_ascii(right_value.ty) {
                    return Err(self.mixed_types_error(left_value.ty, right_value.ty, span));
                }
                let left_max = self.ascii_max(left_value.ty).unwrap();
                let right_max = self.ascii_max(right_value.ty).unwrap();
                let max_bytes = left_max.checked_add(right_max).ok_or_else(|| CheckError {
                    span,
                    message:
                        "Ascii concatenation maximum overflows; reduce one of the declared maxima"
                            .to_owned(),
                })?;
                if max_bytes > i64::MAX as usize {
                    return Err(CheckError {
                        span,
                        message: "Ascii concatenation maximum overflows long; reduce one of the declared maxima".to_owned(),
                    });
                }
                let result = self.intern_ascii(max_bytes, span);
                let result = if let Some(want) = expected {
                    if let (Some(want_max), Some(_)) =
                        (self.ascii_max(want), self.ascii_max(result))
                    {
                        if max_bytes > want_max {
                            let left_range = self
                                .ascii_length_range(&left_value)
                                .unwrap_or((0, left_max));
                            let right_range = self
                                .ascii_length_range(&right_value)
                                .unwrap_or((0, right_max));
                            if left_range.1.saturating_add(right_range.1) > want_max {
                                return Err(CheckError {
                                    span,
                                    message: format!(
                                        "cannot prove this concatenation fits {}; use a checked cast or fit<{}>()",
                                        self.type_name(want),
                                        self.type_name(want)
                                    ),
                                });
                            }
                            want
                        } else {
                            result
                        }
                    } else {
                        self.type_mismatch(result, want, span)?;
                        result
                    }
                } else {
                    result
                };
                return Ok((
                    TExprKind::Binary {
                        op,
                        operator_span: span,
                        left: Box::new(left_value),
                        right: Box::new(right_value),
                    },
                    result,
                ));
            }
        }
        if matches!(
            op,
            BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt | BinaryOp::Ge
        ) && (self.expression_may_be_ascii(left) || self.expression_may_be_ascii(right))
        {
            let left_value = self.check_expr(left, None)?;
            let right_value = self.check_expr(right, None)?;
            if self.is_ascii(left_value.ty) || self.is_ascii(right_value.ty) {
                if !self.is_ascii(left_value.ty) || !self.is_ascii(right_value.ty) {
                    return Err(self.mixed_types_error(left_value.ty, right_value.ty, span));
                }
                return Ok((
                    TExprKind::Binary {
                        op,
                        operator_span: span,
                        left: Box::new(left_value),
                        right: Box::new(right_value),
                    },
                    Ty::Bool,
                ));
            }
        }
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
                let result_input = self
                    .natural_expr_type(left)
                    .is_some_and(|ty| matches!(self.types[ty.0].kind, TTypeKind::Result(_, _)));
                if result_input {
                    None
                } else {
                    Some(self.option_type(want, span))
                }
            } else {
                None
            };
            let left = self.check_expr(left, left_expected)?;
            let value_ty = match self.types[left.ty.0].kind.clone() {
                TTypeKind::Option(value) => value,
                TTypeKind::Result(_, _) => {
                    return Err(CheckError {
                        span,
                        message: "'??' works on Option only; use 'match' to handle a Result or '?' to pass its error up".to_owned(),
                    });
                }
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
            let left_natural = self.natural_expr_type(left);
            let right_natural = self.natural_expr_type(right);
            if let (Some(left_ty), Some(right_ty)) = (left_natural, right_natural) {
                if self.ascii_option_pair(left_ty, right_ty) {
                    let l = self.check_expr(left, None)?;
                    let r = self.check_expr(right, None)?;
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
            }
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
            let right_natural = self.natural_expr_type(right);
            if right_natural.is_some_and(|ty| self.types[ty.0].is_sum()) {
                let right_ty = right_natural.unwrap();
                let l = self.check_expr(left, Some(right_ty))?;
                let r = self.check_expr(right, Some(l.ty))?;
                return Ok((l, r));
            }
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
        let entry_ascii_lengths = self.ascii_lengths.clone();
        self.narrow_from_condition(&condition, true);
        self.conditional_depth += 1;
        let checked_then =
            self.check_block(then_ast, true, if value_context { expected } else { None });
        self.conditional_depth -= 1;
        let then_block = checked_then?;
        if !value_context {
            if let Some(tail) = then_block.tail.as_deref() {
                self.require_handled_result(tail, tail.span)?;
            }
        }
        let then_facts = self.facts.clone();
        let then_counts = self.collection_counts.clone();
        let then_ascii_lengths = self.ascii_lengths.clone();
        self.facts = entry_facts.clone();
        self.collection_counts = entry_counts.clone();
        self.ascii_lengths = entry_ascii_lengths.clone();
        self.narrow_from_condition(&condition, false);
        let else_block = if let Some(block) = else_ast {
            self.conditional_depth += 1;
            let checked =
                self.check_block(block, true, if value_context { expected } else { None });
            self.conditional_depth -= 1;
            Some(checked?)
        } else {
            None
        };
        if !value_context {
            if let Some(tail) = else_block.as_ref().and_then(|block| block.tail.as_deref()) {
                self.require_handled_result(tail, tail.span)?;
            }
        }
        let else_facts = self.facts.clone();
        let else_counts = self.collection_counts.clone();
        let else_ascii_lengths = self.ascii_lengths.clone();
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
        self.ascii_lengths.clear();
        let all_ascii_ids = entry_ascii_lengths
            .keys()
            .chain(then_ascii_lengths.keys())
            .chain(else_ascii_lengths.keys())
            .copied()
            .collect::<std::collections::HashSet<_>>();
        for id in all_ascii_ids {
            let then_range = then_ascii_lengths.get(&id).copied();
            let else_range = else_ascii_lengths.get(&id).copied();
            if then_range == else_range {
                if let Some(range) = then_range {
                    self.ascii_lengths.insert(id, range);
                }
            } else if let (Some(left), Some(right)) = (then_range, else_range) {
                self.ascii_lengths
                    .insert(id, (left.0.min(right.0), left.1.max(right.1)));
            }
        }
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
            } else if let (Some(left), Some(right)) =
                (self.ascii_max(then_ty), self.ascii_max(else_ty))
            {
                self.intern_ascii(left.max(right), span)
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
            ExprKind::IndirectCall { callee, args } => {
                if let Some(function_ty) = self.natural_expr_type(callee) {
                    if let TTypeKind::Function { params, .. } =
                        self.types[function_ty.0].kind.clone()
                    {
                        for (arg, param) in args.iter().zip(params) {
                            if param.mode == ParamMode::Write {
                                if let Ok(place) = self.resolve_place(arg) {
                                    writes.insert(place.root);
                                }
                            }
                        }
                    }
                }
                self.collect_expr_writes(callee, writes);
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
            ExprKind::Take(value) => self.collect_expr_writes(value, writes),
            ExprKind::GridIndex { receiver, x, y, .. } => {
                self.collect_expr_writes(receiver, writes);
                self.collect_expr_writes(x, writes);
                self.collect_expr_writes(y, writes);
            }
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
            | ExprKind::PoolLiteral
            | ExprKind::MapLiteral
            | ExprKind::SetLiteral
            | ExprKind::QueueLiteral
            | ExprKind::RingLiteral
            | ExprKind::Unit
            | ExprKind::Integer { .. }
            | ExprKind::Bool(_)
            | ExprKind::ByteString(_)
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
        let scope_depth = self.locals.len().saturating_sub(1);
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
            owner: match self.types[ty.0].kind {
                TTypeKind::Pool { owner, .. } => Some(owner),
                _ => None,
            },
            scope_depth,
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
                if let Some(binding) = self.find_binding(name) {
                    Ok(TPlace {
                        root: binding.id,
                        fields: Vec::new(),
                        path: Vec::new(),
                        ty: binding.ty,
                    })
                } else if let Some(id) = self.global_ids.get(name).copied() {
                    Ok(TPlace {
                        root: global_root(id),
                        fields: Vec::new(),
                        path: Vec::new(),
                        ty: self.global_types[id].expect("registered global type"),
                    })
                } else {
                    Err(self.unknown_local(name, expr.span))
                }
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
                    is_pool: false,
                    is_map: false,
                    proven,
                    grid: None,
                });
                place.ty = element;
                Ok(place)
            }
            ExprKind::GridIndex {
                receiver,
                x,
                y,
                x_span,
            } => {
                let mut place = self.resolve_place(receiver)?;
                let TTypeKind::Grid {
                    element,
                    width,
                    height,
                    capacity,
                } = self.types[place.ty.0].kind
                else {
                    return Err(CheckError {
                        span: *x_span,
                        message: format!(
                            "{} needs one index; two indexes are only valid on a grid",
                            self.type_name(place.ty)
                        ),
                    });
                };
                let typed_x = self.check_collection_index(x)?;
                let typed_y = self.check_collection_index(y)?;
                let proven_x = self
                    .expr_range(&typed_x)
                    .is_some_and(|(lo, hi)| lo >= 0 && hi < width as i128);
                let proven_y = self
                    .expr_range(&typed_y)
                    .is_some_and(|(lo, hi)| lo >= 0 && hi < height as i128);
                place.path.push(TProjection::Index {
                    index: TExpr {
                        kind: TExprKind::Integer(0),
                        ty: Ty::Long,
                        span: *x_span,
                    },
                    constant: None,
                    capacity,
                    is_list: false,
                    is_pool: false,
                    is_map: false,
                    proven: proven_x && proven_y,
                    grid: Some(GridIndexInfo {
                        x: typed_x,
                        y: typed_y,
                        width,
                        height,
                        proven_x,
                        proven_y,
                    }),
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
        global_from_root(place.root).is_some()
            || self
                .binding_by_id(place.root)
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
            TTypeKind::List { capacity, .. }
            | TTypeKind::Queue { capacity, .. }
            | TTypeKind::Ring { capacity, .. }
            | TTypeKind::Pool { capacity, .. } => Some(capacity),
            TTypeKind::Map { capacity, .. } | TTypeKind::Set { capacity, .. } => Some(capacity),
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

    fn check_loop_ascii_growth(
        &mut self,
        before: &HashMap<usize, (usize, usize)>,
        after: &HashMap<usize, (usize, usize)>,
        body: &TBlock,
        iterations: Option<usize>,
        loop_span: Span,
    ) -> Result<(), CheckError> {
        fn local_root(expr: &TExpr) -> Option<usize> {
            match &expr.kind {
                TExprKind::Local(id) => Some(*id),
                TExprKind::Field { receiver, .. } | TExprKind::Index { receiver, .. } => {
                    local_root(receiver)
                }
                _ => None,
            }
        }

        fn append_roots_expr(
            expr: &TExpr,
            checked: &mut std::collections::HashSet<usize>,
            plain: &mut std::collections::HashSet<usize>,
        ) {
            match &expr.kind {
                TExprKind::AsciiTryAppend { receiver, argument } => {
                    if let Some(root) = local_root(receiver) {
                        checked.insert(root);
                    }
                    append_roots_expr(argument, checked, plain);
                }
                TExprKind::Try { value, .. } => append_roots_expr(value, checked, plain),
                TExprKind::Call { args, .. }
                | TExprKind::Construct { args, .. }
                | TExprKind::CollectionOp { args, .. }
                | TExprKind::PoolOp { args, .. }
                | TExprKind::MapOp { args, .. }
                | TExprKind::SetOp { args, .. }
                | TExprKind::IndirectCall { args, .. }
                | TExprKind::OptionalCall { args, .. } => {
                    for arg in args {
                        append_roots_expr(arg, checked, plain);
                    }
                }
                TExprKind::AsciiUpper(value)
                | TExprKind::AsciiFormat(value)
                | TExprKind::AsciiCast(value)
                | TExprKind::Take(value)
                | TExprKind::OptionalToLong(value)
                | TExprKind::Field {
                    receiver: value, ..
                }
                | TExprKind::Method {
                    receiver: value, ..
                }
                | TExprKind::ToLong(value)
                | TExprKind::Cast { value, .. }
                | TExprKind::Unary { value, .. }
                | TExprKind::Convert { value, .. }
                | TExprKind::Fit { value, .. }
                | TExprKind::AsciiFit { value, .. } => append_roots_expr(value, checked, plain),
                TExprKind::Binary { left, right, .. } => {
                    append_roots_expr(left, checked, plain);
                    append_roots_expr(right, checked, plain);
                }
                TExprKind::Coalesce { option, fallback } => {
                    append_roots_expr(option, checked, plain);
                    append_roots_expr(fallback, checked, plain);
                }
                TExprKind::If {
                    condition,
                    then_block,
                    else_block,
                } => {
                    append_roots_expr(condition, checked, plain);
                    append_roots_block(then_block, checked, plain);
                    if let Some(other) = else_block {
                        append_roots_block(other, checked, plain);
                    }
                }
                TExprKind::Match { scrutinee, arms } => {
                    append_roots_expr(scrutinee, checked, plain);
                    for arm in arms {
                        append_roots_block(&arm.body, checked, plain);
                    }
                }
                TExprKind::StructConstruct { fields } => {
                    for (_, value) in fields {
                        append_roots_expr(value, checked, plain);
                    }
                }
                _ => {}
            }
        }

        fn append_roots_block(
            block: &TBlock,
            checked: &mut std::collections::HashSet<usize>,
            plain: &mut std::collections::HashSet<usize>,
        ) {
            for statement in &block.statements {
                match &statement.kind {
                    TStmtKind::Assign {
                        place,
                        op: AssignOp::Add,
                        value,
                        ..
                    } => {
                        plain.insert(place.root);
                        append_roots_expr(value, checked, plain);
                    }
                    TStmtKind::Let { value, .. }
                    | TStmtKind::Assign { value, .. }
                    | TStmtKind::Expr(value)
                    | TStmtKind::Discard(value) => append_roots_expr(value, checked, plain),
                    TStmtKind::Return(value) => {
                        if let Some(value) = value {
                            append_roots_expr(value, checked, plain);
                        }
                    }
                    TStmtKind::If {
                        condition,
                        then_block,
                        else_block,
                    } => {
                        append_roots_expr(condition, checked, plain);
                        append_roots_block(then_block, checked, plain);
                        if let Some(other) = else_block {
                            append_roots_block(other, checked, plain);
                        }
                    }
                    TStmtKind::For {
                        start, end, body, ..
                    } => {
                        append_roots_expr(start, checked, plain);
                        append_roots_expr(end, checked, plain);
                        append_roots_block(body, checked, plain);
                    }
                    TStmtKind::ForEach {
                        collection, body, ..
                    } => {
                        append_roots_expr(collection, checked, plain);
                        append_roots_block(body, checked, plain);
                    }
                    TStmtKind::Block(body) => append_roots_block(body, checked, plain),
                    TStmtKind::Expect { kind, .. } => match kind {
                        TExpectKind::Bool(value) => append_roots_expr(value, checked, plain),
                        TExpectKind::Compare { left, right, .. } => {
                            append_roots_expr(left, checked, plain);
                            append_roots_expr(right, checked, plain);
                        }
                    },
                    TStmtKind::Break | TStmtKind::Continue => {}
                }
            }
            if let Some(tail) = &block.tail {
                append_roots_expr(tail, checked, plain);
            }
        }

        let mut checked = std::collections::HashSet::new();
        let mut plain = std::collections::HashSet::new();
        append_roots_block(body, &mut checked, &mut plain);
        for id in checked.union(&plain).copied().collect::<Vec<_>>() {
            let Some(before_range) = before.get(&id).copied() else {
                continue;
            };
            let Some(max_bytes) = self
                .binding_by_id(id)
                .and_then(|binding| self.ascii_max(binding.ty))
            else {
                continue;
            };
            let name = self
                .binding_by_id(id)
                .map(|binding| binding.name.clone())
                .unwrap_or_else(|| format!("value {id}"));
            if checked.contains(&id) && !plain.contains(&id) {
                self.ascii_lengths.insert(id, (before_range.0, max_bytes));
                continue;
            }
            let Some(iterations) = iterations else {
                return Err(CheckError {
                    span: loop_span,
                    message: format!(
                        "loop growth for '{name}' has no finite bound; use '{name}.try_append(piece)' and handle Full, or bound the loop and the bytes added each iteration"
                    ),
                });
            };
            let per_iteration = after
                .get(&id)
                .map(|range| range.1.saturating_sub(before_range.1))
                .unwrap_or(max_bytes);
            let maximum = before_range
                .1
                .saturating_add(per_iteration.saturating_mul(iterations));
            if maximum > max_bytes {
                return Err(CheckError {
                    span: loop_span,
                    message: format!(
                        "loop can grow '{name}' to {maximum} bytes, above its Ascii max {max_bytes}; use '{name}.try_append(piece)' and handle Full, or reduce the loop bound or bytes appended each iteration"
                    ),
                });
            }
            self.ascii_lengths.insert(id, (before_range.0, maximum));
        }
        Ok(())
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
                    if matches!(name.as_str(), "push" | "add") {
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
                ExprKind::IndirectCall { callee, args } => {
                    expr(checker, callee, counts)
                        && args.iter().all(|arg| expr(checker, arg, counts))
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
                ExprKind::GridIndex { receiver, x, y, .. } => {
                    expr(checker, receiver, counts)
                        && expr(checker, x, counts)
                        && expr(checker, y, counts)
                }
                ExprKind::Field { receiver, .. }
                | ExprKind::Take(receiver)
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
                | ExprKind::ByteString(_)
                | ExprKind::Name(_)
                | ExprKind::ListLiteral
                | ExprKind::PoolLiteral
                | ExprKind::MapLiteral
                | ExprKind::SetLiteral
                | ExprKind::QueueLiteral
                | ExprKind::RingLiteral
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
        let root = if let Some(global) = global_from_root(place.root) {
            TExpr {
                kind: TExprKind::Global(global),
                ty: self.global_types[global].expect("registered global type"),
                span,
            }
        } else {
            let binding = self
                .binding_by_id(place.root)
                .expect("place owner exists in scope");
            TExpr {
                kind: TExprKind::Local(place.root),
                ty: binding.ty,
                span,
            }
        };
        let mut expr = root;
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
                    grid,
                    ..
                } => {
                    let element = match self.types[expr.ty.0].kind {
                        TTypeKind::Array { element, .. }
                        | TTypeKind::List { element, .. }
                        | TTypeKind::Queue { element, .. }
                        | TTypeKind::Ring { element, .. }
                        | TTypeKind::Grid { element, .. } => element,
                        _ => unreachable!("resolved place index belongs to a collection"),
                    };
                    expr = TExpr {
                        kind: TExprKind::Index {
                            receiver: Box::new(expr),
                            index: Box::new(index.clone()),
                            capacity: *capacity,
                            is_list: *is_list,
                            proven: *proven,
                            grid: grid.clone().map(Box::new),
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
        let capability = match name {
            "env" => Some(("Env", "an Env parameter")),
            "fs" => Some(("Fs", "an Fs parameter (or pass env.fs from main)")),
            "out" | "err" => Some((
                "Out",
                "an Out parameter (or pass env.out/env.err from main)",
            )),
            _ => None,
        };
        if let Some((ty, hint)) = capability {
            return CheckError {
                span,
                message: format!("function has no {ty} capability; add {hint}"),
            };
        }
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
        candidates.extend(self.generic_functions.keys().cloned());
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
            || self
                .ascii_max(actual)
                .zip(self.ascii_max(expected))
                .is_some_and(|(actual, expected)| actual <= expected)
            || (self.is_numeric(actual) && self.base_type(actual) == self.base_type(expected))
            || self.function_type_assignable(actual, expected)
        {
            Ok(())
        } else {
            if let Some(extra) = self.function_type_extra_effect(actual, expected) {
                return Err(CheckError {
                    span,
                    message: format!(
                        "function type exceeds the destination effects bound; extra effect '{}' is not allowed",
                        extra
                    ),
                });
            }
            if let Some((index, actual_mode, expected_mode)) =
                self.function_type_mode_mismatch(actual, expected)
            {
                return Err(CheckError {
                    span,
                    message: format!(
                        "function parameter {} mode mismatch: expected {}, found {}",
                        index + 1,
                        parameter_mode_name(expected_mode),
                        parameter_mode_name(actual_mode)
                    ),
                });
            }
            if let (
                TTypeKind::Id {
                    owner: actual_owner,
                },
                TTypeKind::Id {
                    owner: expected_owner,
                },
            ) = (&self.types[actual.0].kind, &self.types[expected.0].kind)
            {
                let actual_name = self
                    .owner_labels
                    .get(actual_owner)
                    .map(String::as_str)
                    .unwrap_or("other");
                let expected_name = self
                    .owner_labels
                    .get(expected_owner)
                    .map(String::as_str)
                    .unwrap_or("expected");
                return Err(CheckError {
                    span,
                    message: format!(
                        "expected {}.Id, got {}.Id; ids belong to their declaring pools",
                        expected_name, actual_name
                    ),
                });
            }
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

    fn is_function_type(&self, ty: Ty) -> bool {
        matches!(
            self.types.get(ty.0).map(|t| &t.kind),
            Some(TTypeKind::Function { .. })
        )
    }

    fn function_type_mode_mismatch(
        &self,
        actual: Ty,
        expected: Ty,
    ) -> Option<(usize, ParamMode, ParamMode)> {
        let (
            Some(TTypeKind::Function {
                params: actual_params,
                ..
            }),
            Some(TTypeKind::Function {
                params: expected_params,
                ..
            }),
        ) = (
            self.types.get(actual.0).map(|ty| &ty.kind),
            self.types.get(expected.0).map(|ty| &ty.kind),
        )
        else {
            return None;
        };
        if actual_params.len() != expected_params.len() {
            return None;
        }
        actual_params
            .iter()
            .zip(expected_params)
            .enumerate()
            .find_map(|(index, (actual, expected))| {
                (actual.ty == expected.ty && actual.mode != expected.mode).then_some((
                    index,
                    actual.mode,
                    expected.mode,
                ))
            })
    }

    fn function_type_assignable(&self, actual: Ty, expected: Ty) -> bool {
        let (
            Some(TTypeKind::Function {
                params: actual_params,
                result: actual_result,
                supports_append: actual_append,
                effects: actual_effects,
                ..
            }),
            Some(TTypeKind::Function {
                params: expected_params,
                result: expected_result,
                supports_append: expected_append,
                effects: expected_effects,
                ..
            }),
        ) = (
            self.types.get(actual.0).map(|t| &t.kind),
            self.types.get(expected.0).map(|t| &t.kind),
        )
        else {
            return false;
        };
        let result_width_fits = |actual: Ty, expected: Ty| {
            actual == expected
                || self
                    .ascii_max(actual)
                    .zip(self.ascii_max(expected))
                    .is_some_and(|(actual, expected)| actual <= expected)
                || matches!(
                    (&self.types[actual.0].kind, &self.types[expected.0].kind),
                    (
                        TTypeKind::Result(actual_ok, actual_error),
                        TTypeKind::Result(expected_ok, expected_error)
                    ) if actual_error == expected_error
                        && self.ascii_max(*actual_ok)
                            .zip(self.ascii_max(*expected_ok))
                            .is_some_and(|(actual, expected)| actual <= expected)
                )
        };
        let result_fits =
            actual_result == expected_result || result_width_fits(*actual_result, *expected_result);
        actual_params == expected_params
            && result_fits
            && (!expected_append || *actual_append)
            && self.function_effects_subset(actual_effects, expected_effects)
    }

    fn function_effects_subset(
        &self,
        actual: &TFunctionEffects,
        expected: &TFunctionEffects,
    ) -> bool {
        (!actual.out || expected.out)
            && (!actual.env || expected.env)
            && (!actual.fs_read || expected.fs_read)
            && (!actual.fs_write || expected.fs_write)
            && actual.reads.iter().all(|path| {
                expected
                    .reads
                    .iter()
                    .any(|bound| effect_path_covers(bound, path))
                    || expected
                        .writes
                        .iter()
                        .any(|bound| effect_path_covers(bound, path))
            })
            && actual.writes.iter().all(|path| {
                expected
                    .writes
                    .iter()
                    .any(|bound| effect_path_covers(bound, path))
            })
    }

    fn function_type_extra_effect(&self, actual: Ty, expected: Ty) -> Option<String> {
        let (
            TTypeKind::Function {
                params: actual_params,
                result: actual_result,
                effects: actual_effects,
                ..
            },
            TTypeKind::Function {
                params: expected_params,
                result: expected_result,
                effects: expected_effects,
                ..
            },
        ) = (
            &self.types.get(actual.0)?.kind,
            &self.types.get(expected.0)?.kind,
        )
        else {
            return None;
        };
        if actual_params != expected_params || actual_result != expected_result {
            return None;
        }
        if actual_effects.out && !expected_effects.out {
            return Some("out".to_owned());
        }
        if actual_effects.env && !expected_effects.env {
            return Some("env".to_owned());
        }
        if actual_effects.fs_read && !expected_effects.fs_read {
            return Some("fs.read".to_owned());
        }
        if actual_effects.fs_write && !expected_effects.fs_write {
            return Some("fs.write".to_owned());
        }
        actual_effects
            .reads
            .iter()
            .find(|path| {
                !expected_effects
                    .reads
                    .iter()
                    .any(|bound| effect_path_covers(bound, path))
                    && !expected_effects
                        .writes
                        .iter()
                        .any(|bound| effect_path_covers(bound, path))
            })
            .map(|path| format!("reads {path}"))
            .or_else(|| {
                actual_effects
                    .writes
                    .iter()
                    .find(|path| {
                        !expected_effects
                            .writes
                            .iter()
                            .any(|bound| effect_path_covers(bound, path))
                    })
                    .map(|path| format!("writes {path}"))
            })
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
            TExprKind::Global(id) => Some((global_root(*id), Vec::new())),
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
        if self.is_function_type(value.ty) || self.is_function_type(target) {
            self.type_mismatch(value.ty, target, value.span)?;
            return Ok(TExpr {
                ty: target,
                ..value
            });
        }
        if self
            .ascii_max(value.ty)
            .zip(self.ascii_max(target))
            .is_some_and(|(actual, expected)| actual <= expected)
        {
            return Ok(TExpr {
                ty: target,
                ..value
            });
        }
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

    fn validate_function_effect_paths(&self) -> Result<(), CheckError> {
        for (type_id, definition) in self.types.iter().enumerate() {
            let TTypeKind::Function { effects, .. } = &definition.kind else {
                continue;
            };
            for path in effects.reads.iter().chain(&effects.writes) {
                let span = self
                    .function_effect_spans
                    .get(&(Ty(type_id), path.clone()))
                    .copied()
                    .unwrap_or(definition.span);
                let mut parts = path.split('.');
                let root = parts.next().unwrap_or_default();
                let Some(global_id) = self.global_ids.get(root).copied() else {
                    return Err(CheckError {
                        span,
                        message: format!(
                            "unknown global effect path '{}'; name a global and optional struct fields",
                            path
                        ),
                    });
                };
                let Some(mut ty) = self.global_types.get(global_id).and_then(|ty| *ty) else {
                    continue;
                };
                for field_name in parts {
                    let TTypeKind::Struct(fields) = &self.types[ty.0].kind else {
                        return Err(CheckError {
                            span,
                            message: format!(
                                "global effect path '{}' continues through a non-struct field",
                                path
                            ),
                        });
                    };
                    let Some(field) = fields.iter().find(|field| field.name == field_name) else {
                        return Err(CheckError {
                            span,
                            message: format!(
                                "unknown field in global effect path '{}'; check the global's struct fields",
                                path
                            ),
                        });
                    };
                    ty = field.ty;
                }
            }
        }
        Ok(())
    }

    fn function_effect_extra(
        &self,
        actual: &GlobalEffects,
        allowed: &TFunctionEffects,
    ) -> Option<String> {
        if actual.out && !allowed.out {
            return Some("out".to_owned());
        }
        if actual.env && !allowed.env {
            return Some("env".to_owned());
        }
        if actual.fs_read && !allowed.fs_read {
            return Some("fs.read".to_owned());
        }
        if actual.fs_write && !allowed.fs_write {
            return Some("fs.write".to_owned());
        }
        for path in &actual.reads {
            let name = self.global_path_name(path);
            if !allowed
                .reads
                .iter()
                .any(|bound| effect_path_covers(bound, &name))
                && !allowed
                    .writes
                    .iter()
                    .any(|bound| effect_path_covers(bound, &name))
            {
                return Some(format!("reads {name}"));
            }
        }
        for write in &actual.writes {
            let name = self.global_path_name(&write.path);
            if !allowed
                .writes
                .iter()
                .any(|bound| effect_path_covers(bound, &name))
            {
                return Some(format!("writes {name}"));
            }
        }
        None
    }

    fn resolve_indirect_calls(
        &self,
        functions: &[TFunction],
        direct_graph: Vec<Vec<TCallEdge>>,
    ) -> Result<(Vec<Vec<TCallEdge>>, HashMap<usize, Vec<usize>>), CheckError> {
        let mut graph = direct_graph.clone();
        let mut targets = HashMap::<usize, Vec<usize>>::new();
        let mut address_taken = self
            .function_value_uses
            .iter()
            .map(|usage| usage.function)
            .collect::<Vec<_>>();
        address_taken.sort_unstable();
        address_taken.dedup();
        let mut seen_maps = Vec::<HashMap<usize, Vec<usize>>>::new();

        for _ in 0..=functions
            .len()
            .saturating_add(self.indirect_calls.len())
            .saturating_add(1)
        {
            let effects = infer_global_effects(functions, &graph);
            let mut next_targets = HashMap::<usize, Vec<usize>>::new();
            for site in &self.indirect_calls {
                let TTypeKind::Function {
                    params,
                    result,
                    effects: allowed,
                    ..
                } = &self.types[site.function_ty.0].kind
                else {
                    continue;
                };
                let mut compatible = Vec::new();
                for candidate in &address_taken {
                    let Some(function) = functions.get(*candidate) else {
                        continue;
                    };
                    if function.is_test
                        || function.result != *result
                        || function.params.len() != params.len()
                        || !function
                            .params
                            .iter()
                            .zip(params)
                            .all(|(actual, contract)| {
                                actual.ty == contract.ty && actual.mode == contract.mode
                            })
                    {
                        continue;
                    }
                    if effects
                        .get(*candidate)
                        .and_then(|summary| self.function_effect_extra(summary, allowed))
                        .is_none()
                    {
                        compatible.push(*candidate);
                    }
                }
                next_targets.insert(site.id, compatible);
            }
            let mut next_graph = direct_graph.clone();
            for site in &self.indirect_calls {
                if let Some(candidates) = next_targets.get(&site.id) {
                    for target in candidates {
                        if site.from < next_graph.len() {
                            next_graph[site.from].push(TCallEdge {
                                target: *target,
                                span: site.span,
                            });
                        }
                    }
                }
            }
            if next_targets == targets {
                graph = next_graph;
                targets = next_targets;
                break;
            }
            if seen_maps.contains(&next_targets) {
                // If recursive effect bounds oscillate, retain every reachable candidate. This
                // conservative closure keeps recursion and hidden effects visible to later checks.
                for map in seen_maps.iter().chain(std::iter::once(&next_targets)) {
                    for (site, candidates) in map {
                        let current = targets.entry(*site).or_default();
                        for candidate in candidates {
                            if !current.contains(candidate) {
                                current.push(*candidate);
                            }
                        }
                    }
                }
                graph = direct_graph.clone();
                for site in &self.indirect_calls {
                    if let Some(candidates) = targets.get(&site.id) {
                        for target in candidates {
                            if site.from < graph.len() {
                                graph[site.from].push(TCallEdge {
                                    target: *target,
                                    span: site.span,
                                });
                            }
                        }
                    }
                }
                break;
            }
            seen_maps.push(targets.clone());
            targets = next_targets;
            graph = next_graph;
        }

        let effects = infer_global_effects(functions, &graph);
        for usage in &self.function_value_uses {
            let TTypeKind::Function {
                effects: allowed, ..
            } = &self.types[usage.function_ty.0].kind
            else {
                continue;
            };
            if let Some(extra) = effects
                .get(usage.function)
                .and_then(|actual| self.function_effect_extra(actual, allowed))
            {
                return Err(CheckError {
                    span: usage.span,
                    message: if usage.sort_comparator {
                        format!(
                            "function '{}' has extra effect '{}'; a sort comparator must be pure",
                            functions[usage.function].name, extra
                        )
                    } else {
                        format!(
                            "function '{}' has extra effect '{}'; add it to the function type's effects bound",
                            functions[usage.function].name, extra
                        )
                    },
                });
            }
        }
        Ok((graph, targets))
    }

    fn check_recursion(
        &self,
        call_graph: &[Vec<TCallEdge>],
        functions: &[TFunction],
    ) -> Result<(), CheckError> {
        for component in strongly_connected_components(call_graph) {
            let cyclic = component.len() > 1
                || component
                    .first()
                    .is_some_and(|id| call_graph[*id].iter().any(|edge| edge.target == *id));
            if !cyclic {
                continue;
            }
            let mut unmarked = component
                .iter()
                .copied()
                .filter(|id| !functions[*id].recursive)
                .collect::<Vec<_>>();
            if unmarked.is_empty() {
                continue;
            }
            unmarked.sort_unstable();
            let names = unmarked
                .iter()
                .map(|id| format!("'{}'", functions[*id].name))
                .collect::<Vec<_>>()
                .join(", ");
            return Err(CheckError {
                span: functions[unmarked[0]].span,
                message: format!(
                    "call cycle contains unmarked function(s) {names}; mark every function in the cycle 'recursive'"
                ),
            });
        }
        Ok(())
    }

    fn check_recursive_regions(
        &self,
        functions: &[TFunction],
        call_graph: &[Vec<TCallEdge>],
    ) -> Result<(), CheckError> {
        let components = strongly_connected_components(call_graph);
        let mut component_of = vec![usize::MAX; functions.len()];
        let mut cyclic_component = vec![false; components.len()];
        for (component_id, component) in components.iter().enumerate() {
            for function in component {
                component_of[*function] = component_id;
            }
            cyclic_component[component_id] = component.len() > 1
                || component
                    .first()
                    .is_some_and(|id| call_graph[*id].iter().any(|edge| edge.target == *id));
        }
        for function in functions {
            let component = component_of[function.id];
            if !cyclic_component[component] {
                continue;
            }
            check_recursive_region_block(
                self,
                function,
                &function.body,
                call_graph,
                &component_of,
                &cyclic_component,
                &mut Vec::new(),
            )?;
        }
        Ok(())
    }
}

fn strongly_connected_components(call_graph: &[Vec<TCallEdge>]) -> Vec<Vec<usize>> {
    let count = call_graph.len();
    let mut visited = vec![false; count];
    let mut order = Vec::with_capacity(count);
    for root in 0..count {
        if visited[root] {
            continue;
        }
        visited[root] = true;
        let mut stack = vec![(root, 0usize)];
        while let Some((node, edge_index)) = stack.last_mut() {
            if *edge_index < call_graph[*node].len() {
                let target = call_graph[*node][*edge_index].target;
                *edge_index += 1;
                if target < count && !visited[target] {
                    visited[target] = true;
                    stack.push((target, 0));
                }
            } else {
                order.push(*node);
                stack.pop();
            }
        }
    }
    let mut reverse = vec![Vec::new(); count];
    for (from, edges) in call_graph.iter().enumerate() {
        for edge in edges {
            if edge.target < count {
                reverse[edge.target].push(from);
            }
        }
    }
    visited.fill(false);
    let mut components = Vec::new();
    for root in order.into_iter().rev() {
        if visited[root] {
            continue;
        }
        visited[root] = true;
        let mut component = Vec::new();
        let mut stack = vec![root];
        while let Some(node) = stack.pop() {
            component.push(node);
            for target in &reverse[node] {
                if !visited[*target] {
                    visited[*target] = true;
                    stack.push(*target);
                }
            }
        }
        component.sort_unstable();
        components.push(component);
    }
    components
}

fn check_recursive_region_block(
    checker: &Checker,
    function: &TFunction,
    block: &TBlock,
    call_graph: &[Vec<TCallEdge>],
    component_of: &[usize],
    cyclic_component: &[bool],
    active_regions: &mut Vec<(String, Ty)>,
) -> Result<(), CheckError> {
    for statement in &block.statements {
        match &statement.kind {
            TStmtKind::Let {
                name, ty, value, ..
            } => {
                let large = checker.type_size_checked(
                    *ty,
                    &mut vec![None; checker.types.len()],
                    statement.span,
                )? > 4_096;
                if large {
                    active_regions.push((name.clone(), *ty));
                }
                check_recursive_region_expr(
                    checker,
                    function,
                    value,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
            }
            TStmtKind::Assign { place, value, .. } => {
                check_recursive_region_place(
                    checker,
                    function,
                    place,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                check_recursive_region_expr(
                    checker,
                    function,
                    value,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
            }
            TStmtKind::Expr(value) | TStmtKind::Discard(value) => check_recursive_region_expr(
                checker,
                function,
                value,
                call_graph,
                component_of,
                cyclic_component,
                active_regions,
            )?,
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    check_recursive_region_expr(
                        checker,
                        function,
                        value,
                        call_graph,
                        component_of,
                        cyclic_component,
                        active_regions,
                    )?;
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                check_recursive_region_expr(
                    checker,
                    function,
                    condition,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                check_recursive_region_block(
                    checker,
                    function,
                    then_block,
                    call_graph,
                    component_of,
                    cyclic_component,
                    &mut active_regions.clone(),
                )?;
                if let Some(other) = else_block {
                    check_recursive_region_block(
                        checker,
                        function,
                        other,
                        call_graph,
                        component_of,
                        cyclic_component,
                        &mut active_regions.clone(),
                    )?;
                }
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                check_recursive_region_expr(
                    checker,
                    function,
                    start,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                check_recursive_region_expr(
                    checker,
                    function,
                    end,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                check_recursive_region_block(
                    checker,
                    function,
                    body,
                    call_graph,
                    component_of,
                    cyclic_component,
                    &mut active_regions.clone(),
                )?;
            }
            TStmtKind::ForEach {
                id,
                collection,
                source,
                body,
                ..
            } => {
                check_recursive_region_place(
                    checker,
                    function,
                    source,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                check_recursive_region_expr(
                    checker,
                    function,
                    collection,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                let element_ty = match &checker.types[collection.ty.0].kind {
                    TTypeKind::Array { element, .. }
                    | TTypeKind::List { element, .. }
                    | TTypeKind::Queue { element, .. }
                    | TTypeKind::Ring { element, .. }
                    | TTypeKind::Grid { element, .. }
                    | TTypeKind::Pool { element, .. }
                    | TTypeKind::Map { value: element, .. }
                    | TTypeKind::Set { key: element, .. } => Some(*element),
                    _ => None,
                };
                let mut iteration_regions = active_regions.clone();
                if let Some(element_ty) = element_ty {
                    if checker.type_size_checked(
                        element_ty,
                        &mut vec![None; checker.types.len()],
                        statement.span,
                    )? > 4_096
                    {
                        iteration_regions.push((format!("loop value {id}"), element_ty));
                    }
                }
                check_recursive_region_block(
                    checker,
                    function,
                    body,
                    call_graph,
                    component_of,
                    cyclic_component,
                    &mut iteration_regions,
                )?;
            }
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => check_recursive_region_expr(
                    checker,
                    function,
                    value,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?,
                TExpectKind::Compare { left, right, .. } => {
                    check_recursive_region_expr(
                        checker,
                        function,
                        left,
                        call_graph,
                        component_of,
                        cyclic_component,
                        active_regions,
                    )?;
                    check_recursive_region_expr(
                        checker,
                        function,
                        right,
                        call_graph,
                        component_of,
                        cyclic_component,
                        active_regions,
                    )?;
                }
            },
            TStmtKind::Block(inner) => check_recursive_region_block(
                checker,
                function,
                inner,
                call_graph,
                component_of,
                cyclic_component,
                &mut active_regions.clone(),
            )?,
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        check_recursive_region_expr(
            checker,
            function,
            tail,
            call_graph,
            component_of,
            cyclic_component,
            active_regions,
        )?;
    }
    Ok(())
}

fn typed_expr_contains_take(expr: &TExpr) -> bool {
    match &expr.kind {
        TExprKind::Take(_) => true,
        TExprKind::Construct { args, .. } => args.iter().any(typed_expr_contains_take),
        TExprKind::AsciiUpper(value)
        | TExprKind::AsciiFormat(value)
        | TExprKind::AsciiCast(value)
        | TExprKind::Convert { value, .. }
        | TExprKind::Fit { value, .. }
        | TExprKind::Try { value, .. }
        | TExprKind::OptionalToLong(value)
        | TExprKind::ToLong(value)
        | TExprKind::Cast { value, .. }
        | TExprKind::Unary { value, .. } => typed_expr_contains_take(value),
        TExprKind::AsciiFit { value, .. } => typed_expr_contains_take(value),
        TExprKind::AsciiTryAppend { receiver, argument } => {
            typed_expr_contains_take(receiver) || typed_expr_contains_take(argument)
        }
        TExprKind::Coalesce { option, fallback } => {
            typed_expr_contains_take(option) || typed_expr_contains_take(fallback)
        }
        TExprKind::Binary { left, right, .. } => {
            typed_expr_contains_take(left) || typed_expr_contains_take(right)
        }
        _ => false,
    }
}

fn check_recursive_region_expr(
    checker: &Checker,
    function: &TFunction,
    expr: &TExpr,
    call_graph: &[Vec<TCallEdge>],
    component_of: &[usize],
    cyclic_component: &[bool],
    active_regions: &mut Vec<(String, Ty)>,
) -> Result<(), CheckError> {
    let recurse = |child: &TExpr, active: &mut Vec<(String, Ty)>| {
        check_recursive_region_expr(
            checker,
            function,
            child,
            call_graph,
            component_of,
            cyclic_component,
            active,
        )
    };
    match &expr.kind {
        TExprKind::Call { args, .. }
        | TExprKind::Construct { args, .. }
        | TExprKind::IndirectCall { args, .. } => {
            if let TExprKind::IndirectCall { callee, .. } = &expr.kind {
                recurse(callee, active_regions)?;
            }
            for arg in args {
                recurse(arg, active_regions)?;
            }
        }
        TExprKind::OptionalCall { receiver, args, .. } => {
            recurse(receiver, active_regions)?;
            for arg in args {
                recurse(arg, active_regions)?;
            }
        }
        TExprKind::Method { receiver, .. }
        | TExprKind::OptionalToLong(receiver)
        | TExprKind::Field { receiver, .. }
        | TExprKind::ToLong(receiver)
        | TExprKind::Convert {
            value: receiver, ..
        }
        | TExprKind::Fit {
            value: receiver, ..
        }
        | TExprKind::Try {
            value: receiver, ..
        }
        | TExprKind::AsciiUpper(receiver)
        | TExprKind::AsciiFormat(receiver)
        | TExprKind::AsciiCast(receiver)
        | TExprKind::Take(receiver)
        | TExprKind::Cast {
            value: receiver, ..
        }
        | TExprKind::Unary {
            value: receiver, ..
        } => recurse(receiver, active_regions)?,
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            recurse(receiver, active_regions)?;
            recurse(index, active_regions)?;
            if let Some(grid) = grid {
                recurse(&grid.x, active_regions)?;
                recurse(&grid.y, active_regions)?;
            }
        }
        TExprKind::Fill { value, .. } => recurse(value, active_regions)?,
        TExprKind::CollectionOp { receiver, args, .. }
        | TExprKind::PoolOp { receiver, args, .. }
        | TExprKind::MapOp { receiver, args, .. }
        | TExprKind::SetOp { receiver, args, .. } => {
            recurse(receiver, active_regions)?;
            for arg in args {
                recurse(arg, active_regions)?;
            }
        }
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                recurse(value, active_regions)?;
            }
        }
        TExprKind::Coalesce { option, fallback } => {
            recurse(option, active_regions)?;
            recurse(fallback, active_regions)?;
        }
        TExprKind::Match { scrutinee, arms } => {
            recurse(scrutinee, active_regions)?;
            for arm in arms {
                check_recursive_region_block(
                    checker,
                    function,
                    &arm.body,
                    call_graph,
                    component_of,
                    cyclic_component,
                    &mut active_regions.clone(),
                )?;
            }
        }
        TExprKind::Return(value) => {
            if let Some(value) = value {
                recurse(value, active_regions)?;
            }
        }
        TExprKind::Binary { left, right, .. } => {
            recurse(left, active_regions)?;
            recurse(right, active_regions)?;
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            recurse(condition, active_regions)?;
            check_recursive_region_block(
                checker,
                function,
                then_block,
                call_graph,
                component_of,
                cyclic_component,
                &mut active_regions.clone(),
            )?;
            if let Some(other) = else_block {
                check_recursive_region_block(
                    checker,
                    function,
                    other,
                    call_graph,
                    component_of,
                    cyclic_component,
                    &mut active_regions.clone(),
                )?;
            }
        }
        TExprKind::Unit
        | TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Local(_)
        | TExprKind::Global(_)
        | TExprKind::Constant(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::LoopExit(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::AsciiEmpty => {}
        TExprKind::AsciiFit { value, .. } => recurse(value, active_regions)?,
        TExprKind::AsciiTryAppend { receiver, argument } => {
            recurse(receiver, active_regions)?;
            recurse(argument, active_regions)?;
        }
    }

    let component = component_of[function.id];
    let recursive_targets = call_graph[function.id]
        .iter()
        .filter(|edge| {
            edge.span.file == expr.span.file
                && edge.span.line == expr.span.line
                && edge.span.col == expr.span.col
                && component_of.get(edge.target) == Some(&component)
                && cyclic_component[component]
        })
        .map(|edge| edge.target)
        .collect::<Vec<_>>();
    if recursive_targets.is_empty() {
        return Ok(());
    }
    if let Some((name, _)) = active_regions.first() {
        return Err(CheckError {
            span: expr.span,
            message: format!(
                "large value '{name}' keeps a data-stack region alive across a recursive call; move it out of this cycle or end its scope before the call"
            ),
        });
    }
    if checker.type_size_checked(expr.ty, &mut vec![None; checker.types.len()], expr.span)? > 4_096
        && matches!(
            expr.kind,
            TExprKind::Call { .. }
                | TExprKind::IndirectCall { .. }
                | TExprKind::OptionalCall { .. }
        )
    {
        return Err(CheckError {
            span: expr.span,
            message: format!(
                "recursive call's large result destination '{}' keeps a data-stack region alive across the cycle; return a small value or end the region before recursing",
                checker.types[expr.ty.0].name
            ),
        });
    }
    let args = match &expr.kind {
        TExprKind::Call { args, .. }
        | TExprKind::Construct { args, .. }
        | TExprKind::IndirectCall { args, .. }
        | TExprKind::OptionalCall { args, .. } => args,
        _ => return Ok(()),
    };
    for arg in args {
        let is_large =
            checker.type_size_checked(arg.ty, &mut vec![None; checker.types.len()], arg.span)?
                > 4_096;
        let gathered_element =
            matches!(arg.kind, TExprKind::Field { .. } | TExprKind::Index { .. });
        if is_large && (!region_expr_is_place(arg) || gathered_element) {
            return Err(CheckError {
                span: arg.span,
                message: format!(
                    "large temporary copy of argument '{}' would keep a data-stack region alive across a recursive call; pass a borrowed local or smaller value",
                    checker.types[arg.ty.0].name
                ),
            });
        }
    }
    Ok(())
}

fn check_recursive_region_place(
    checker: &Checker,
    function: &TFunction,
    place: &TPlace,
    call_graph: &[Vec<TCallEdge>],
    component_of: &[usize],
    cyclic_component: &[bool],
    active_regions: &mut Vec<(String, Ty)>,
) -> Result<(), CheckError> {
    for projection in &place.path {
        if let TProjection::Index { index, grid, .. } = projection {
            check_recursive_region_expr(
                checker,
                function,
                index,
                call_graph,
                component_of,
                cyclic_component,
                active_regions,
            )?;
            if let Some(grid) = grid {
                check_recursive_region_expr(
                    checker,
                    function,
                    &grid.x,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
                check_recursive_region_expr(
                    checker,
                    function,
                    &grid.y,
                    call_graph,
                    component_of,
                    cyclic_component,
                    active_regions,
                )?;
            }
        }
    }
    Ok(())
}

fn region_expr_is_place(expr: &TExpr) -> bool {
    match &expr.kind {
        TExprKind::Local(_) | TExprKind::Global(_) => true,
        TExprKind::Field { receiver, .. } | TExprKind::Index { receiver, .. } => {
            region_expr_is_place(receiver)
        }
        _ => false,
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct GlobalPath {
    global: usize,
    fields: Vec<usize>,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct GlobalWrite {
    path: GlobalPath,
    structural: bool,
}

#[derive(Clone, Debug, Default)]
struct GlobalEffects {
    reads: Vec<GlobalPath>,
    writes: Vec<GlobalWrite>,
    structural_writes: Vec<GlobalPath>,
    calls: Vec<usize>,
    out: bool,
    env: bool,
    fs_read: bool,
    fs_write: bool,
}

impl GlobalEffects {
    fn add_read(&mut self, path: GlobalPath) {
        if !self.reads.contains(&path) {
            self.reads.push(path);
        }
    }

    fn add_write(&mut self, path: GlobalPath, structural: bool) {
        let write = GlobalWrite {
            path: path.clone(),
            structural,
        };
        if !self.writes.contains(&write) {
            self.writes.push(write);
        }
        if structural && !self.structural_writes.contains(&path) {
            self.structural_writes.push(path);
        }
    }

    fn add_call(&mut self, function: usize) {
        if !self.calls.contains(&function) {
            self.calls.push(function);
        }
    }
}

fn global_path_from_expr(expr: &TExpr) -> Option<GlobalPath> {
    match &expr.kind {
        TExprKind::Global(global) => Some(GlobalPath {
            global: *global,
            fields: Vec::new(),
        }),
        TExprKind::Field {
            receiver,
            field_index,
        } => {
            let mut path = global_path_from_expr(receiver)?;
            path.fields.push(*field_index);
            Some(path)
        }
        TExprKind::Index { receiver, .. } => global_path_from_expr(receiver),
        _ => None,
    }
}

fn global_path_from_place(place: &TPlace) -> Option<GlobalPath> {
    let global = global_from_root(place.root)?;
    let fields = place
        .path
        .iter()
        .filter_map(|projection| match projection {
            TProjection::Field(index) => Some(*index),
            TProjection::Index { .. } => None,
        })
        .collect();
    Some(GlobalPath { global, fields })
}

fn global_paths_overlap(left: &GlobalPath, right: &GlobalPath) -> bool {
    global_path_is_prefix(left, right) || global_path_is_prefix(right, left)
}

fn global_path_is_prefix(prefix: &GlobalPath, path: &GlobalPath) -> bool {
    prefix.global == path.global
        && prefix.fields.len() <= path.fields.len()
        && prefix
            .fields
            .iter()
            .zip(&path.fields)
            .all(|(left, right)| left == right)
}

fn effect_path_covers(bound: &str, actual: &str) -> bool {
    actual == bound
        || actual
            .strip_prefix(bound)
            .is_some_and(|suffix| suffix.starts_with('.'))
}

fn parameter_mode_name(mode: ParamMode) -> &'static str {
    match mode {
        ParamMode::Read => "read",
        ParamMode::Write => "write",
        ParamMode::Grow => "grow",
    }
}

fn infer_global_effects(
    functions: &[TFunction],
    call_graph: &[Vec<TCallEdge>],
) -> Vec<GlobalEffects> {
    let mut effects = functions
        .iter()
        .map(|function| {
            let mut effects = GlobalEffects::default();
            collect_global_block_effects(&function.body, &mut effects, functions);
            effects
        })
        .collect::<Vec<_>>();
    for (function, edges) in call_graph.iter().enumerate() {
        if let Some(effect) = effects.get_mut(function) {
            for edge in edges {
                effect.add_call(edge.target);
            }
        }
    }
    loop {
        let previous = effects.clone();
        let mut changed = false;
        for effect in &mut effects {
            let calls = effect.calls.clone();
            for target in calls {
                let Some(callee) = previous.get(target) else {
                    continue;
                };
                for read in &callee.reads {
                    if !effect.reads.contains(read) {
                        effect.reads.push(read.clone());
                        changed = true;
                    }
                }
                for write in &callee.writes {
                    if !effect.writes.contains(write) {
                        effect.writes.push(write.clone());
                        changed = true;
                    }
                }
                for write in &callee.structural_writes {
                    if !effect.structural_writes.contains(write) {
                        effect.structural_writes.push(write.clone());
                        changed = true;
                    }
                }
                if callee.out && !effect.out {
                    effect.out = true;
                    changed = true;
                }
                if callee.env && !effect.env {
                    effect.env = true;
                    changed = true;
                }
                if callee.fs_read && !effect.fs_read {
                    effect.fs_read = true;
                    changed = true;
                }
                if callee.fs_write && !effect.fs_write {
                    effect.fs_write = true;
                    changed = true;
                }
            }
        }
        if !changed {
            break;
        }
    }
    effects
}

fn close_global_effects(effects: &mut GlobalEffects, functions: &[GlobalEffects]) {
    let mut seen = std::collections::HashSet::new();
    let mut pending = effects.calls.clone();
    while let Some(target) = pending.pop() {
        if !seen.insert(target) {
            continue;
        }
        let Some(callee) = functions.get(target) else {
            continue;
        };
        for read in &callee.reads {
            effects.add_read(read.clone());
        }
        for write in &callee.writes {
            effects.add_write(write.path.clone(), write.structural);
        }
        for write in &callee.structural_writes {
            if !effects.structural_writes.contains(write) {
                effects.structural_writes.push(write.clone());
            }
        }
        effects.out |= callee.out;
        effects.env |= callee.env;
        effects.fs_read |= callee.fs_read;
        effects.fs_write |= callee.fs_write;
        pending.extend(callee.calls.iter().copied());
    }
}

fn collect_global_block_effects(
    block: &TBlock,
    effects: &mut GlobalEffects,
    functions: &[TFunction],
) {
    for statement in &block.statements {
        match &statement.kind {
            TStmtKind::Let { value, .. } | TStmtKind::Expr(value) | TStmtKind::Discard(value) => {
                collect_global_expr_effects(value, effects, functions)
            }
            TStmtKind::Assign {
                place, op, value, ..
            } => {
                if let Some(path) = global_path_from_place(place) {
                    effects.add_write(path.clone(), *op == AssignOp::Set);
                    if *op != AssignOp::Set {
                        effects.add_read(path);
                    }
                }
                for projection in &place.path {
                    if let TProjection::Index { index, .. } = projection {
                        collect_global_expr_effects(index, effects, functions);
                    }
                }
                collect_global_expr_effects(value, effects, functions);
            }
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    collect_global_expr_effects(value, effects, functions);
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                collect_global_expr_effects(condition, effects, functions);
                collect_global_block_effects(then_block, effects, functions);
                if let Some(other) = else_block {
                    collect_global_block_effects(other, effects, functions);
                }
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                collect_global_expr_effects(start, effects, functions);
                collect_global_expr_effects(end, effects, functions);
                collect_global_block_effects(body, effects, functions);
            }
            TStmtKind::ForEach {
                collection, body, ..
            } => {
                collect_global_expr_effects(collection, effects, functions);
                collect_global_block_effects(body, effects, functions);
            }
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => collect_global_expr_effects(value, effects, functions),
                TExpectKind::Compare { left, right, .. } => {
                    collect_global_expr_effects(left, effects, functions);
                    collect_global_expr_effects(right, effects, functions);
                }
            },
            TStmtKind::Block(inner) => collect_global_block_effects(inner, effects, functions),
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        collect_global_expr_effects(tail, effects, functions);
    }
}

fn collect_global_expr_effects(expr: &TExpr, effects: &mut GlobalEffects, functions: &[TFunction]) {
    match &expr.kind {
        TExprKind::Global(global) => effects.add_read(GlobalPath {
            global: *global,
            fields: Vec::new(),
        }),
        TExprKind::Field { receiver, .. } => {
            if let Some(path) = global_path_from_expr(expr) {
                effects.add_read(path);
            } else {
                collect_global_expr_effects(receiver, effects, functions);
            }
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            if let Some(path) = global_path_from_expr(expr) {
                effects.add_read(path);
            } else {
                collect_global_expr_effects(receiver, effects, functions);
            }
            if let Some(grid) = grid {
                collect_global_expr_effects(&grid.x, effects, functions);
                collect_global_expr_effects(&grid.y, effects, functions);
            } else {
                collect_global_expr_effects(index, effects, functions);
            }
        }
        TExprKind::Call { target, args, .. } => {
            match target {
                CallTarget::Function(function) => {
                    effects.add_call(*function);
                    if let Some(callee) = functions.get(*function) {
                        for (argument, parameter) in args.iter().zip(&callee.params) {
                            if parameter.mode != ParamMode::Read {
                                if let Some(path) = global_path_from_expr(argument) {
                                    effects.add_write(path, false);
                                }
                            }
                        }
                    }
                }
                CallTarget::Print
                | CallTarget::OutWrite
                | CallTarget::OutLine
                | CallTarget::OutInt
                | CallTarget::OutLong => effects.out = true,
                CallTarget::EnvArgs
                | CallTarget::ArgsCount
                | CallTarget::ArgsGet
                | CallTarget::ArgLength
                | CallTarget::ArgByte => effects.env = true,
                CallTarget::FsRead => effects.fs_read = true,
                CallTarget::FsWrite => effects.fs_write = true,
                CallTarget::FsList => effects.fs_read = true,
                CallTarget::FsJoin
                | CallTarget::EnvFs
                | CallTarget::EnvOut
                | CallTarget::EnvErr => {}
                CallTarget::Min | CallTarget::Max => {}
                CallTarget::Sort { .. } | CallTarget::SortBy { .. } => {
                    if let Some(path) = args.first().and_then(global_path_from_expr) {
                        effects.add_write(path, true);
                    }
                }
                CallTarget::BinarySearch { .. } => {}
            }
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::OptionalCall {
            receiver,
            function_id,
            args,
            ..
        } => {
            effects.add_call(*function_id);
            collect_global_expr_effects(receiver, effects, functions);
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::IndirectCall {
            callee,
            args,
            params,
            ..
        } => {
            for (argument, parameter) in args.iter().zip(params) {
                if parameter.mode != ParamMode::Read {
                    if let Some(path) = global_path_from_expr(argument) {
                        effects.add_write(path, false);
                    }
                }
            }
            collect_global_expr_effects(callee, effects, functions);
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::CollectionOp {
            op, receiver, args, ..
        } => {
            collect_global_expr_effects(receiver, effects, functions);
            if let Some(path) = global_path_from_expr(receiver) {
                match op {
                    CollectionOp::Push => effects.add_write(path, false),
                    CollectionOp::RingPush => effects.add_write(path, true),
                    CollectionOp::Pop
                    | CollectionOp::Insert
                    | CollectionOp::Remove
                    | CollectionOp::Clear => effects.add_write(path, true),
                    CollectionOp::Count
                    | CollectionOp::Len
                    | CollectionOp::Peek
                    | CollectionOp::Width
                    | CollectionOp::Height => {}
                }
            }
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::PoolOp {
            op, receiver, args, ..
        } => {
            collect_global_expr_effects(receiver, effects, functions);
            if let Some(path) = global_path_from_expr(receiver) {
                match op {
                    PoolOp::Add => effects.add_write(path, false),
                    PoolOp::Remove => effects.add_write(path, true),
                    PoolOp::Get | PoolOp::Contains | PoolOp::Count => {}
                }
            }
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::MapOp {
            op, receiver, args, ..
        } => {
            collect_global_expr_effects(receiver, effects, functions);
            if let Some(path) = global_path_from_expr(receiver) {
                match op {
                    MapOp::Set | MapOp::Remove => effects.add_write(path, true),
                    MapOp::Get | MapOp::Contains | MapOp::Count => {}
                }
            }
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::SetOp {
            op, receiver, args, ..
        } => {
            collect_global_expr_effects(receiver, effects, functions);
            if let Some(path) = global_path_from_expr(receiver) {
                match op {
                    SetOp::Add | SetOp::Remove => effects.add_write(path, true),
                    SetOp::Contains | SetOp::Count => {}
                }
            }
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::Construct { args, .. } => {
            for argument in args {
                collect_global_expr_effects(argument, effects, functions);
            }
        }
        TExprKind::Method { receiver, .. }
        | TExprKind::OptionalToLong(receiver)
        | TExprKind::ToLong(receiver) => collect_global_expr_effects(receiver, effects, functions),
        TExprKind::AsciiTryAppend { receiver, argument } => {
            collect_global_expr_effects(receiver, effects, functions);
            if let Some(path) = global_path_from_expr(receiver) {
                effects.add_write(path, false);
            }
            collect_global_expr_effects(argument, effects, functions);
        }
        TExprKind::Fill { value, .. } => collect_global_expr_effects(value, effects, functions),
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                collect_global_expr_effects(value, effects, functions);
            }
        }
        TExprKind::Convert { value, .. }
        | TExprKind::Fit { value, .. }
        | TExprKind::Try { value, .. }
        | TExprKind::AsciiUpper(value)
        | TExprKind::AsciiFormat(value)
        | TExprKind::AsciiCast(value)
        | TExprKind::Take(value)
        | TExprKind::Cast { value, .. }
        | TExprKind::Unary { value, .. } => collect_global_expr_effects(value, effects, functions),
        TExprKind::AsciiFit { value, .. } => collect_global_expr_effects(value, effects, functions),
        TExprKind::Coalesce { option, fallback } => {
            collect_global_expr_effects(option, effects, functions);
            collect_global_expr_effects(fallback, effects, functions);
        }
        TExprKind::Match { scrutinee, arms } => {
            collect_global_expr_effects(scrutinee, effects, functions);
            for arm in arms {
                collect_global_block_effects(&arm.body, effects, functions);
            }
        }
        TExprKind::Return(value) => {
            if let Some(value) = value {
                collect_global_expr_effects(value, effects, functions);
            }
        }
        TExprKind::Binary { left, right, .. } => {
            collect_global_expr_effects(left, effects, functions);
            collect_global_expr_effects(right, effects, functions);
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            collect_global_expr_effects(condition, effects, functions);
            collect_global_block_effects(then_block, effects, functions);
            if let Some(other) = else_block {
                collect_global_block_effects(other, effects, functions);
            }
        }
        TExprKind::Unit
        | TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Local(_)
        | TExprKind::Constant(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::LoopExit(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::AsciiEmpty => {}
    }
}

fn visit_global_calls_block(
    block: &TBlock,
    active_views: &mut Vec<GlobalPath>,
    check: &mut impl FnMut(&TExpr, &[GlobalPath]) -> Result<(), CheckError>,
) -> Result<(), CheckError> {
    for statement in &block.statements {
        match &statement.kind {
            TStmtKind::Let { value, .. } | TStmtKind::Expr(value) | TStmtKind::Discard(value) => {
                visit_global_calls_expr(value, active_views, check)?
            }
            TStmtKind::Assign { place, value, .. } => {
                for projection in &place.path {
                    if let TProjection::Index { index, .. } = projection {
                        visit_global_calls_expr(index, active_views, check)?;
                    }
                }
                visit_global_calls_expr(value, active_views, check)?;
            }
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    visit_global_calls_expr(value, active_views, check)?;
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                visit_global_calls_expr(condition, active_views, check)?;
                visit_global_calls_block(then_block, active_views, check)?;
                if let Some(other) = else_block {
                    visit_global_calls_block(other, active_views, check)?;
                }
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                visit_global_calls_expr(start, active_views, check)?;
                visit_global_calls_expr(end, active_views, check)?;
                visit_global_calls_block(body, active_views, check)?;
            }
            TStmtKind::ForEach {
                collection,
                source,
                body,
                ..
            } => {
                visit_global_calls_expr(collection, active_views, check)?;
                let view = global_path_from_place(source);
                if let Some(view) = &view {
                    active_views.push(view.clone());
                }
                visit_global_calls_block(body, active_views, check)?;
                if view.is_some() {
                    active_views.pop();
                }
            }
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => visit_global_calls_expr(value, active_views, check)?,
                TExpectKind::Compare { left, right, .. } => {
                    visit_global_calls_expr(left, active_views, check)?;
                    visit_global_calls_expr(right, active_views, check)?;
                }
            },
            TStmtKind::Block(inner) => visit_global_calls_block(inner, active_views, check)?,
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        visit_global_calls_expr(tail, active_views, check)?;
    }
    Ok(())
}

fn visit_global_calls_expr(
    expr: &TExpr,
    active_views: &mut Vec<GlobalPath>,
    check: &mut impl FnMut(&TExpr, &[GlobalPath]) -> Result<(), CheckError>,
) -> Result<(), CheckError> {
    let needs_global_call_check = matches!(
        &expr.kind,
        TExprKind::Call {
            target: CallTarget::Function(_) | CallTarget::SortBy { .. },
            ..
        } | TExprKind::OptionalCall { .. }
            | TExprKind::IndirectCall { .. }
    );
    if needs_global_call_check {
        check(expr, active_views)?;
    }
    match &expr.kind {
        TExprKind::Call { args, .. } | TExprKind::Construct { args, .. } => {
            for argument in args {
                visit_global_calls_expr(argument, active_views, check)?;
            }
        }
        TExprKind::OptionalCall { receiver, args, .. } => {
            visit_global_calls_expr(receiver, active_views, check)?;
            for argument in args {
                visit_global_calls_expr(argument, active_views, check)?;
            }
        }
        TExprKind::IndirectCall { callee, args, .. } => {
            visit_global_calls_expr(callee, active_views, check)?;
            for argument in args {
                visit_global_calls_expr(argument, active_views, check)?;
            }
        }
        TExprKind::Method { receiver, .. }
        | TExprKind::OptionalToLong(receiver)
        | TExprKind::Field { receiver, .. }
        | TExprKind::ToLong(receiver)
        | TExprKind::Convert {
            value: receiver, ..
        }
        | TExprKind::Fit {
            value: receiver, ..
        }
        | TExprKind::Try {
            value: receiver, ..
        }
        | TExprKind::AsciiUpper(receiver)
        | TExprKind::AsciiFormat(receiver)
        | TExprKind::AsciiCast(receiver)
        | TExprKind::Take(receiver)
        | TExprKind::Cast {
            value: receiver, ..
        }
        | TExprKind::Unary {
            value: receiver, ..
        } => {
            visit_global_calls_expr(receiver, active_views, check)?;
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            visit_global_calls_expr(receiver, active_views, check)?;
            if let Some(grid) = grid {
                visit_global_calls_expr(&grid.x, active_views, check)?;
                visit_global_calls_expr(&grid.y, active_views, check)?;
            } else {
                visit_global_calls_expr(index, active_views, check)?;
            }
        }
        TExprKind::Fill { value, .. } => visit_global_calls_expr(value, active_views, check)?,
        TExprKind::AsciiFit { value, .. } => visit_global_calls_expr(value, active_views, check)?,
        TExprKind::AsciiTryAppend { receiver, argument } => {
            visit_global_calls_expr(receiver, active_views, check)?;
            visit_global_calls_expr(argument, active_views, check)?;
        }
        TExprKind::CollectionOp { receiver, args, .. }
        | TExprKind::PoolOp { receiver, args, .. }
        | TExprKind::MapOp { receiver, args, .. }
        | TExprKind::SetOp { receiver, args, .. } => {
            visit_global_calls_expr(receiver, active_views, check)?;
            for argument in args {
                visit_global_calls_expr(argument, active_views, check)?;
            }
        }
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                visit_global_calls_expr(value, active_views, check)?;
            }
        }
        TExprKind::Coalesce { option, fallback } => {
            visit_global_calls_expr(option, active_views, check)?;
            visit_global_calls_expr(fallback, active_views, check)?;
        }
        TExprKind::Match { scrutinee, arms } => {
            visit_global_calls_expr(scrutinee, active_views, check)?;
            for arm in arms {
                visit_global_calls_block(&arm.body, active_views, check)?;
            }
        }
        TExprKind::Return(value) => {
            if let Some(value) = value {
                visit_global_calls_expr(value, active_views, check)?;
            }
        }
        TExprKind::Binary { left, right, .. } => {
            visit_global_calls_expr(left, active_views, check)?;
            visit_global_calls_expr(right, active_views, check)?;
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            visit_global_calls_expr(condition, active_views, check)?;
            visit_global_calls_block(then_block, active_views, check)?;
            if let Some(other) = else_block {
                visit_global_calls_block(other, active_views, check)?;
            }
        }
        TExprKind::Unit
        | TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Local(_)
        | TExprKind::Global(_)
        | TExprKind::Constant(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::LoopExit(_)
        | TExprKind::AsciiEmpty => {}
    }
    Ok(())
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
            (
                TProjection::Index { is_pool: left, .. },
                TProjection::Index { is_pool: right, .. },
            ) => left == right,
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
        AssignOp::Shr => BinaryOp::Shr,
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
        AssignOp::Shr => ">>",
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
