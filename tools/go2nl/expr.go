package main

import (
	"fmt"
	"go/ast"
	"go/constant"
	"go/token"
	"go/types"
	"strings"
)

// valueExpr converts e for a slot of Go type want: it drops the & of a fresh
// &T{...} (pointers become values) and keeps everything else as expr does.
func (f *fnConv) valueExpr(e ast.Expr, want types.Type) string {
	if want != nil {
		if _, ok := want.Underlying().(*types.Signature); ok {
			if f.c.isNilIdent(e) {
				return "0L"
			}
			if v := f.funcValue(e); v != "" {
				return v
			}
		}
		if isEmptyInterface(want) && !isEmptyInterface(f.c.p.Info.TypeOf(e)) {
			return f.box(e)
		}
	}
	if u, ok := ast.Unparen(e).(*ast.UnaryExpr); ok && u.Op == token.AND {
		if _, ok := ast.Unparen(u.X).(*ast.CompositeLit); ok {
			return f.expr(u.X)
		}
	}
	if want != nil {
		if tv, ok := f.c.p.Info.Types[e]; ok && tv.Value != nil && !f.namedConst(e) {
			return f.c.literal(tv.Value, want, e)
		}
	}
	if want != nil && isNarrow(want) {
		switch x := ast.Unparen(e).(type) {
		case *ast.BinaryExpr:
			if !isComparison(x.Op) {
				return f.c.narrowCast(f.expr(e), want)
			}
		case *ast.UnaryExpr:
			if x.Op == token.SUB || x.Op == token.XOR {
				return f.c.narrowCast(f.expr(e), want)
			}
		}
	}
	return f.expr(e)
}

func isComparison(op token.Token) bool {
	switch op {
	case token.EQL, token.NEQ, token.LSS, token.LEQ, token.GTR, token.GEQ, token.LAND, token.LOR:
		return true
	}
	return false
}

// narrowCast: arithmetic on a range type gives the base type, and storing it
// back needs a checked cast, which fails the program if the value is out of
// range (Go would wrap).
func (c *conv) narrowCast(x string, t types.Type) string {
	c.decide("arithmetic stored into a narrow integer type is cast back; out of range fails (Go wraps)")
	return "(" + c.nlType(t, "") + ")(" + x + ")"
}

// namedConst: e names a typed constant that keeps its name in the output.
func (f *fnConv) namedConst(e ast.Expr) bool {
	var id *ast.Ident
	switch x := ast.Unparen(e).(type) {
	case *ast.Ident:
		id = x
	case *ast.SelectorExpr:
		id = x.Sel
	default:
		return false
	}
	k, ok := f.c.p.Info.Uses[id].(*types.Const)
	return ok && f.c.r.Objs[k] && f.c.wantsConstDecl(k)
}

func (f *fnConv) expr(e ast.Expr) string {
	c := f.c
	info := c.p.Info
	tv := info.Types[e]
	if tv.Value != nil {
		if f.namedConst(e) {
			var id *ast.Ident
			if s, ok := ast.Unparen(e).(*ast.SelectorExpr); ok {
				id = s.Sel
			} else {
				id = ast.Unparen(e).(*ast.Ident)
			}
			return c.valueName(info.Uses[id])
		}
		return c.literal(tv.Value, tv.Type, e)
	}
	switch e := e.(type) {
	case *ast.ParenExpr:
		return "(" + f.expr(e.X) + ")"
	case *ast.Ident:
		return f.ident(e)
	case *ast.SelectorExpr:
		if sel := info.Selections[e]; sel != nil {
			switch sel.Kind() {
			case types.FieldVal:
				return f.expr(e.X) + c.embedPath(e, sel) + "." + fieldName(e.Sel.Name)
			default:
				c.fail(e, "func-value", "method value %s", c.exprString(e))
			}
		}
		return f.ident(e.Sel)
	case *ast.StarExpr:
		return f.expr(e.X)
	case *ast.IndexExpr:
		return f.index(e)
	case *ast.SliceExpr:
		return f.slice(e)
	case *ast.UnaryExpr:
		return f.unary(e)
	case *ast.BinaryExpr:
		return f.binaryExpr(e)
	case *ast.CallExpr:
		return f.call(e)
	case *ast.CompositeLit:
		return f.composite(e)
	case *ast.FuncLit:
		return f.funcValue(e)
	case *ast.TypeAssertExpr:
		c.fail(e, "type-switch", "type assertion")
	}
	c.fail(e, "expression", "expression %T", e)
	return ""
}

