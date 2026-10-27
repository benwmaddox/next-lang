package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/constant"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed shim/gostd.nl
var gostdShim string

// unsupported is raised (as a panic) when the converter meets a construct it
// has no rule for. The declaration being converted is then left out and the
// problem reported: the converter fails closed instead of guessing.
type unsupported struct {
	pos      string
	category string
	msg      string
}

// Result is what one conversion produced.
type Result struct {
	Converted, Failed, Excluded, Stubbed int
	Problems                             []Problem
	Decls                                []DeclRecord
	files                                map[string]*strings.Builder
	convertedObjs                        map[types.Object]bool
	reach                                *Reach
	usedShim                             bool
	cfg                                  *Config
}

type Problem struct {
	Symbol   string `json:"symbol"`
	Pos      string `json:"pos"`
	Category string `json:"category"`
	Message  string `json:"message"`
}

// DeclRecord is one entry of the decisions log: which Go symbol became which
// next-lang declaration, and which rules were applied to it.
type DeclRecord struct {
	Symbol    string   `json:"symbol"`
	Source    string   `json:"source"`
	Target    string   `json:"target,omitempty"`
	Status    string   `json:"status"`
	Decisions []string `json:"decisions,omitempty"`
}

type conv struct {
	p         *Program
	r         *Reach
	cfg       *Config
	top       *namer
	topNames  map[types.Object]string
	modes     *modes
	written   map[types.Object]bool
	recursive map[*types.Func]bool
	// Read-only string-keyed map variables converted to lookup functions.
	lookups map[types.Object]lookupTable
	// Function values (funcvals.go).
	families     map[string]*family
	litMember    map[*ast.FuncLit]*member
	fnMember     map[*types.Func]*member
	lifted       map[*member]bool
	usedFamilies map[*family]bool
	res          *Result

	// Per-declaration state.
	decisions map[string]bool
	tuples    map[*types.Func]string
	extra     []string // helper declarations generated while converting a decl
}

const (
	defaultStringMax = 4096
	defaultSliceMax  = 256
	defaultMapMax    = 256
)

func convert(p *Program, r *Reach, cfg *Config) *Result {
	c := &conv{
		p: p, r: r, cfg: cfg,
		top:          newNamer(nil),
		topNames:     map[types.Object]string{},
		res:          &Result{files: map[string]*strings.Builder{}, cfg: cfg, convertedObjs: map[types.Object]bool{}, reach: r},
		tuples:       map[*types.Func]string{},
		lookups:      map[types.Object]lookupTable{},
		lifted:       map[*member]bool{},
		usedFamilies: map[*family]bool{},
	}
	// Reserve the shim's names so converted code never takes one.
	for _, line := range strings.Split(gostdShim, "\n") {
		for _, kw := range []string{"fn ", "type ", "struct ", "const "} {
			if strings.HasPrefix(line, kw) {
				rest := strings.TrimPrefix(line, kw)
				end := strings.IndexAny(rest, " (<:={")
				if end > 0 {
					c.top.used[rest[:end]] = true
				}
			}
		}
	}
	c.findFuncValues()
	c.modes = c.computeModes()
	c.recursive = c.findRecursive()
	for _, obj := range r.Order {
		c.convertDecl(obj)
	}
	if len(c.usedFamilies) > 0 {
		func() {
			defer func() {
				if e := recover(); e != nil {
					u, ok := e.(unsupported)
					if !ok {
						panic(e)
					}
					c.res.Problems = append(c.res.Problems, Problem{Symbol: "function-value dispatchers", Pos: u.pos, Category: u.category, Message: u.msg})
				}
			}()
			b := &strings.Builder{}
			b.WriteString(c.dispatchers())
			c.res.files["go2nl_funcvalues.nl"] = b
		}()
	}
	return c.res
}

func (c *conv) fail(n ast.Node, category, format string, args ...any) {
	pos := ""
	if n != nil {
		pos = c.p.pos(n)
	}
	panic(unsupported{pos: pos, category: category, msg: fmt.Sprintf(format, args...)})
}

