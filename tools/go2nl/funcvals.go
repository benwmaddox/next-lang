package main

import (
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"sort"
	"strings"
)

// Function values, by defunctionalisation. next-lang has no closures, and its
// function values carry effect annotations a converter would have to infer, so
// go2nl replaces every Go function value with a number:
//
//   - Functions of one signature that are ever used as values form a family.
//     Each member gets an id (1, 2, ...); 0 is Go's nil.
//   - A function literal that captures nothing is lifted to a top-level
//     function and joins its family; one that captures a local is refused.
//   - Calling a function value calls the family's dispatcher, which compares
//     the id and calls the member directly.
//
// The set of members is closed over the whole converted program, so this is
// exact for the roots the config names.

type family struct {
	key      string
	sig      *types.Signature
	typeName string // the next-lang type of a value of this family
	dispatch string
	members  []*member
}

type member struct {
	id   int
	name string       // the next-lang function called
	fn   *types.Func  // a named function, or
	lit  *ast.FuncLit // a lifted literal
	in   types.Object // the declaration the literal is in
}

func sigKey(sig *types.Signature) string {
	var parts []string
	for i := 0; i < sig.Params().Len(); i++ {
		parts = append(parts, types.TypeString(sig.Params().At(i).Type(), nil))
	}
	var res []string
	for i := 0; i < sig.Results().Len(); i++ {
		res = append(res, types.TypeString(sig.Results().At(i).Type(), nil))
	}
	v := ""
	if sig.Variadic() {
		v = "..."
	}
	return "func(" + strings.Join(parts, ",") + v + ")(" + strings.Join(res, ",") + ")"
}