func (f *fnConv) ident(id *ast.Ident) string {
	c := f.c
	obj := c.p.Info.Uses[id]
	switch o := obj.(type) {
	case *types.Var:
		if name, ok := f.locals[o]; ok {
			return name
		}
		if isPackageLevel(o) && c.p.inModule(o) && c.isLookupVar(o) {
			c.fail(id, "lookup-map", "map %s (converted to a lookup function) used other than by key or len", id.Name)
		}
		if isPackageLevel(o) && c.p.inModule(o) && c.globalFunc(o) {
			c.decide("a read-only global holding a string is built by a function call (stage 0 const workaround)")
			return c.valueName(o) + "()"
		}
		if isPackageLevel(o) && c.p.inModule(o) {
			return c.valueName(o)
		}
		if isPackageLevel(o) {
			c.fail(id, "stdlib-var", "standard-library variable %s", stdlibName(o))
		}
		c.fail(id, "closure", "variable %s from an enclosing function", id.Name)
	case *types.Nil:
		c.fail(id, "nil", "nil")
	case *types.Func:
		if v := f.funcValue(id); v != "" {
			return v
		}
		c.fail(id, "func-value", "function %s used as a value", id.Name)
	case *types.Const:
		return c.literal(o.Val(), o.Type(), id)
	}
	c.fail(id, "expression", "name %s", id.Name)
	return ""
}

// place converts an expression that is changed (assigned, or passed to a write
// parameter): no copies, and & and * dropped.
func (f *fnConv) place(e ast.Expr) string {
	c := f.c
	switch x := e.(type) {
	case *ast.ParenExpr:
		return f.place(x.X)
	case *ast.Ident:
		if v, ok := c.p.Info.Uses[x].(*types.Var); ok && isPackageLevel(v) {
			c.fail(x, "mutable-global", "package variable %s changed", x.Name)
		}
		return f.ident(x)
	case *ast.StarExpr:
		return f.place(x.X)
	case *ast.UnaryExpr:
		if x.Op == token.AND {
			return f.place(x.X)
		}
	case *ast.SelectorExpr:
		if sel := c.p.Info.Selections[x]; sel != nil && sel.Kind() == types.FieldVal {
			return f.place(x.X) + c.embedPath(x, sel) + "." + fieldName(x.Sel.Name)
		}
	case *ast.IndexExpr:
		xt := c.p.Info.TypeOf(x.X).Underlying()
		if _, ok := xt.(*types.Map); ok {
			c.fail(x, "map", "map element changed in place")
		}
		if isGoString(xt) {
			c.fail(x, "string", "string byte assigned")
		}
		return f.place(x.X) + "[" + f.indexValue(x.Index) + "]"
	}
	c.fail(e, "address-of", "changing %s (not a variable, field or element)", c.exprString(e))
	return ""
}

// indexValue converts an index: next-lang indexes are long.
func (f *fnConv) indexValue(e ast.Expr) string {
	c := f.c
	t := c.p.Info.TypeOf(e)
	if tv := c.p.Info.Types[e]; tv.Value != nil {
		return c.literal(tv.Value, types.Typ[types.Int], e)
	}
	if c.intBase(t) == "long" {
		if _, named := t.(*types.Named); !named && !isU32(t) {
			return f.expr(e)
		}
	}
	return "(long)(" + f.expr(e) + ")"
}

func isU32(t types.Type) bool {
	b, ok := t.Underlying().(*types.Basic)
	return ok && b.Kind() == types.Uint32
}