func (c *conv) decide(d string) { c.decisions[d] = true }

func (c *conv) convertDecl(obj types.Object) {
	decl := c.p.Decls[obj]
	if decl == nil {
		return
	}
	if _, ok := obj.(*types.Const); ok {
		// Constants are written at each use as literals of the type Go gave
		// that use, except typed ones, which keep their name (see constDecl).
		if !c.wantsConstDecl(obj.(*types.Const)) {
			return
		}
	}
	sym := c.p.objName(obj)
	rec := DeclRecord{Symbol: sym, Source: c.p.pos(decl)}
	c.decisions = map[string]bool{}
	c.extra = nil
	var text string
	func() {
		defer func() {
			if e := recover(); e != nil {
				u, ok := e.(unsupported)
				if !ok {
					panic(e)
				}
				if u.pos == "" {
					u.pos = rec.Source
				}
				c.res.Problems = append(c.res.Problems, Problem{Symbol: sym, Pos: u.pos, Category: u.category, Message: u.msg})
				rec.Status = "failed: " + u.category + ": " + u.msg
				text = ""
			}
		}()
		switch d := decl.(type) {
		case *ast.FuncDecl:
			text = c.funcDecl(obj.(*types.Func), d)
			rec.Target = c.valueName(obj)
		case *ast.TypeSpec:
			text = c.typeDecl(obj.(*types.TypeName), d)
			rec.Target = c.typeName(obj.(*types.TypeName))
		case *ast.ValueSpec:
			if k, ok := obj.(*types.Const); ok {
				text = c.constDecl(k)
			} else {
				text = c.globalDecl(obj.(*types.Var), d)
			}
			rec.Target = c.valueName(obj)
		}
		rec.Status = "converted"
	}()
	for d := range c.decisions {
		rec.Decisions = append(rec.Decisions, d)
	}
	sort.Strings(rec.Decisions)
	file := c.p.shortPkg(obj.Pkg().Path()) + ".nl"
	b := c.res.files[file]
	if b == nil {
		b = &strings.Builder{}
		c.res.files[file] = b
	}
	c.res.convertedObjs[obj] = text != ""
	if text == "" {
		c.res.Failed++
		fmt.Fprintf(b, "// go2nl: %s (%s) not converted: %s\n\n", sym, rec.Source, strings.TrimPrefix(rec.Status, "failed: "))
	} else {
		c.res.Converted++
		fmt.Fprintf(b, "// %s (%s)\n%s\n", sym, rec.Source, text)
		for _, x := range c.extra {
			fmt.Fprintf(b, "%s\n", x)
		}
	}
	c.res.Decls = append(c.res.Decls, rec)
}

// ---- types ----

func (c *conv) stringMax() int64 {
	return c.cfg.capacity("default.string", "", defaultStringMax)
}

