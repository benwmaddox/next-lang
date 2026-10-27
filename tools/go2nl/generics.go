package main

import (
	"go/ast"
	"go/types"
	"sort"
	"strings"
	"unicode"
)

// Generic functions, by monomorphisation: each set of type arguments a
// generic function is called with gets its own next-lang copy, named
// f__T1_T2, with the type parameters replaced. Arguments are still evaluated
// before the call, as in Go (core.IfElse stays eager).

type instance struct {
	fn    *types.Func // the generic function (its origin), or the function copied
	targs []types.Type
	bound map[int]*types.Func // parameters bound to a method value
	name  string
}

// typeOf is the Go type of e with the current type substitution applied.
func (c *conv) typeOf(e ast.Expr) types.Type { return c.resolve(c.p.Info.TypeOf(e)) }

// resolve replaces type parameters with the current instance's arguments.
func (c *conv) resolve(t types.Type) types.Type {
	if c.subst == nil || t == nil {
		return t
	}
	switch u := t.(type) {
	case *types.TypeParam:
		if r, ok := c.subst[u]; ok {
			return r
		}
	case *types.Pointer:
		return types.NewPointer(c.resolve(u.Elem()))
	case *types.Slice:
		return types.NewSlice(c.resolve(u.Elem()))
	case *types.Array:
		return types.NewArray(c.resolve(u.Elem()), u.Len())
	case *types.Map:
		return types.NewMap(c.resolve(u.Key()), c.resolve(u.Elem()))
	case *types.Named:
		if u.TypeArgs().Len() > 0 {
			var args []types.Type
			for i := 0; i < u.TypeArgs().Len(); i++ {
				args = append(args, c.resolve(u.TypeArgs().At(i)))
			}
			if r, err := types.Instantiate(nil, u.Origin(), args, false); err == nil {
				return r
			}
		}
	case *types.Signature:
		params := c.resolveTuple(u.Params())
		results := c.resolveTuple(u.Results())
		return types.NewSignatureType(nil, nil, nil, params, results, u.Variadic())
	}
	return t
}

func (c *conv) resolveTuple(t *types.Tuple) *types.Tuple {
	var vars []*types.Var
	for i := 0; i < t.Len(); i++ {
		v := t.At(i)
		vars = append(vars, types.NewParam(v.Pos(), v.Pkg(), v.Name(), c.resolve(v.Type())))
	}
	return types.NewTuple(vars...)
}

func isGeneric(fn *types.Func) bool {
	sig := fn.Origin().Signature()
	return sig.TypeParams().Len() > 0 || (sig.Recv() != nil && sig.RecvTypeParams().Len() > 0)
}

// instanceName records (once) and names the copy of generic fn for the type
// arguments Go inferred at id.
func (c *conv) instanceName(fn *types.Func, id *ast.Ident) string {
	inst, ok := c.p.Info.Instances[id]
	if !ok {
		c.fail(id, "generic", "generic call without type arguments")
	}
	var targs []types.Type
	var keys []string
	for i := 0; i < inst.TypeArgs.Len(); i++ {
		t := c.resolve(inst.TypeArgs.At(i))
		targs = append(targs, t)
		keys = append(keys, mangleType(t))
	}
	origin := fn.Origin()
	key := c.valueName(origin) + "[" + strings.Join(keys, ",") + "]"
	if in, ok := c.instances[key]; ok {
		return in.name
	}
	in := &instance{fn: origin, targs: targs, name: c.top.claim(c.valueName(origin) + "__" + strings.Join(keys, "_"))}
	c.instances[key] = in
	c.instOrder = append(c.instOrder, in)
	c.decide("generic function is copied for each set of type arguments")
	return in.name
}

func mangleType(t types.Type) string {
	s := types.TypeString(t, func(p *types.Package) string { return p.Name() })
	var b strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	return strings.Trim(b.String(), "_")
}