func (f *fnConv) index(e *ast.IndexExpr) string {
	c := f.c
	info := c.p.Info
	if tv, ok := info.Types[e.X]; ok && tv.IsType() {
		c.fail(e, "generic", "generic instantiation")
	}
	if _, ok := info.Instances[rootIdent(e.X)]; ok {
		c.fail(e, "generic", "generic instantiation")
	}
	xt := info.TypeOf(e.X).Underlying()
	if p, ok := xt.(*types.Pointer); ok {
		xt = p.Elem().Underlying()
	}
	switch xt.(type) {
	case *types.Map:
		return "(" + f.mapGetOption(e) + " ?? " + c.zero(info.TypeOf(e), "") + ")"
	}
	return f.expr(e.X) + "[" + f.indexValue(e.Index) + "]"
}

// mapKey converts a key for a map of type mt. String keys are stored as Ascii.
func (f *fnConv) mapKey(mt types.Type, k ast.Expr) string {
	m := mt.Underlying().(*types.Map)
	if !isGoString(m.Key()) {
		return f.valueExpr(k, m.Key())
	}
	if tv := f.c.p.Info.Types[k]; tv.Value != nil {
		s := constant.StringVal(tv.Value)
		if isASCII(s) {
			return strings.TrimPrefix(bytesLiteral(s), "b")
		}
	}
	return f.expr(k) + ".to_ascii().unwrap()"
}

func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= 128 || s[i] < 32 && s[i] != '\n' && s[i] != '\t' {
			return false
		}
	}
	return true
}

// mapGetOption is m[k] as an Option (none when the key is missing).
func (f *fnConv) mapGetOption(e *ast.IndexExpr) string {
	c := f.c
	if lt, ok := f.lookupOf(e.X); ok {
		return lt.get + "(" + f.valueExpr(e.Index, nil) + ")"
	}
	mt := c.p.Info.TypeOf(e.X)
	m := mt.Underlying().(*types.Map)
	if isGoString(m.Key()) {
		if tv := c.p.Info.Types[e.Index]; tv.Value == nil {
			key := f.tmp("key")
			found := f.tmp("found")
			f.pre("let %s: Option<%s> = match %s.to_ascii() { ok(%s) => %s.get(%s), err(_) => none }", found, c.nlType(m.Elem(), ""), f.expr(e.Index), key, f.expr(e.X), key)
			return found
		}
	}
	return fmt.Sprintf("%s.get(%s)", f.expr(e.X), f.mapKey(mt, e.Index))
}

func (f *fnConv) mapSet(ix *ast.IndexExpr, value string) {
	mt := f.c.p.Info.TypeOf(ix.X)
	f.line("%s.set(%s, %s).unwrap()", f.place(ix.X), f.mapKey(mt, ix.Index), value)
	f.c.decide("m[k] = v becomes m.set(k, v).unwrap()")
}

func (f *fnConv) slice(e *ast.SliceExpr) string {
	c := f.c
	if e.Slice3 {
		c.fail(e, "slice-expr", "three-index slice")
	}
	xt := c.p.Info.TypeOf(e.X)
	if !isGoString(xt) {
		c.fail(e, "slice-expr", "slicing a %s (only strings so far)", xt)
	}
	x := f.expr(e.X)
	lo, hi := "0L", x+".len()"
	if e.Low != nil {
		lo = f.indexValue(e.Low)
	}
	if e.High != nil {
		hi = f.indexValue(e.High)
	}
	return fmt.Sprintf("%s.slice(%s..%s)", x, lo, hi)
}

func (f *fnConv) unary(e *ast.UnaryExpr) string {
	c := f.c
	t := c.p.Info.TypeOf(e)
	switch e.Op {
	case token.SUB:
		return "-(" + f.expr(e.X) + ")"
	case token.ADD:
		return f.expr(e.X)
	case token.NOT:
		return "!(" + f.expr(e.X) + ")"
	case token.XOR:
		return "(" + f.expr(e.X) + " ^ " + f.allOnes(t) + ")"
	case token.AND:
		if _, ok := ast.Unparen(e.X).(*ast.CompositeLit); ok {
			return f.expr(e.X)
		}
		c.fail(e, "address-of", "address of %s", c.exprString(e.X))
	}
	c.fail(e, "expression", "unary %s", e.Op)
	return ""
}