// nlType is the next-lang spelling of a Go type. where names the field or
// variable, for capacity lookups ("pkg.Type.field").
func (c *conv) nlType(t types.Type, where string) string {
	switch t := t.(type) {
	case *types.Alias:
		return c.nlType(types.Unalias(t), where)
	case *types.Basic:
		return c.basicType(t)
	case *types.Named:
		if t.TypeArgs().Len() > 0 || t.TypeParams().Len() > 0 {
			c.fail(nil, "generic", "generic type %s", t)
		}
		if t.Obj().Pkg() == nil {
			if t.Obj().Name() == "error" {
				c.decide("error becomes GoError: 0 is nil, then one code per known error")
				return errorType
			}
			c.fail(nil, "interface-type", "built-in type %s", t)
		}
		if !c.p.inModule(t.Obj()) {
			if nt, _, ok := c.stdlibType(t); ok {
				return nt
			}
			c.fail(nil, "stdlib-type", "standard-library type %s", t)
		}
		if types.IsInterface(t) {
			c.fail(nil, "interface-type", "interface type %s", t)
		}
		return c.typeName(t.Obj())
	case *types.Pointer:
		// A pointer becomes the value it points to; the parameter modes carry
		// the "may change it" part. Pointer identity and nil are refused where
		// they are used (see expr).
		c.decide("pointer *T becomes the value T (parameters: write when changed through)")
		return c.nlType(t.Elem(), where)
	case *types.Slice:
		if b, ok := t.Elem().Underlying().(*types.Basic); ok && b.Kind() == types.Byte {
			c.fail(nil, "string-conv", "[]byte (no rule yet; Go strings are Bytes)")
		}
		n := c.cfg.capacity(where, "default.slice", defaultSliceMax)
		c.decide(fmt.Sprintf("slice []T becomes list<T, %d>; append past %d fails the program", n, n))
		return fmt.Sprintf("list<%s, %d>", c.nlType(t.Elem(), where+"[]"), n)
	case *types.Array:
		return fmt.Sprintf("%s[%d]", c.nlType(t.Elem(), where+"[]"), t.Len())
	case *types.Map:
		n := c.cfg.capacity(where, "default.map", defaultMapMax)
		c.decide(fmt.Sprintf("map becomes map<K, V, %d>; a new key past %d fails the program", n, n))
		return fmt.Sprintf("map<%s, %s, %d>", c.mapKeyType(t.Key()), c.nlType(t.Elem(), where+"[]"), n)
	case *types.Signature:
		return c.familyOf(t).typeName
	case *types.Interface:
		if t.Empty() {
			return "GoAny"
		}
		c.fail(nil, "interface-type", "interface type %s", t)
	case *types.Struct:
		c.fail(nil, "anonymous-struct", "anonymous struct type")
	case *types.Chan:
		c.fail(nil, "goroutine", "channel type")
	case *types.TypeParam:
		c.fail(nil, "generic", "type parameter %s", t)
	}
	c.fail(nil, "type", "type %s", t)
	return ""
}

func (c *conv) mapKeyType(t types.Type) string {
	if isGoString(t) {
		c.decide("string map keys are Ascii (Bytes isn't hashable); a non-ASCII key is never found")
		return "Ascii max go_string_max"
	}
	return c.nlType(t, "")
}

func isGoString(t types.Type) bool {
	b, ok := t.Underlying().(*types.Basic)
	return ok && b.Info()&types.IsString != 0
}

func (c *conv) basicType(t *types.Basic) string {
	switch t.Kind() {
	case types.Bool, types.UntypedBool:
		return "bool"
	case types.Int, types.Int64, types.UntypedInt:
		return "long"
	case types.Int32, types.UntypedRune:
		return "int"
	case types.Int16:
		return "GoI16"
	case types.Int8:
		return "GoI8"
	case types.Uint8:
		return "byte"
	case types.Uint16:
		return "GoU16"
	case types.Uint32:
		return "GoU32"
	case types.String, types.UntypedString:
		c.decide(fmt.Sprintf("string becomes Bytes max %d (Go strings are bytes)", c.stringMax()))
		return "Bytes max go_string_max"
	case types.Float32, types.Float64, types.UntypedFloat:
		c.fail(nil, "float", "%s (stage 0 has no floats)", t)
	case types.Uint, types.Uint64, types.Uintptr:
		c.fail(nil, "unsigned-wide", "%s (next-lang has no 64-bit unsigned type)", t)
	}
	c.fail(nil, "type", "basic type %s", t)
	return ""
}

// intBase is "long", "int" or "byte": the type a refined alias is built on,
// which decides literal suffixes and casts.
func (c *conv) intBase(t types.Type) string {
	b, ok := t.Underlying().(*types.Basic)
	if !ok {
		return ""
	}
	switch b.Kind() {
	case types.Int, types.Int64, types.UntypedInt, types.Uint32:
		return "long"
	case types.Int32, types.UntypedRune, types.Int16, types.Int8, types.Uint16:
		return "int"
	case types.Uint8:
		return "byte"
	}
	return ""
}

