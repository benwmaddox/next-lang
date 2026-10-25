use crate::ast::{AssignOp, BinaryOp, ParamMode, RefinePolicy, Span, UnaryOp};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Ty(pub usize);

#[allow(non_upper_case_globals)]
impl Ty {
    pub const Int: Ty = Ty(0);
    pub const Long: Ty = Ty(1);
    pub const Bool: Ty = Ty(2);
    pub const Unit: Ty = Ty(3);
    pub const Never: Ty = Ty(4);

    pub fn name(self) -> &'static str {
        match self {
            Ty::Int => "int",
            Ty::Long => "long",
            Ty::Bool => "bool",
            Ty::Unit => "()",
            Ty::Never => "never",
            _ => "aggregate",
        }
    }
}

#[derive(Clone, Debug)]
pub struct TType {
    pub name: String,
    pub kind: TTypeKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum TTypeKind {
    Int,
    Long,
    Bool,
    Unit,
    Never,
    Refinement {
        base: Ty,
        min: i128,
        max: i128,
        policy: RefinePolicy,
    },
    Struct(Vec<TField>),
    Enum(Vec<TCase>),
    Option(Ty),
    Result(Ty, Ty),
    Array {
        element: Ty,
        capacity: usize,
    },
    List {
        element: Ty,
        capacity: usize,
    },
    Queue {
        element: Ty,
        capacity: usize,
    },
    Ring {
        element: Ty,
        capacity: usize,
    },
    Grid {
        element: Ty,
        width: usize,
        height: usize,
        capacity: usize,
    },
    Map {
        key: Ty,
        value: Ty,
        capacity: usize,
    },
    Set {
        key: Ty,
        capacity: usize,
    },
    Function {
        params: Vec<TFunctionTypeParam>,
        result: Ty,
        effects: TFunctionEffects,
        data_stack_requirement: u64,
    },
    Id {
        owner: usize,
    },
    Pool {
        element: Ty,
        capacity: usize,
        owner: usize,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct TFunctionTypeParam {
    pub ty: Ty,
    pub mode: ParamMode,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub struct TFunctionEffects {
    pub print: bool,
    pub reads: Vec<String>,
    pub writes: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct TField {
    pub name: String,
    pub ty: Ty,
}

pub fn base_type(mut ty: Ty, types: &[TType]) -> Ty {
    while let Some(TType {
        kind: TTypeKind::Refinement { base, .. },
        ..
    }) = types.get(ty.0)
    {
        ty = *base;
    }
    ty
}

pub fn is_numeric_type(ty: Ty, types: &[TType]) -> bool {
    matches!(base_type(ty, types), Ty::Int | Ty::Long)
}

pub fn refinement(ty: Ty, types: &[TType]) -> Option<(Ty, i128, i128, RefinePolicy)> {
    match &types.get(ty.0)?.kind {
        TTypeKind::Refinement {
            base,
            min,
            max,
            policy,
        } => Some((*base, *min, *max, *policy)),
        _ => None,
    }
}

#[derive(Clone, Debug)]
pub struct TCase {
    pub name: String,
    pub payload: Vec<Ty>,
    #[allow(dead_code)]
    pub span: Span,
}

impl TType {
    pub fn cases(&self) -> Vec<TCase> {
        match &self.kind {
            TTypeKind::Enum(cases) => cases.clone(),
            TTypeKind::Option(value) => vec![
                TCase {
                    name: "some".to_owned(),
                    payload: vec![*value],
                    span: self.span,
                },
                TCase {
                    name: "none".to_owned(),
                    payload: Vec::new(),
                    span: self.span,
                },
            ],
            TTypeKind::Result(ok, err) => vec![
                TCase {
                    name: "ok".to_owned(),
                    payload: vec![*ok],
                    span: self.span,
                },
                TCase {
                    name: "err".to_owned(),
                    payload: vec![*err],
                    span: self.span,
                },
            ],
            _ => Vec::new(),
        }
    }

    pub fn is_sum(&self) -> bool {
        matches!(
            self.kind,
            TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..)
        )
    }
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // The checker preserves the call graph for later analyses.
pub struct TProgram {
    pub functions: Vec<TFunction>,
    pub tests: Vec<TTest>,
    pub constants: Vec<TConstant>,
    pub globals: Vec<TGlobal>,
    pub global_init_order: Vec<usize>,
    pub global_state_bytes: u64,
    pub job_headroom_bytes: u64,
    pub globals_budget_bytes: u64,
    pub recursion_budget_bytes: u64,
    pub files: Vec<String>,
    pub call_graph: Vec<Vec<TCallEdge>>,
    pub function_type_targets: Vec<Vec<usize>>,
    pub types: Vec<TType>,
}

pub const GLOBAL_ROOT_START: usize = usize::MAX / 2;

pub fn global_root(id: usize) -> usize {
    GLOBAL_ROOT_START + id
}

pub fn global_from_root(root: usize) -> Option<usize> {
    (root >= GLOBAL_ROOT_START).then(|| root - GLOBAL_ROOT_START)
}

#[derive(Clone, Debug)]
pub struct TGlobal {
    pub id: usize,
    pub name: String,
    pub ty: Ty,
    pub initializer: TGlobalInitializer,
    pub span: Span,
    pub offset: u64,
    pub size_bytes: u64,
}

#[derive(Clone, Debug)]
pub enum TGlobalInitializer {
    Constant(ConstValue),
    Runtime(TExpr),
}

#[derive(Clone, Debug)]
pub struct TConstant {
    pub id: usize,
    pub name: String,
    pub ty: Ty,
    pub value: ConstValue,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct TConstExpr {
    pub id: usize,
    pub name: String,
    pub ty: Ty,
    pub expr: TExpr,
    pub span: Span,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConstValue {
    Unit,
    Integer(i128),
    Bool(bool),
    Struct(Vec<ConstValue>),
    Array(Vec<ConstValue>),
    List(Vec<ConstValue>),
    Queue(Vec<ConstValue>),
    Ring(Vec<ConstValue>),
    Grid(Vec<ConstValue>),
    Map(Vec<(ConstValue, ConstValue)>),
    Set(Vec<ConstValue>),
    Pool {
        slots: Vec<Option<ConstValue>>,
        generations: Vec<u32>,
        free: Vec<u32>,
    },
    Function(usize),
    Enum {
        case_index: usize,
        payload: Vec<ConstValue>,
    },
}

#[derive(Clone, Copy, Debug)]
#[allow(dead_code)]
pub struct TCallEdge {
    pub target: usize,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct TTest {
    pub name: String,
    pub function_id: usize,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // Keep source locations and source names in the typed form for later diagnostics.
pub struct TFunction {
    pub id: usize,
    pub name: String,
    pub params: Vec<TParam>,
    pub result: Ty,
    pub body: TBlock,
    pub span: Span,
    pub is_test: bool,
    pub recursive: bool,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct TParam {
    pub id: usize,
    pub name: String,
    pub ty: Ty,
    pub mode: ParamMode,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct TBlock {
    pub statements: Vec<TStmt>,
    pub tail: Option<Box<TExpr>>,
    pub falls_through: bool,
    pub scope_id: usize,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct TStmt {
    pub kind: TStmtKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)] // Mutability and names remain explicit after name resolution.
pub enum TStmtKind {
    Let {
        id: usize,
        name: String,
        ty: Ty,
        mutable: bool,
        value: TExpr,
    },
    Assign {
        place: TPlace,
        ty: Ty,
        op: AssignOp,
        operator_span: Span,
        value: TExpr,
    },
    Return(Option<TExpr>),
    Expr(TExpr),
    If {
        condition: TExpr,
        then_block: TBlock,
        else_block: Option<TBlock>,
    },
    For {
        id: usize,
        ty: Ty,
        start: TExpr,
        end: TExpr,
        inclusive: bool,
        body: TBlock,
    },
    ForEach {
        id: usize,
        index_id: Option<usize>,
        second_index_id: Option<usize>,
        counter_id: usize,
        collection: TExpr,
        source: TPlace,
        is_list: bool,
        is_pool: bool,
        is_map: bool,
        is_set: bool,
        is_grid: bool,
        body: TBlock,
    },
    Discard(TExpr),
    Break,
    Continue,
    Expect {
        source: String,
        kind: TExpectKind,
    },
    Block(TBlock),
}

#[derive(Clone, Debug)]
pub struct TPlace {
    pub root: usize,
    /// Struct-only projections retained for the refinement fact map.
    pub fields: Vec<usize>,
    pub path: Vec<TProjection>,
    pub ty: Ty,
}

#[derive(Clone, Debug)]
pub enum TProjection {
    Field(usize),
    Index {
        index: TExpr,
        constant: Option<i128>,
        capacity: usize,
        is_list: bool,
        is_pool: bool,
        is_map: bool,
        proven: bool,
        grid: Option<GridIndexInfo>,
    },
}

#[derive(Clone, Debug)]
pub struct GridIndexInfo {
    pub x: TExpr,
    pub y: TExpr,
    pub width: usize,
    pub height: usize,
    pub proven_x: bool,
    pub proven_y: bool,
}

#[derive(Clone, Debug)]
pub enum TExpectKind {
    Bool(TExpr),
    Compare {
        op: BinaryOp,
        left: TExpr,
        right: TExpr,
    },
}

#[derive(Clone, Debug)]
pub struct TExpr {
    pub kind: TExprKind,
    pub ty: Ty,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum CallTarget {
    Function(usize),
    Print,
    Min,
    Max,
    Sort {
        capacity: usize,
        is_list: bool,
    },
    SortBy {
        callsite_id: usize,
        capacity: usize,
        is_list: bool,
    },
    BinarySearch {
        capacity: usize,
        is_list: bool,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Effect {
    None,
    Observable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MethodKind {
    IsNone,
    IsSome,
    IsOk,
    IsErr,
    ResultOk,
    UnwrapOption,
    UnwrapResult,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CollectionOp {
    Push,
    RingPush,
    Pop,
    Peek,
    Insert,
    Remove,
    Count,
    Len,
    Width,
    Height,
    Clear,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PoolOp {
    Add,
    Get,
    Remove,
    Contains,
    Count,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MapOp {
    Get,
    Set,
    Remove,
    Contains,
    Count,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SetOp {
    Add,
    Remove,
    Contains,
    Count,
}

#[derive(Clone, Debug)]
pub enum TPattern {
    Wildcard,
    Integer(i128),
    Bool(bool),
    Case {
        ty: Ty,
        case_index: usize,
        bindings: Vec<Option<usize>>,
    },
}

#[derive(Clone, Debug)]
pub struct TMatchArm {
    pub pattern: TPattern,
    pub body: TBlock,
}

#[derive(Clone, Debug)]
pub enum TExprKind {
    Unit,
    Integer(i128),
    Bool(bool),
    Local(usize),
    Global(usize),
    Constant(usize),
    FunctionValue(usize),
    Call {
        target: CallTarget,
        args: Vec<TExpr>,
        effect: Effect,
    },
    IndirectCall {
        callsite_id: usize,
        callee: Box<TExpr>,
        args: Vec<TExpr>,
        params: Vec<TFunctionTypeParam>,
    },
    Construct {
        case_index: usize,
        args: Vec<TExpr>,
    },
    Method {
        kind: MethodKind,
        receiver: Box<TExpr>,
    },
    OptionalCall {
        receiver: Box<TExpr>,
        function_id: usize,
        args: Vec<TExpr>,
        wraps_result: bool,
    },
    OptionalToLong(Box<TExpr>),
    Field {
        receiver: Box<TExpr>,
        field_index: usize,
    },
    Index {
        receiver: Box<TExpr>,
        index: Box<TExpr>,
        capacity: usize,
        is_list: bool,
        proven: bool,
        grid: Option<Box<GridIndexInfo>>,
    },
    Fill {
        value: Box<TExpr>,
        capacity: usize,
    },
    EmptyArray,
    EmptyGrid,
    EmptyList,
    EmptyPool,
    EmptyMap,
    EmptySet,
    EmptyQueue,
    EmptyRing,
    CollectionOp {
        op: CollectionOp,
        receiver: Box<TExpr>,
        args: Vec<TExpr>,
        capacity: usize,
        proven_success: bool,
    },
    PoolOp {
        op: PoolOp,
        receiver: Box<TExpr>,
        args: Vec<TExpr>,
        capacity: usize,
        proven_success: bool,
    },
    MapOp {
        op: MapOp,
        receiver: Box<TExpr>,
        args: Vec<TExpr>,
        capacity: usize,
        proven_success: bool,
    },
    SetOp {
        op: SetOp,
        receiver: Box<TExpr>,
        args: Vec<TExpr>,
        capacity: usize,
        proven_success: bool,
    },
    StructConstruct {
        fields: Vec<(usize, TExpr)>,
    },
    Convert {
        value: Box<TExpr>,
        min: i128,
        max: i128,
        policy: RefinePolicy,
    },
    Fit {
        value: Box<TExpr>,
        min: i128,
        max: i128,
        option_ty: Ty,
    },
    Try {
        value: Box<TExpr>,
        success_ty: Ty,
        error_ty: Option<Ty>,
        propagated_ty: Ty,
    },
    Coalesce {
        option: Box<TExpr>,
        fallback: Box<TExpr>,
    },
    Match {
        scrutinee: Box<TExpr>,
        arms: Vec<TMatchArm>,
    },
    Return(Option<Box<TExpr>>),
    LoopExit(bool),
    ToLong(Box<TExpr>),
    Cast {
        cast_span: Span,
        value: Box<TExpr>,
    },
    Unary {
        op: UnaryOp,
        operator_span: Span,
        value: Box<TExpr>,
    },
    Binary {
        op: BinaryOp,
        operator_span: Span,
        left: Box<TExpr>,
        right: Box<TExpr>,
    },
    If {
        condition: Box<TExpr>,
        then_block: TBlock,
        else_block: Option<TBlock>,
    },
}

pub fn llvm_type(ty: Ty, types: &[TType]) -> String {
    let ty = base_type(ty, types);
    if matches!(types[ty.0].kind, TTypeKind::Id { .. }) {
        return "i64".to_owned();
    }
    match ty {
        Ty::Int => "i32".to_owned(),
        Ty::Long => "i64".to_owned(),
        Ty::Bool => "i1".to_owned(),
        Ty::Unit | Ty::Never => "void".to_owned(),
        _ if matches!(types[ty.0].kind, TTypeKind::Function { .. }) => "ptr".to_owned(),
        Ty(id) => {
            debug_assert!(id < types.len());
            format!("%nl.ty.{id}")
        }
    }
}