// allOnes is the value whose bits are all set, for Go's ^x and &^.
func (f *fnConv) allOnes(t types.Type) string {
	switch f.c.intBase(t) {
	case "long":
		if isU32(t) {
			return "4294967295L"
		}
		return "-1L"
	case "int":
		if b, ok := t.Underlying().(*types.Basic); ok && b.Kind() == types.Uint16 {
			return "65535"
		}
		return "-1"
	case "byte":
		return "255"
	}
	f.c.fail(nil, "type", "bitwise not of %s", t)
	return ""
}

var binOps = map[token.Token]string{
	token.ADD: "+", token.SUB: "-", token.MUL: "*", token.QUO: "/", token.REM: "%",
	token.EQL: "==", token.NEQ: "!=", token.LSS: "<", token.LEQ: "<=", token.GTR: ">", token.GEQ: ">=",
	token.LAND: "&&", token.LOR: "||", token.AND: "&", token.OR: "|", token.XOR: "^",
	token.SHL: "<<", token.SHR: ">>",
}

func (f *fnConv) binaryExpr(e *ast.BinaryExpr) string {
	c := f.c
	info := c.p.Info
	lt, rt := info.TypeOf(e.X), info.TypeOf(e.Y)
	if isNilType(lt) || isNilType(rt) {
		other, ot := e.X, lt
		if isNilType(lt) {
			other, ot = e.Y, rt
		}
		if _, ok := ot.Underlying().(*types.Signature); ok && (e.Op == token.EQL || e.Op == token.NEQ) {
			return "(" + f.expr(other) + " " + binOps[e.Op] + " 0L)"
		}
		c.fail(e, "nil", "comparison with nil")
	}
	// An untyped side takes the other side's type, as in Go.
	if isUntyped(lt) {
		lt = rt
	}
	if e.Op == token.AND_NOT {
		return "(" + f.valueExpr(e.X, lt) + " & (" + f.valueExpr(e.Y, lt) + " ^ " + f.allOnes(lt) + "))"
	}
	op := binOps[e.Op]
	if op == "" {
		c.fail(e, "expression", "operator %s", e.Op)
	}
	if isGoString(lt) && op == "+" {
		return "go_concat(" + f.valueExpr(e.X, lt) + ", " + f.valueExpr(e.Y, lt) + ")"
	}
	return f.binary(op, f.valueExpr(e.X, lt), e.Y, lt, rt)
}

// binary writes `left op right`, parenthesised: next-lang's precedence need not
// match Go's, so every converted operator carries its own parentheses.
func (f *fnConv) binary(op, left string, right ast.Expr, lt, rt types.Type) string {
	var r string
	if op == "<<" || op == ">>" {
		r = f.shiftCount(right, lt)
	} else {
		want := lt
		if op == "&&" || op == "||" {
			want = nil
		}
		r = f.valueExpr(right, want)
	}
	return "(" + left + " " + op + " " + r + ")"
}

// shiftCount converts a shift count to the shifted value's type.
func (f *fnConv) shiftCount(e ast.Expr, lt types.Type) string {
	c := f.c
	f.c.decide("shift counts are converted to the shifted type; an oversized shift fails (Go gives 0)")
	if tv := c.p.Info.Types[e]; tv.Value != nil {
		return c.literal(tv.Value, lt, e)
	}
	ct := c.p.Info.TypeOf(e)
	if c.intBase(ct) == c.intBase(lt) {
		return f.expr(e)
	}
	return f.convertInt(f.expr(e), ct, lt)
}

func isNilType(t types.Type) bool {
	b, ok := t.(*types.Basic)
	return ok && b.Kind() == types.UntypedNil
}