// zero is the next-lang zero value of a Go type.
func (c *conv) zero(t types.Type, where string) string {
	if isErrorType(t) {
		return "0L"
	}
	if n, ok := t.(*types.Named); ok && n.Obj().Pkg() != nil && !c.p.inModule(n.Obj()) {
		if _, z, ok := c.stdlibType(n); ok {
			return z
		}
	}
	switch u := t.Underlying().(type) {
	case *types.Basic:
		switch {
		case u.Info()&types.IsBoolean != 0:
			return "false"
		case u.Info()&types.IsString != 0:
			c.basicType(u)
			return `b""`
		case u.Info()&types.IsInteger != 0:
			c.nlType(t, where)
			if c.intBase(t) == "long" {
				return "0L"
			}
			return "0"
		}
	case *types.Struct:
		c.nlType(t, where)
		return c.nlType(t, where) + " {}"
	case *types.Pointer:
		if _, ok := u.Elem().Underlying().(*types.Struct); ok {
			// A nil pointer has no next-lang value; a pointer field or local
			// left nil is refused here.
			c.fail(nil, "nil-pointer", "zero value of pointer type %s is nil", t)
		}
	case *types.Slice:
		c.nlType(t, where)
		return "list {}"
	case *types.Map:
		c.nlType(t, where)
		return "map {}"
	case *types.Array:
		return "fill(" + c.zero(u.Elem(), where+"[]") + ")"
	case *types.Signature:
		c.nlType(t, where)
		return "0L"
	case *types.Interface:
		if u.Empty() {
			return "GoAny.Nil"
		}
	}
	c.fail(nil, "type", "no zero value for %s", t)
	return ""
}

func (c *conv) typeDecl(tn *types.TypeName, spec *ast.TypeSpec) string {
	if spec.TypeParams != nil {
		c.fail(spec, "generic", "generic type")
	}
	if spec.Assign.IsValid() {
		c.fail(spec, "type-alias", "Go type alias")
	}
	name := c.typeName(tn)
	sym := c.p.objName(tn)
	switch u := tn.Type().Underlying().(type) {
	case *types.Struct:
		var b strings.Builder
		fmt.Fprintf(&b, "struct %s {\n", name)
		for i := 0; i < u.NumFields(); i++ {
			f := u.Field(i)
			if hasPointer(f.Type()) {
				c.fail(spec, "pointer-field", "field %s has pointer type %s (an object graph needs pools and ids)", f.Name(), f.Type())
			}
			where := sym + "." + f.Name()
			fmt.Fprintf(&b, "    %s: %s = %s\n", fieldName(f.Name()), c.nlType(f.Type(), where), c.zero(f.Type(), where))
		}
		c.decide("every struct field defaults to its Go zero value, so T {} is Go's T{}")
		b.WriteString("}\n")
		return b.String()
	case *types.Interface:
		c.fail(spec, "interface-type", "interface type")
	default:
		c.decide("named non-struct type becomes a type alias")
		return fmt.Sprintf("type %s = %s\n", name, c.nlType(u, sym))
	}
	return ""
}

// wantsConstDecl: typed constants of an integer named type keep their name, so
// `ast.KindIdentifier` reads as such in the output. Untyped constants are
// written as literals wherever they're used.
func (c *conv) wantsConstDecl(k *types.Const) bool {
	_, named := k.Type().(*types.Named)
	return named && c.intBase(k.Type()) != ""
}

func (c *conv) constDecl(k *types.Const) string {
	c.decide("typed constant keeps its name")
	return fmt.Sprintf("const %s: %s = %s\n", c.valueName(k), c.nlType(k.Type(), ""), c.literal(k.Val(), k.Type(), nil))
}

