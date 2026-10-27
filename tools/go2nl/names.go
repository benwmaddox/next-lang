package main

import (
	"fmt"
	"go/types"
	"strings"
	"unicode"
)

// Words next-lang gives a meaning to. A Go identifier that collides with one
// gets a trailing "_go". The list is deliberately generous: escaping a name that
// didn't need it costs nothing, missing one breaks the build.
var reserved = map[string]bool{}

func init() {
	for _, w := range strings.Fields(`fn let var const type struct enum match if else for in return
		break continue true false none some ok err take write grow read discard expect test check
		global shared recursive pub max print fill list pool map set queue ring grid Option Result
		Full Id Text Ascii Bytes int long byte short i8 bool never default effects reads writes out
		env fs str abs min max len count unbounded wrap clamp transaction parallel spawn job freeze
		scope task api page action piece fit to_long main self Self impl interface trait use import
		module mod mut ref loop while do switch case go defer chan select bytes b`) {
		reserved[w] = true
	}
}

// namer hands out names, unique within one scope, deterministically: the
// first claimant of a name keeps it, later ones get _2, _3, ...
type namer struct {
	used map[string]bool
}

func newNamer(parent *namer) *namer {
	n := &namer{used: map[string]bool{}}
	if parent != nil {
		for k := range parent.used {
			n.used[k] = true
		}
	}
	return n
}

func (n *namer) claim(base string) string {
	if reserved[base] {
		base += "_go"
	}
	name := base
	for i := 2; n.used[name]; i++ {
		name = fmt.Sprintf("%s_%d", base, i)
	}
	n.used[name] = true
	return name
}

func upperFirst(s string) string {
	if s == "" {
		return s
	}
	r := []rune(s)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

func lowerFirst(s string) string {
	if s == "" {
		return s
	}
	r := []rune(s)
	r[0] = unicode.ToLower(r[0])
	return string(r)
}

// localName makes a Go local, parameter or field name safe as a next-lang value
// name: lowercase first letter (capitalised names start struct literals and
// patterns in next-lang) and no reserved word.
func localBase(goName string) string {
	if goName == "" || goName == "_" {
		return "unused"
	}
	if unicode.IsUpper([]rune(goName)[0]) {
		return "v" + goName
	}
	return goName
}

// fieldName keeps Go's field name where it can, for traceability.
func fieldName(goName string) string {
	if reserved[goName] {
		return goName + "_go"
	}
	return goName
}

// Top-level names: values (functions, constants, package variables) get a
// lowercase package prefix, types a capitalised one, so names from different
// Go packages never meet in the one next-lang package.
func (c *conv) valueName(obj types.Object) string {
	if name, ok := c.topNames[obj]; ok {
		return name
	}
	pkg := c.p.shortPkg(obj.Pkg().Path())
	var base string
	if obj.Name() == "main" && pkg == "main" && !isMethod(obj) {
		c.top.used["main"] = true
		c.topNames[obj] = "main"
		return "main"
	} else if f, ok := obj.(*types.Func); ok && f.Signature().Recv() != nil {
		recv := namedOf(f.Signature().Recv().Type())
		base = pkg + "_" + recv.Obj().Name() + "_" + obj.Name()
	} else {
		base = pkg + "_" + obj.Name()
	}
	name := c.top.claim(base)
	c.topNames[obj] = name
	return name
}

func (c *conv) typeName(obj *types.TypeName) string {
	if name, ok := c.topNames[obj]; ok {
		return name
	}
	pkg := c.p.shortPkg(obj.Pkg().Path())
	name := c.top.claim(upperFirst(pkg) + "_" + obj.Name())
	c.topNames[obj] = name
	return name
}