func isUntyped(t types.Type) bool {
	b, ok := t.(*types.Basic)
	return ok && b.Info()&types.IsUntyped != 0
}

// convertInt converts between Go integer types. A value that doesn't fit the
// target fails the program, where Go would truncate.
func (f *fnConv) convertInt(x string, from, to types.Type) string {
	c := f.c
	fb, tb := c.intBase(from), c.intBase(to)
	target := c.nlType(to, "")
	c.decide("integer conversion that doesn't fit fails the program (Go truncates)")
	switch tb {
	case "byte":
		if fb == "byte" {
			return x
		}
		if fb == "long" {
			x = "(int)(" + x + ")"
		}
		return "(" + x + ").fit<byte>().unwrap()"
	case "long", "int":
		if target == tb && fb == tb && !isU32(from) && !isNarrow(from) {
			return x
		}
		return "(" + target + ")(" + x + ")"
	}
	c.fail(nil, "type", "conversion to %s", to)
	return ""
}

// isNarrow: a Go type converted to a range alias (GoI16 and the like).
func isNarrow(t types.Type) bool {
	b, ok := t.Underlying().(*types.Basic)
	if !ok {
		return false
	}
	switch b.Kind() {
	case types.Int8, types.Int16, types.Uint16, types.Uint32:
		return true
	}
	return false
}

func (f *fnConv) call(e *ast.CallExpr) string {
	c := f.c
	info := c.p.Info
	fun := ast.Unparen(e.Fun)
	// Conversions T(x).
	if tv, ok := info.Types[fun]; ok && tv.IsType() {
		to := tv.Type
		from := info.TypeOf(e.Args[0])
		if c.intBase(to) != "" && c.intBase(from) != "" {
			return f.convertInt(f.expr(e.Args[0]), from, to)
		}
		if types.Identical(to.Underlying(), from.Underlying()) {
			return f.expr(e.Args[0])
		}
		if isGoString(to) || isGoString(from) {
			c.fail(e, "string-conv", "conversion %s", c.exprString(e))
		}
		c.fail(e, "conversion", "conversion %s", c.exprString(e))
	}
	if id, ok := fun.(*ast.Ident); ok {
		if b, ok := info.Uses[id].(*types.Builtin); ok {
			return f.builtin(b.Name(), e)
		}
	}
	callee := calleeFunc(c, e)
	if callee == nil {
		// A call through a function value: the family's dispatcher.
		sig, ok := info.TypeOf(e.Fun).Underlying().(*types.Signature)
		if !ok {
			c.fail(e, "func-value", "call of %s", c.exprString(e.Fun))
		}
		fam := c.familyOf(info.TypeOf(e.Fun))
		pi := &paramInfo{write: make([]bool, sig.Params().Len())}
		for i := range pi.write {
			pi.write[i] = fam.writes(c, i)
		}
		args := append([]string{f.expr(e.Fun)}, f.callArgs(e, sig, pi, 0, c.writeRootsOf(e, pi, nil))...)
		return fam.dispatch + "(" + strings.Join(args, ", ") + ")"
	}
	if !c.p.inModule(callee) {
		return f.stdlibCall(stdlibName(callee), e)
	}
	callee = callee.Origin()
	var args []string
	pi := c.modes.funcs[callee]
	idx := 0
	var recv ast.Expr
	if sel, ok := fun.(*ast.SelectorExpr); ok {
		if s := info.Selections[sel]; s != nil && s.Kind() == types.MethodVal {
			recv = sel.X
		}
	}
	if sel, ok := fun.(*ast.SelectorExpr); ok {
		if s := info.Selections[sel]; s != nil && s.Kind() == types.MethodVal {
			if types.IsInterface(s.Recv()) {
				c.fail(e, "interface-call", "method call through an interface (%s)", sel.Sel.Name)
			}
			path := c.embedPath(sel, s)
			if pi != nil && pi.write[0] {
				args = append(args, f.place(sel.X)+path)
			} else {
				args = append(args, f.expr(sel.X)+path)
			}
			idx = 1
		}
	}
	args = append(args, f.callArgs(e, callee.Signature(), pi, idx, c.writeRootsOf(e, pi, recv))...)
	return c.valueName(callee) + "(" + strings.Join(args, ", ") + ")"
}