func (c *conv) globalDecl(v *types.Var, spec *ast.ValueSpec) string {
	if c.writtenGlobals()[v] {
		c.fail(spec, "mutable-global", "package variable %s is written after initialisation (next-lang has no mutable globals)", v.Name())
	}
	c.decide("package variable only read after initialisation becomes const")
	var value ast.Expr
	for i, n := range spec.Names {
		if c.p.Info.Defs[n] == v && i < len(spec.Values) {
			value = spec.Values[i]
		}
	}
	t := c.nlType(v.Type(), c.p.objName(v))
	if value == nil {
		return fmt.Sprintf("const %s: %s = %s\n", c.valueName(v), t, c.zero(v.Type(), c.p.objName(v)))
	}
	// Composite literals of maps and slices are built by a helper function,
	// which next-lang evaluates at compile time.
	if cl, ok := ast.Unparen(value).(*ast.CompositeLit); ok {
		if m, ok := c.p.Info.TypeOf(cl).Underlying().(*types.Map); ok && isGoString(m.Key()) {
			return c.lookupTable(v, cl, m)
		}
		switch c.p.Info.TypeOf(cl).Underlying().(type) {
		case *types.Map, *types.Slice:
			fc := c.newFunc(nil)
			fname := c.top.claim("init_" + c.valueName(v))
			body := fc.buildCollection(cl, v.Type(), c.p.objName(v))
			c.extra = append(c.extra, fmt.Sprintf("fn %s() -> %s {\n%s}\n", fname, t, body))
			c.decide("collection literal is built by a helper function evaluated at compile time")
			return fmt.Sprintf("const %s: %s = %s()\n", c.valueName(v), t, fname)
		}
	}
	fc := c.newFunc(nil)
	if c.globalFunc(v) {
		fc.ind = 1
		body := fc.valueExpr(value, v.Type())
		return fmt.Sprintf("fn %s() -> %s {\n%s    %s\n}\n", c.valueName(v), t, fc.b.String(), body)
	}
	return fmt.Sprintf("const %s: %s = %s\n", c.valueName(v), t, fc.expr(value))
}

// globalFunc: a read-only package variable whose value holds a string is
// emitted as a zero-argument function that builds it, not as a const. Stage 0
// leaves a const struct with a large Bytes field out of the data-stack bound
// and fails at run time ("data stack exhausted") when one is passed on; a value
// built locally is counted.
func (c *conv) globalFunc(v *types.Var) bool {
	if c.isLookupVar(v) {
		return false
	}
	spec, ok := c.p.Decls[v].(*ast.ValueSpec)
	if !ok || len(spec.Values) == 0 {
		return false
	}
	if _, ok := v.Type().Underlying().(*types.Map); ok {
		return false
	}
	if _, ok := v.Type().Underlying().(*types.Slice); ok {
		return false
	}
	return holdsString(v.Type(), 0)
}

func holdsString(t types.Type, depth int) bool {
	if depth > 8 {
		return false
	}
	switch u := t.Underlying().(type) {
	case *types.Basic:
		return u.Info()&types.IsString != 0
	case *types.Pointer:
		return holdsString(u.Elem(), depth+1)
	case *types.Struct:
		for i := 0; i < u.NumFields(); i++ {
			if holdsString(u.Field(i).Type(), depth+1) {
				return true
			}
		}
	case *types.Array:
		return holdsString(u.Elem(), depth+1)
	}
	return false
}

func (c *conv) writtenGlobals() map[types.Object]bool {
	if c.written == nil {
		c.written = c.p.writtenGlobals(c.r)
	}
	return c.written
}

// ---- literals ----

// literal writes a constant value as a next-lang literal of the type Go gave it.
func (c *conv) literal(v constant.Value, t types.Type, n ast.Node) string {
	if t == nil {
		t = types.Default(types.Typ[types.UntypedInt])
	}
	t = types.Default(t)
	switch v.Kind() {
	case constant.Bool:
		if constant.BoolVal(v) {
			return "true"
		}
		return "false"
	case constant.String:
		c.basicType(types.Typ[types.String])
		return bytesLiteral(constant.StringVal(v))
	case constant.Int:
		base := c.intBase(t)
		if base == "" {
			if isFloat(t) {
				c.fail(n, "float", "float constant")
			}
			c.fail(n, "type", "integer constant of type %s", t)
		}
		c.nlType(t, "")
		s := v.ExactString()
		if base == "long" {
			s += "L"
		}
		if _, named := t.(*types.Named); named && base != "long" {
			// A refined alias needs no cast from a literal that fits.
			return s
		}
		return s
	case constant.Float:
		c.fail(n, "float", "float constant %s", v)
	}
	c.fail(n, "type", "constant %s", v)
	return ""
}