// findFuncValues is the pre-pass: it finds every function used as a value and
// every function literal in the reachable code, and builds the families.
func (c *conv) findFuncValues() {
	c.families = map[string]*family{}
	c.litMember = map[*ast.FuncLit]*member{}
	c.fnMember = map[*types.Func]*member{}
	litCount := map[types.Object]int{}
	for _, obj := range c.r.Order {
		decl := c.p.Decls[obj]
		if decl == nil {
			continue
		}
		var body ast.Node = decl
		if fd, ok := decl.(*ast.FuncDecl); ok {
			if fd.Body == nil {
				continue
			}
			body = fd.Body
		}
		called := map[*ast.Ident]bool{}
		ast.Inspect(body, func(n ast.Node) bool {
			if call, ok := n.(*ast.CallExpr); ok {
				switch fun := ast.Unparen(call.Fun).(type) {
				case *ast.Ident:
					called[fun] = true
				case *ast.SelectorExpr:
					called[fun.Sel] = true
				case *ast.IndexExpr:
					if id, ok := fun.X.(*ast.Ident); ok {
						called[id] = true
					}
				}
			}
			return true
		})
		ast.Inspect(body, func(n ast.Node) bool {
			switch n := n.(type) {
			case *ast.FuncLit:
				sig, ok := c.typeOf(n).(*types.Signature)
				if !ok {
					return true
				}
				litCount[obj]++
				name := c.top.claim(fmt.Sprintf("lambda_%s_%d", c.valueName(obj), litCount[obj]))
				m := &member{name: name, lit: n, in: obj}
				c.litMember[n] = m
				c.addMember(sig, m)
				return false
			case *ast.Ident:
				if called[n] {
					return true
				}
				f, ok := c.p.Info.Uses[n].(*types.Func)
				if !ok || !c.p.inModule(f) || f.Signature().Recv() != nil {
					return true
				}
				f = f.Origin()
				if c.fnMember[f] == nil {
					m := &member{fn: f}
					c.fnMember[f] = m
					c.addMember(f.Signature(), m)
				}
			}
			return true
		})
	}
	// Ids in a fixed order: by family, then member name.
	var keys []string
	for k := range c.families {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for i, k := range keys {
		fam := c.families[k]
		fam.typeName = c.top.claim(fmt.Sprintf("GoFn%d", i+1))
		fam.dispatch = c.top.claim(fmt.Sprintf("go_call_fn%d", i+1))
		for _, m := range fam.members {
			if m.fn != nil {
				m.name = c.valueName(m.fn)
			}
		}
		sort.SliceStable(fam.members, func(a, b int) bool { return fam.members[a].name < fam.members[b].name })
		for j, m := range fam.members {
			m.id = j + 1
		}
	}
}

func (c *conv) addMember(sig *types.Signature, m *member) {
	key := sigKey(sig)
	fam := c.families[key]
	if fam == nil {
		fam = &family{key: key, sig: sig}
		c.families[key] = fam
	}
	fam.members = append(fam.members, m)
}

func (c *conv) familyOf(t types.Type) *family {
	sig, ok := t.Underlying().(*types.Signature)
	if !ok {
		return nil
	}
	fam := c.families[sigKey(sig)]
	if fam == nil {
		// A function type no value ever reaches: only nil flows through it.
		fam = &family{key: sigKey(sig), sig: sig}
		c.families[fam.key] = fam
		fam.typeName = c.top.claim(fmt.Sprintf("GoFn%d", len(c.families)))
		fam.dispatch = c.top.claim(fmt.Sprintf("go_call_fn%d", len(c.families)))
	}
	c.decide("function value becomes a numbered member of its signature's family (0 is nil), called through a dispatcher")
	c.usedFamilies[fam] = true
	return fam
}

// funcValue converts a function used as a value, or a function literal.
func (f *fnConv) funcValue(e ast.Expr) string {
	c := f.c
	switch x := ast.Unparen(e).(type) {
	case *ast.FuncLit:
		m := c.litMember[x]
		if m == nil {
			c.fail(x, "closure", "function literal not found by the pre-pass")
		}
		c.familyOf(c.typeOf(x))
		c.liftLiteral(m)
		return fmt.Sprintf("%dL", m.id)
	case *ast.Ident, *ast.SelectorExpr:
		var id *ast.Ident
		if s, ok := x.(*ast.SelectorExpr); ok {
			if sel := c.p.Info.Selections[s]; sel != nil {
				c.fail(x, "func-value", "method value %s", c.exprString(x))
			}
			id = s.Sel
		} else {
			id = x.(*ast.Ident)
		}
		fn, ok := c.p.Info.Uses[id].(*types.Func)
		if !ok {
			return ""
		}
		m := c.fnMember[fn.Origin()]
		if m == nil {
			c.fail(x, "func-value", "%s used as a value but not found by the pre-pass", id.Name)
		}
		c.familyOf(fn.Signature())
		return fmt.Sprintf("%dL", m.id)
	}
	return ""
}

// liftLiteral emits a function literal as a top-level function, once.
func (c *conv) liftLiteral(m *member) {
	if c.lifted[m] {
		return
	}
	c.lifted[m] = true
	lit := m.lit
	// Refuse captures: any local of an enclosing function used inside.
	ast.Inspect(lit.Body, func(n ast.Node) bool {
		id, ok := n.(*ast.Ident)
		if !ok {
			return true
		}
		v, ok := c.p.Info.Uses[id].(*types.Var)
		if !ok || v.IsField() || isPackageLevel(v) {
			return true
		}
		if v.Pos() < lit.Pos() || v.Pos() >= lit.End() {
			c.fail(id, "closure", "function literal captures %s", id.Name)
		}
		return true
	})
	sig := c.typeOf(lit).(*types.Signature)
	text := c.emitFunc(m.name, nil, nil, lit.Type, lit.Body, sig)
	c.extra = append(c.extra, fmt.Sprintf("// function literal lifted from %s (%s)\n%s", c.p.objName(m.in), c.p.pos(lit), text))
	c.decide("function literal that captures nothing is lifted to a top-level function")
}

// dispatchers writes each used family's type and dispatcher.
func (c *conv) dispatchers() string {
	var keys []string
	for fam := range c.usedFamilies {
		keys = append(keys, fam.key)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		fam := c.families[k]
		sig := fam.sig
		fmt.Fprintf(&b, "// %s values: 0 is nil", k)
		for _, m := range fam.members {
			fmt.Fprintf(&b, ", %d is %s", m.id, m.name)
		}
		fmt.Fprintf(&b, "\ntype %s = long\n", fam.typeName)
		var params, args []string
		for i := 0; i < sig.Params().Len(); i++ {
			t := sig.Params().At(i).Type()
			nt := ""
			if sig.Variadic() && i == sig.Params().Len()-1 {
				nt = c.variadicType(t.(*types.Slice).Elem())
			} else {
				nt = c.nlType(t, "")
			}
			mode := ""
			if fam.writes(c, i) {
				mode = "write "
			}
			params = append(params, fmt.Sprintf("a%d: %s%s", i, mode, nt))
			args = append(args, fmt.Sprintf("a%d", i))
		}
		res := ""
		zero := ""
		if sig.Results().Len() == 1 {
			res = " -> " + c.nlType(sig.Results().At(0).Type(), "")
			zero = c.zero(sig.Results().At(0).Type(), "")
		} else if sig.Results().Len() > 1 {
			c.fail(nil, "multi-return", "function value with several results")
		}
		fmt.Fprintf(&b, "fn %s(fnid: %s", fam.dispatch, fam.typeName)
		for _, p := range params {
			b.WriteString(", " + p)
		}
		fmt.Fprintf(&b, ")%s {\n", res)
		for _, m := range fam.members {
			call := fmt.Sprintf("%s(%s)", m.name, strings.Join(args, ", "))
			if res == "" {
				fmt.Fprintf(&b, "    if fnid == %dL {\n        %s\n        return\n    }\n", m.id, call)
			} else {
				fmt.Fprintf(&b, "    if fnid == %dL { return %s }\n", m.id, call)
			}
		}
		b.WriteString("    go_panic()\n")
		if zero != "" {
			b.WriteString("    " + zero + "\n")
		}
		b.WriteString("}\n\n")
	}
	return b.String()
}

// writes: some member changes parameter i through a pointer.
func (fam *family) writes(c *conv, i int) bool {
	for _, m := range fam.members {
		if m.fn == nil {
			continue
		}
		if pi := c.modes.funcs[m.fn]; pi != nil && i < len(pi.write) && pi.write[i] {
			return true
		}
	}
	return false
}

// ---- variadic parameters and any ----

func (c *conv) variadicMax() int64 { return c.cfg.capacity("default.variadic", "", 8) }

// variadicType is the list a variadic parameter ...T becomes.
func (c *conv) variadicType(elem types.Type) string {
	c.decide("variadic ...T becomes list<T, go_variadic_max>")
	return fmt.Sprintf("list<%s, go_variadic_max>", c.nlType(elem, ""))
}

func isEmptyInterface(t types.Type) bool {
	it, ok := t.Underlying().(*types.Interface)
	return ok && it.Empty()
}

// box converts a value to Go's any, which next-lang holds as the GoAny enum.
func (f *fnConv) box(e ast.Expr) string {
	c := f.c
	t := c.typeOf(e)
	c.decide("any becomes the GoAny enum (strings, integers and booleans only)")
	if isNilType(t) {
		return "GoAny.Nil"
	}
	if isEmptyInterface(t) {
		return f.expr(e)
	}
	b, ok := t.Underlying().(*types.Basic)
	if !ok {
		c.fail(e, "any-conversion", "%s stored in any", t)
	}
	switch {
	case b.Info()&types.IsString != 0:
		return "GoAny.Str(" + f.valueExpr(e, types.Typ[types.String]) + ")"
	case b.Info()&types.IsBoolean != 0:
		return "GoAny.Bool(" + f.valueExpr(e, types.Typ[types.Bool]) + ")"
	case b.Info()&types.IsInteger != 0:
		if tv := c.p.Info.Types[e]; tv.Value != nil {
			return "GoAny.Int(" + c.literal(tv.Value, types.Typ[types.Int], e) + ")"
		}
		return "GoAny.Int(" + f.convertInt(f.expr(e), t, types.Typ[types.Int]) + ")"
	}
	c.fail(e, "any-conversion", "%s stored in any", t)
	return ""
}

// callArgs converts a call's arguments for a function of signature sig whose
// parameter modes are pi (nil for a dispatcher with no writes). first is the
// index of the first argument's parameter (1 after a receiver).
func (f *fnConv) callArgs(e *ast.CallExpr, sig *types.Signature, pi *paramInfo, first int, writeRoots map[types.Object]bool) []string {
	c := f.c
	var args []string
	n := sig.Params().Len()
	fixed := n
	if sig.Variadic() {
		fixed = n - 1
	}
	for i := 0; i < fixed && i < len(e.Args); i++ {
		write := pi != nil && first+i < len(pi.write) && pi.write[first+i]
		a := f.argFor(e.Args[i], pi, first+i, sig.Params().At(i).Type())
		if _, bound := f.boundArgs[e.Args[i]]; !write && !bound && mentions(c, e.Args[i], writeRoots) {
			// Go copies the value before the call; next-lang refuses a read
			// argument that overlaps a write one, so copy it first.
			t := f.tmp("arg")
			f.pre("let %s: %s = %s", t, c.nlType(sig.Params().At(i).Type(), ""), a)
			a = t
			c.decide("an argument that overlaps a write argument is copied first (Go passes it by value)")
		}
		args = append(args, a)
	}
	if !sig.Variadic() {
		return args
	}
	elem := sig.Params().At(n - 1).Type().(*types.Slice).Elem()
	if e.Ellipsis.IsValid() {
		// f(xs...): only a variadic parameter passed on keeps the list type.
		spread := ast.Unparen(e.Args[len(e.Args)-1])
		id, ok := spread.(*ast.Ident)
		if !ok || !f.variadicParams[c.p.Info.Uses[id]] {
			c.fail(e, "variadic", "spreading %s into a variadic call (only a variadic parameter passed on is converted)", c.exprString(spread))
		}
		return append(args, f.ident(id))
	}
	var items []string
	for _, a := range e.Args[fixed:] {
		if mentions(c, a, writeRoots) && !isEmptyInterface(elem) {
			c.decide("an argument that overlaps a write argument is copied first (Go passes it by value)")
		}
		if isEmptyInterface(elem) {
			items = append(items, f.box(a))
		} else {
			items = append(items, f.valueExpr(a, elem))
		}
	}
	if int64(len(items)) > c.variadicMax() {
		c.fail(e, "variadic", "%d variadic arguments, more than default.variadic (%d)", len(items), c.variadicMax())
	}
	va := f.tmp("varargs")
	if len(items) == 0 {
		f.pre("let %s: %s = list {}", va, c.variadicType(elem))
	} else {
		f.pre("let %s: %s = [%s]", va, c.variadicType(elem), strings.Join(items, ", "))
	}
	return append(args, va)
}

func (f *fnConv) argFor(a ast.Expr, pi *paramInfo, i int, pt types.Type) string {
	if v, ok := f.boundArgs[a]; ok {
		return v
	}
	if pi != nil && i < len(pi.write) && pi.write[i] {
		return f.place(a)
	}
	if isEmptyInterface(pt) {
		return f.box(a)
	}
	if _, ok := pt.Underlying().(*types.Signature); ok {
		if v := f.funcValue(a); v != "" {
			return v
		}
		if isNilType(f.c.typeOf(a)) {
			return "0L"
		}
	}
	return f.valueExpr(a, pt)
}

// isNilIdent: e is the predeclared nil.
func (c *conv) isNilIdent(e ast.Expr) bool {
	id, ok := ast.Unparen(e).(*ast.Ident)
	if !ok {
		return false
	}
	_, isNil := c.p.Info.Uses[id].(*types.Nil)
	return isNil
}

var _ = token.ADD

// mentions: e reads one of the variables in roots.
func mentions(c *conv, e ast.Expr, roots map[types.Object]bool) bool {
	if len(roots) == 0 {
		return false
	}
	found := false
	ast.Inspect(e, func(n ast.Node) bool {
		if id, ok := n.(*ast.Ident); ok && roots[c.p.Info.Uses[id]] {
			found = true
		}
		return !found
	})
	return found
}

// writeRootsOf: the variables a call changes through its write arguments.
func (c *conv) writeRootsOf(e *ast.CallExpr, pi *paramInfo, recv ast.Expr) map[types.Object]bool {
	roots := map[types.Object]bool{}
	if pi == nil {
		return roots
	}
	first := 0
	if recv != nil {
		if pi.write[0] {
			if id := rootIdent(recv); id != nil {
				roots[c.p.Info.Uses[id]] = true
			}
		}
		first = 1
	}
	for i, a := range e.Args {
		if first+i < len(pi.write) && pi.write[first+i] {
			if id := rootIdent(a); id != nil {
				roots[c.p.Info.Uses[id]] = true
			}
		}
	}
	return roots
}