// emitInstances writes every instance, including ones that instances call.
func (c *conv) emitInstances() {
	for done := 0; done < len(c.instOrder); done++ {
		in := c.instOrder[done]
		fd := c.p.Decls[in.fn].(*ast.FuncDecl)
		sym := c.p.objName(in.fn) + "[" + in.name + "]"
		rec := DeclRecord{Symbol: sym, Source: c.p.pos(fd), Target: in.name}
		c.decisions = map[string]bool{}
		c.extra = nil
		text := ""
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
					c.res.convertedObjs[in.fn] = false
				}
			}()
			sig := in.fn.Signature()
			if len(in.targs) > 0 {
				c.subst = map[*types.TypeParam]types.Type{}
			}
			tps := sig.TypeParams()
			if sig.Recv() != nil && sig.RecvTypeParams().Len() > 0 {
				tps = sig.RecvTypeParams()
			}
			for i := 0; i < tps.Len() && i < len(in.targs); i++ {
				c.subst[tps.At(i)] = in.targs[i]
			}
			c.curBound = in.bound
			rsig := c.resolve(sig).(*types.Signature)
			c.curBound = in.bound
			text = c.emitFunc(in.name, in.fn, fd.Recv, fd.Type, fd.Body, rsig)
			c.curBound = nil
			rec.Status = "converted"
		}()
		c.subst = nil
		for d := range c.decisions {
			rec.Decisions = append(rec.Decisions, d)
		}
		sort.Strings(rec.Decisions)
		c.res.Decls = append(c.res.Decls, rec)
		if text == "" {
			continue
		}
		file := c.p.shortPkg(in.fn.Pkg().Path()) + ".nl"
		b := c.res.files[file]
		if b == nil {
			b = &strings.Builder{}
			c.res.files[file] = b
		}
		b.WriteString("// " + sym + " (" + rec.Source + ")\n" + text + "\n")
		for _, x := range c.extra {
			b.WriteString(x + "\n")
		}
	}
}

// Bound method values, by specialisation: g(x, s.errorAt) calls a copy of g in
// which the callback parameter holds the receiver s instead, and calling the
// parameter calls errorAt(s, ...) directly. It works when g only calls the
// parameter or compares it with nil, which the copy checks as it converts.

// boundMethods finds the arguments of call e that are method values passed
// to function-typed parameters of callee.
func (c *conv) boundMethods(e *ast.CallExpr, first int) (map[int]*types.Func, map[int]ast.Expr) {
	var bound map[int]*types.Func
	var recvs map[int]ast.Expr
	for i, a := range e.Args {
		sel, ok := ast.Unparen(a).(*ast.SelectorExpr)
		if !ok {
			continue
		}
		s := c.p.Info.Selections[sel]
		if s == nil || s.Kind() != types.MethodVal {
			continue
		}
		m, ok := s.Obj().(*types.Func)
		if !ok || !c.p.inModule(m) {
			c.fail(a, "func-value", "method value %s", c.exprString(a))
		}
		if bound == nil {
			bound = map[int]*types.Func{}
			recvs = map[int]ast.Expr{}
		}
		bound[first+i] = m.Origin()
		recvs[first+i] = sel.X
	}
	return bound, recvs
}

// cloneName records (once) and names the copy of fn with bound parameters.
func (c *conv) cloneName(fn *types.Func, bound map[int]*types.Func) string {
	var keys []int
	for k := range bound {
		keys = append(keys, k)
	}
	sort.Ints(keys)
	var parts []string
	for _, k := range keys {
		parts = append(parts, bound[k].Name())
	}
	key := c.valueName(fn) + "{" + strings.Join(parts, ",") + "}"
	if in, ok := c.instances[key]; ok {
		return in.name
	}
	in := &instance{fn: fn, bound: bound, name: c.top.claim(c.valueName(fn) + "__with_" + strings.Join(parts, "_"))}
	c.instances[key] = in
	c.instOrder = append(c.instOrder, in)
	c.decide("a method value passed as an argument makes a copy of the callee that calls the method directly")
	return in.name
}