func isFloat(t types.Type) bool {
	b, ok := t.Underlying().(*types.Basic)
	return ok && b.Info()&types.IsFloat != 0
}

func bytesLiteral(s string) string {
	var b strings.Builder
	b.WriteString(`b"`)
	for i := 0; i < len(s); i++ {
		ch := s[i]
		switch {
		case ch == '"':
			b.WriteString(`\"`)
		case ch == '\\':
			b.WriteString(`\\`)
		case ch == '\n':
			b.WriteString(`\n`)
		case ch == '\t':
			b.WriteString(`\t`)
		case ch == 0:
			b.WriteString(`\0`)
		case ch < 32 || ch >= 127:
			fmt.Fprintf(&b, `\x%02X`, ch)
		default:
			b.WriteByte(ch)
		}
	}
	b.WriteString(`"`)
	return b.String()
}

// ---- output ----

func (r *Result) writeTo(dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	// Remove earlier output so a declaration that moved files doesn't linger.
	old, _ := filepath.Glob(filepath.Join(dir, "*.nl"))
	for _, f := range old {
		os.Remove(f)
	}
	var names []string
	for k := range r.files {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, k := range names {
		header := "// Generated by go2nl from Go source. Do not edit; change the converter or its config.\n\n"
		if err := os.WriteFile(filepath.Join(dir, k), []byte(header+r.files[k].String()), 0o644); err != nil {
			return err
		}
	}
	config := fmt.Sprintf("// Generated by go2nl: capacities from the conversion config.\n\nconst go_string_max: long = %dL\n", r.cfg.capacity("default.string", "", defaultStringMax))
	if err := os.WriteFile(filepath.Join(dir, "go2nl_config.nl"), []byte(config), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "gostd.nl"), []byte(gostdShim), 0o644); err != nil {
		return err
	}
	data, _ := json.MarshalIndent(r.Decls, "", "  ")
	if err := os.WriteFile(filepath.Join(dir, "go2nl-decisions.json"), append(data, '\n'), 0o644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "go2nl-report.md"), []byte(r.report()), 0o644)
}

func (r *Result) report() string {
	var b strings.Builder
	fmt.Fprintf(&b, "# go2nl conversion report\n\n")
	if r.cfg.Upstream.Repo != "" {
		fmt.Fprintf(&b, "Upstream: %s at %s\n\n", r.cfg.Upstream.Repo, r.cfg.Upstream.Commit)
	}
	closed := r.closed(r.reach)
	fmt.Fprintf(&b, "%d declarations converted, %d not converted, %d excluded by the config, %d replaced by stubs.\n\n", r.Converted, r.Failed, r.Excluded, r.Stubbed)
	fmt.Fprintf(&b, "**%d of the %d converted declarations are dependency-closed**: they and everything they use converted, so only these can compile.\n\n", len(closed), r.Converted)
	fa, fc, fcl := r.funcCounts(closed)
	fmt.Fprintf(&b, "Functions and methods: %d reachable, %d converted, **%d dependency-closed**.\n\n", fa, fc, fcl)
	byCat := map[string]int{}
	for _, p := range r.Problems {
		byCat[p.Category]++
	}
	var cats []string
	for k := range byCat {
		cats = append(cats, k)
	}
	sort.Slice(cats, func(i, j int) bool {
		if byCat[cats[i]] != byCat[cats[j]] {
			return byCat[cats[i]] > byCat[cats[j]]
		}
		return cats[i] < cats[j]
	})
	if len(cats) > 0 {
		fmt.Fprintf(&b, "| Blocked by | Declarations |\n| --- | ---: |\n")
		for _, k := range cats {
			fmt.Fprintf(&b, "| %s | %d |\n", k, byCat[k])
		}
		fmt.Fprintf(&b, "\n## Not converted\n\n")
		for _, p := range r.Problems {
			fmt.Fprintf(&b, "- %s (%s): %s: %s\n", p.Symbol, p.Pos, p.Category, p.Message)
		}
	}
	return b.String()
}

