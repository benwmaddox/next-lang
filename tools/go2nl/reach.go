package main

import (
	"fmt"
	"go/ast"
	"go/types"
	"sort"
	"strings"
)

// Reach is the set of declarations needed by the roots: a declaration is
// reachable when a root uses it, or when something reachable uses it. Only
// reachable declarations are converted, so converting the scanner does not mean
// converting all 21,000 lines of the ast package.
type Reach struct {
	Objs  map[types.Object]bool
	Order []types.Object // discovery order, made deterministic by sorting
	// Stdlib counts uses of standard-library functions, methods and variables.
	Stdlib map[string]int
}

func (p *Program) resolveRoots(roots []string) ([]types.Object, error) {
	var out []types.Object
	for _, r := range roots {
		pkgPath, rest := splitRoot(r)
		pkg := p.ByPath[pkgPath]
		if pkg == nil {
			pkg = p.ByPath[p.Module+"/"+pkgPath]
		}
		if pkg == nil {
			return nil, fmt.Errorf("root %q: package %q not loaded", r, pkgPath)
		}
		scope := pkg.Types.Scope()
		if rest == "*" {
			for _, name := range scope.Names() {
				obj := scope.Lookup(name)
				if !obj.Exported() {
					continue
				}
				switch obj := obj.(type) {
				case *types.Func:
					out = append(out, obj)
				case *types.TypeName:
					if named, ok := obj.Type().(*types.Named); ok {
						for i := 0; i < named.NumMethods(); i++ {
							if m := named.Method(i); m.Exported() {
								out = append(out, m)
							}
						}
					}
				}
			}
			continue
		}
		parts := strings.Split(rest, ".")
		obj := scope.Lookup(parts[0])
		if obj == nil {
			return nil, fmt.Errorf("root %q: %s not found", r, parts[0])
		}
		if len(parts) == 2 && parts[1] == "*" {
			named, ok := obj.Type().(*types.Named)
			if !ok {
				return nil, fmt.Errorf("root %q: %s is not a named type", r, parts[0])
			}
			for i := 0; i < named.NumMethods(); i++ {
				if m := named.Method(i); m.Exported() {
					out = append(out, m)
				}
			}
			continue
		}
		if len(parts) == 2 {
			named, ok := obj.Type().(*types.Named)
			if !ok {
				return nil, fmt.Errorf("root %q: %s is not a named type", r, parts[0])
			}
			var m types.Object
			for i := 0; i < named.NumMethods(); i++ {
				if named.Method(i).Name() == parts[1] {
					m = named.Method(i)
				}
			}
			if m == nil {
				return nil, fmt.Errorf("root %q: method not found", r)
			}
			obj = m
		}
		out = append(out, obj)
	}
	return out, nil
}

// splitRoot splits "a/b/pkg.Name.Method" at the first dot after the last slash.
func splitRoot(r string) (string, string) {
	slash := strings.LastIndex(r, "/")
	dot := strings.Index(r[slash+1:], ".")
	if dot < 0 {
		return r, ""
	}
	return r[:slash+1+dot], r[slash+2+dot:]
}

func (p *Program) reach(roots []types.Object) *Reach {
	r := &Reach{Objs: map[types.Object]bool{}, Stdlib: map[string]int{}}
	var work []types.Object
	add := func(obj types.Object) {
		if obj == nil || r.Objs[obj] {
			return
		}
		if f, ok := obj.(*types.Func); ok && f.Origin() != f {
			obj = f.Origin()
			if r.Objs[obj] {
				return
			}
		}
		r.Objs[obj] = true
		r.Order = append(r.Order, obj)
		work = append(work, obj)
	}
	for _, o := range roots {
		add(o)
	}
	var ifaces []*types.Interface
	seenIface := map[*types.Interface]bool{}
	for {
		for len(work) > 0 {
			obj := work[len(work)-1]
			work = work[:len(work)-1]
			decl := p.Decls[obj]
			if decl == nil {
				continue
			}
			// A method needs its receiver type.
			if f, ok := obj.(*types.Func); ok {
				if recv := f.Signature().Recv(); recv != nil {
					if n := namedOf(recv.Type()); n != nil {
						add(n.Obj())
					}
				}
			}
			ast.Inspect(decl, func(n ast.Node) bool {
				id, ok := n.(*ast.Ident)
				if !ok {
					return true
				}
				used := p.Info.Uses[id]
				if used == nil {
					return true
				}
				if p.inModule(used) {
					if isPackageLevel(used) || isMethod(used) {
						add(used)
					}
					if v, ok := used.(*types.Var); ok && v.IsField() {
						return true
					}
				} else if used.Pkg() != nil && (isPackageLevel(used) || isMethod(used)) {
					r.Stdlib[stdlibName(used)]++
				}
				if tn, ok := used.(*types.TypeName); ok {
					if it, ok := tn.Type().Underlying().(*types.Interface); ok && !seenIface[it] {
						seenIface[it] = true
						ifaces = append(ifaces, it)
					}
				}
				return true
			})
		}
		// Interface calls can reach any method that satisfies a reachable
		// interface, so add those methods of reachable types too.
		before := len(r.Order)
		for _, obj := range append([]types.Object(nil), r.Order...) {
			tn, ok := obj.(*types.TypeName)
			if !ok {
				continue
			}
			named, ok := tn.Type().(*types.Named)
			if !ok || types.IsInterface(named) {
				continue
			}
			for _, it := range ifaces {
				if it.NumMethods() == 0 {
					continue
				}
				if types.Implements(named, it) || types.Implements(types.NewPointer(named), it) {
					for i := 0; i < it.NumMethods(); i++ {
						m, _, _ := types.LookupFieldOrMethod(named, true, named.Obj().Pkg(), it.Method(i).Name())
						if m != nil {
							add(m)
						}
					}
				}
			}
		}
		if len(r.Order) == before && len(work) == 0 {
			break
		}
	}
	sort.SliceStable(r.Order, func(i, j int) bool {
		return p.Fset.Position(r.Order[i].Pos()).String() < p.Fset.Position(r.Order[j].Pos()).String()
	})
	return r
}

func namedOf(t types.Type) *types.Named {
	if ptr, ok := t.(*types.Pointer); ok {
		t = ptr.Elem()
	}
	n, _ := t.(*types.Named)
	return n
}

func isPackageLevel(obj types.Object) bool {
	return obj.Pkg() != nil && obj.Parent() == obj.Pkg().Scope()
}

func isMethod(obj types.Object) bool {
	f, ok := obj.(*types.Func)
	return ok && f.Signature().Recv() != nil
}

func stdlibName(obj types.Object) string {
	if f, ok := obj.(*types.Func); ok {
		if recv := f.Signature().Recv(); recv != nil {
			if n := namedOf(recv.Type()); n != nil {
				return obj.Pkg().Path() + "." + n.Obj().Name() + "." + obj.Name()
			}
		}
	}
	return obj.Pkg().Path() + "." + obj.Name()
}

// objName is the stable display name of a reachable object: pkg.Name or
// pkg.Type.Method.
func (p *Program) objName(obj types.Object) string {
	pkg := p.shortPkg(obj.Pkg().Path())
	if f, ok := obj.(*types.Func); ok {
		if recv := f.Signature().Recv(); recv != nil {
			if n := namedOf(recv.Type()); n != nil {
				return pkg + "." + n.Obj().Name() + "." + obj.Name()
			}
		}
	}
	return pkg + "." + obj.Name()
}