func (f *fnConv) builtin(name string, e *ast.CallExpr) string {
	c := f.c
	info := c.p.Info
	switch name {
	case "len":
		t := info.TypeOf(e.Args[0]).Underlying()
		if p, ok := t.(*types.Pointer); ok {
			t = p.Elem().Underlying()
		}
		switch t := t.(type) {
		case *types.Basic:
			return f.expr(e.Args[0]) + ".len()"
		case *types.Slice, *types.Map:
			if lt, ok := f.lookupOf(e.Args[0]); ok {
				return fmt.Sprintf("%dL", lt.count)
			}
			return f.expr(e.Args[0]) + ".count()"
		case *types.Array:
			return fmt.Sprintf("%dL", t.Len())
		}
	case "min", "max":
		t := info.TypeOf(e)
		out := f.valueExpr(e.Args[0], t)
		for _, a := range e.Args[1:] {
			out = name + "(" + out + ", " + f.valueExpr(a, t) + ")"
		}
		return out
	case "append":
		c.fail(e, "append", "append used as a value")
	}
	c.fail(e, "builtin", "built-in %s", name)
	return ""
}

func (f *fnConv) composite(e *ast.CompositeLit) string {
	c := f.c
	t := c.p.Info.TypeOf(e)
	switch u := t.Underlying().(type) {
	case *types.Struct:
		var fields []string
		for i, el := range e.Elts {
			var name string
			var v ast.Expr
			if kv, ok := el.(*ast.KeyValueExpr); ok {
				name = kv.Key.(*ast.Ident).Name
				v = kv.Value
			} else {
				name = u.Field(i).Name()
				v = el
			}
			var ft types.Type
			for j := 0; j < u.NumFields(); j++ {
				if u.Field(j).Name() == name {
					ft = u.Field(j).Type()
				}
			}
			fields = append(fields, fieldName(name)+": "+f.valueExpr(v, ft))
		}
		if len(fields) == 0 {
			return c.nlType(t, "") + " {}"
		}
		return c.nlType(t, "") + " { " + strings.Join(fields, ", ") + " }"
	case *types.Array, *types.Slice:
		var elem types.Type
		if a, ok := u.(*types.Array); ok {
			elem = a.Elem()
			if int64(len(e.Elts)) != a.Len() {
				c.fail(e, "composite", "array literal with fewer elements than its length")
			}
		} else {
			elem = u.(*types.Slice).Elem()
		}
		var items []string
		for _, el := range e.Elts {
			if _, ok := el.(*ast.KeyValueExpr); ok {
				c.fail(e, "composite", "indexed array literal")
			}
			items = append(items, f.valueExpr(el, elem))
		}
		c.nlType(t, "")
		if _, ok := u.(*types.Slice); ok {
			if len(items) == 0 {
				return "list {}"
			}
			// A list literal needs its type from context; a typed temporary gives it one.
			lit := f.tmp("items")
			f.pre("let %s: %s = [%s]", lit, c.nlType(t, ""), strings.Join(items, ", "))
			return lit
		}
		return "[" + strings.Join(items, ", ") + "]"
	case *types.Map:
		if len(e.Elts) == 0 {
			c.nlType(t, "")
			return "map {}"
		}
		c.fail(e, "map", "non-empty map literal inside a function")
	}
	c.fail(e, "composite", "composite literal of %s", t)
	return ""
}