// exprString is a short source snippet for messages.
func (c *conv) exprString(e ast.Node) string {
	pos := c.p.Fset.Position(e.Pos())
	end := c.p.Fset.Position(e.End())
	data, err := os.ReadFile(pos.Filename)
	if err != nil || end.Offset > len(data) {
		return "?"
	}
	s := string(data[pos.Offset:end.Offset])
	if len(s) > 60 {
		s = s[:57] + "..."
	}
	return strings.ReplaceAll(s, "\n", " ")
}

var _ = token.ADD

type lookupTable struct {
	get   string
	count int
}

// lookupTable converts a read-only map[string]V literal into a function from
// key to Option<V>. Stage 0 can't hold a const map with Ascii keys (its
// compile-time hashing panics), and a lookup function needs no hashing.
// Lookups (m[k], v, ok := m[k]) and len(m) are converted; any other use of the
// variable, such as ranging over it, is refused.
func (c *conv) lookupTable(v *types.Var, cl *ast.CompositeLit, m *types.Map) string {
	f := c.newFunc(nil)
	name := c.valueName(v) + "_get"
	if lt, ok := c.lookups[v]; ok {
		name = lt.get
	}
	c.top.used[name] = true
	key := f.tmp("key")
	vt := c.nlType(m.Elem(), "")
	f.ind = 1
	for _, el := range cl.Elts {
		kv := el.(*ast.KeyValueExpr)
		f.line("if %s == %s { return some(%s) }", key, f.valueExpr(kv.Key, m.Key()), f.valueExpr(kv.Value, m.Elem()))
	}
	f.line("none")
	c.lookups[v] = lookupTable{get: name, count: len(cl.Elts)}
	c.decide("read-only map[string]V literal becomes a lookup function (stage 0 can't hash const Ascii keys)")
	return fmt.Sprintf("fn %s(%s: %s) -> Option<%s> {\n%s}\n", name, key, c.nlType(m.Key(), ""), vt, f.b.String())
}

// isLookupVar: v is a read-only package variable initialised with a
// map[string]V literal, which lookupTable converts.
func (c *conv) isLookupVar(v *types.Var) bool {
	return c.lookupLiteral(v) != nil && !c.writtenGlobals()[v]
}

func (c *conv) lookupLiteral(v *types.Var) *ast.CompositeLit {
	spec, ok := c.p.Decls[v].(*ast.ValueSpec)
	if !ok {
		return nil
	}
	for i, n := range spec.Names {
		if c.p.Info.Defs[n] == v && i < len(spec.Values) {
			cl, ok := ast.Unparen(spec.Values[i]).(*ast.CompositeLit)
			if !ok {
				return nil
			}
			if m, ok := c.p.Info.TypeOf(cl).Underlying().(*types.Map); ok && isGoString(m.Key()) {
				return cl
			}
		}
	}
	return nil
}

func (c *conv) lookupCount(v *types.Var) int { return len(c.lookupLiteral(v).Elts) }

// closedCount counts converted declarations whose every dependency (direct
// or not) also converted: the ones that can actually compile.
func (r *Result) closed(reach *Reach) map[types.Object]bool {
	ok := map[types.Object]bool{}
	for obj, conv := range r.convertedObjs {
		if conv {
			ok[obj] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for obj := range ok {
			for d := range reach.Deps[obj] {
				if _, tracked := r.convertedObjs[d]; tracked && !ok[d] {
					delete(ok, obj)
					changed = true
					break
				}
			}
		}
	}
	return ok
}

// funcCounts: (reachable functions, converted, dependency-closed).
func (r *Result) funcCounts(closed map[types.Object]bool) (int, int, int) {
	var all, conv, cl int
	for obj, ok := range r.convertedObjs {
		if _, isFn := obj.(*types.Func); !isFn {
			continue
		}
		all++
		if ok {
			conv++
		}
		if closed[obj] {
			cl++
		}
	}
	return all, conv, cl
}