// buildCollection writes the body of a helper function that builds a package
// variable's map or slice literal.
func (f *fnConv) buildCollection(cl *ast.CompositeLit, t types.Type, where string) string {
	c := f.c
	f.ind = 1
	name := f.tmp("built")
	nt := c.nlType(t, where)
	switch u := t.Underlying().(type) {
	case *types.Map:
		f.line("var %s: %s = map {}", name, nt)
		for _, el := range cl.Elts {
			kv := el.(*ast.KeyValueExpr)
			f.line("%s.set(%s, %s).unwrap()", name, f.mapKey(t, kv.Key), f.valueExpr(kv.Value, u.Elem()))
		}
	case *types.Slice:
		f.line("var %s: %s = list {}", name, nt)
		for _, el := range cl.Elts {
			if _, ok := el.(*ast.KeyValueExpr); ok {
				c.fail(cl, "composite", "indexed slice literal")
			}
			f.line("%s.push(%s).unwrap()", name, f.valueExpr(el, u.Elem()))
		}
	}
	f.line("%s", name)
	return f.b.String()
}

// stdlibCall maps a standard-library call to the shim, or fails.
func (f *fnConv) stdlibCall(name string, e *ast.CallExpr) string {
	c := f.c
	args := func() []string {
		var out []string
		for _, a := range e.Args {
			out = append(out, f.valueExpr(a, nil))
		}
		return out
	}
	switch name {
	case "fmt.Println":
		if len(e.Args) != 1 {
			c.fail(e, "stdlib-call", "fmt.Println with %d arguments", len(e.Args))
		}
		t := c.p.Info.TypeOf(e.Args[0])
		switch u := t.Underlying().(type) {
		case *types.Basic:
			if u.Info()&(types.IsInteger|types.IsBoolean|types.IsString) != 0 {
				c.decide("fmt.Println of one integer, bool or string becomes print")
				return "print(" + f.valueExpr(e.Args[0], types.Default(t)) + ")"
			}
		}
		c.fail(e, "stdlib-call", "fmt.Println of %s", t)
	case "strings.HasPrefix", "strings.HasSuffix", "strings.IndexByte", "strings.Repeat", "strconv.Itoa":
		pkg, fn, _ := strings.Cut(name, ".")
		c.decide("standard-library call goes to the gostd shim")
		return "go_" + pkg + "_" + fn + "(" + strings.Join(args(), ", ") + ")"
	}
	c.fail(e, "stdlib-call", "%s has no shim yet", name)
	return ""
}

// lookupOf: e names a map variable converted to a lookup function.
func (f *fnConv) lookupOf(e ast.Expr) (lookupTable, bool) {
	var id *ast.Ident
	switch x := ast.Unparen(e).(type) {
	case *ast.Ident:
		id = x
	case *ast.SelectorExpr:
		id = x.Sel
	default:
		return lookupTable{}, false
	}
	obj := f.c.p.Info.Uses[id]
	if obj == nil {
		return lookupTable{}, false
	}
	if lt, ok := f.c.lookups[obj]; ok {
		return lt, true
	}
	// Not converted yet: convert the variable now so its kind is known.
	if v, ok := obj.(*types.Var); ok && isPackageLevel(v) && f.c.isLookupVar(v) {
		f.c.lookups[v] = lookupTable{get: f.c.valueName(v) + "_get", count: f.c.lookupCount(v)}
		return f.c.lookups[v], true
	}
	return lookupTable{}, false
}

// embedPath spells out a promoted selection: Go's s.pos, where pos lives in
// an embedded ScannerState, is next-lang's s.ScannerState.pos.
func (c *conv) embedPath(e *ast.SelectorExpr, sel *types.Selection) string {
	idx := sel.Index()
	if len(idx) <= 1 {
		return ""
	}
	t := sel.Recv()
	path := ""
	for _, i := range idx[:len(idx)-1] {
		if p, ok := t.Underlying().(*types.Pointer); ok {
			t = p.Elem()
		}
		st, ok := t.Underlying().(*types.Struct)
		if !ok {
			c.fail(e, "embedding", "promotion through %s", t)
		}
		fld := st.Field(i)
		if _, ok := fld.Type().Underlying().(*types.Pointer); ok {
			c.fail(e, "embedding", "promotion through embedded pointer %s", fld.Name())
		}
		path += "." + fieldName(fld.Name())
		t = fld.Type()
	}
	c.decide("embedded struct becomes a named field; promoted fields and methods go through it")
	return path
}
