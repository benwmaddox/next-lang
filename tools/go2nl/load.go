package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/importer"
	"go/parser"
	"go/token"
	"go/types"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
)

// Program is every Go package loaded from source, type-checked, with an index
// from package-level objects to their declarations.
type Program struct {
	Fset     *token.FileSet
	Pkgs     []*Package // dependency order: a package comes after its imports
	ByPath   map[string]*Package
	Info     *types.Info // shared by all source packages
	Decls    map[types.Object]ast.Node
	DeclFile map[types.Object]*ast.File
	Module   string
}

type Package struct {
	Path  string
	Name  string
	Dir   string
	Files []*ast.File
	Types *types.Package
}

type listedPackage struct {
	ImportPath string
	Name       string
	Dir        string
	GoFiles    []string
	Standard   bool
	Module     *struct{ Path string }
}

// load runs `go list -deps` and type-checks every package of the main module
// from source. Standard-library packages are type-checked from GOROOT source by
// the "source" importer, so no export data or extra tooling is needed.
func load(dir string, patterns []string) (*Program, error) {
	args := append([]string{"list", "-json", "-deps"}, patterns...)
	cmd := exec.Command("go", args...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("go list: %v\n%s", err, stderr.String())
	}
	dec := json.NewDecoder(bytes.NewReader(out))
	var listed []listedPackage
	for {
		var lp listedPackage
		if err := dec.Decode(&lp); err == io.EOF {
			break
		} else if err != nil {
			return nil, err
		}
		listed = append(listed, lp)
	}
	module := ""
	for _, lp := range listed {
		if lp.Module != nil && !lp.Standard {
			module = lp.Module.Path
		}
	}

	p := &Program{
		Fset:   token.NewFileSet(),
		ByPath: map[string]*Package{},
		Info: &types.Info{
			Types:      map[ast.Expr]types.TypeAndValue{},
			Defs:       map[*ast.Ident]types.Object{},
			Uses:       map[*ast.Ident]types.Object{},
			Implicits:  map[ast.Node]types.Object{},
			Selections: map[*ast.SelectorExpr]*types.Selection{},
			Scopes:     map[ast.Node]*types.Scope{},
			Instances:  map[*ast.Ident]types.Instance{},
		},
		Decls:    map[types.Object]ast.Node{},
		DeclFile: map[types.Object]*ast.File{},
		Module:   module,
	}
	std := importer.ForCompiler(p.Fset, "source", nil).(types.ImporterFrom)
	var imp types.Importer
	_ = importerFunc(func(path string) (*types.Package, error) {
		if pkg, ok := p.ByPath[path]; ok {
			return pkg.Types, nil
		}
		return std.ImportFrom(path, dir, 0)
	})
	ext := map[string]*types.Package{}
	imp = importerFunc(func(path string) (*types.Package, error) {
		if pkg, ok := p.ByPath[path]; ok {
			return pkg.Types, nil
		}
		if pkg, ok := ext[path]; ok {
			return pkg, nil
		}
		return std.ImportFrom(path, dir, 0)
	})
	for _, lp := range listed {
		if lp.Standard || lp.Module == nil {
			continue
		}
		if lp.Module.Path != module {
			// Third-party: type-check from source so the main module can import
			// it, but never convert it.
			var files []*ast.File
			for _, f := range lp.GoFiles {
				file, err := parser.ParseFile(p.Fset, filepath.Join(lp.Dir, f), nil, parser.SkipObjectResolution)
				if err != nil {
					return nil, err
				}
				files = append(files, file)
			}
			conf := types.Config{Importer: imp}
			tp, err := conf.Check(lp.ImportPath, p.Fset, files, nil)
			if err != nil {
				return nil, fmt.Errorf("type-check %s: %v", lp.ImportPath, err)
			}
			ext[lp.ImportPath] = tp
			continue
		}
		pkg := &Package{Path: lp.ImportPath, Name: lp.Name, Dir: lp.Dir}
		for _, f := range lp.GoFiles {
			file, err := parser.ParseFile(p.Fset, filepath.Join(lp.Dir, f), nil, parser.ParseComments|parser.SkipObjectResolution)
			if err != nil {
				return nil, err
			}
			pkg.Files = append(pkg.Files, file)
		}
		conf := types.Config{Importer: imp}
		tp, err := conf.Check(lp.ImportPath, p.Fset, pkg.Files, p.Info)
		if err != nil {
			return nil, fmt.Errorf("type-check %s: %v", lp.ImportPath, err)
		}
		pkg.Types = tp
		p.Pkgs = append(p.Pkgs, pkg)
		p.ByPath[lp.ImportPath] = pkg
		p.index(pkg)
	}
	return p, nil
}

type importerFunc func(string) (*types.Package, error)

func (f importerFunc) Import(path string) (*types.Package, error) { return f(path) }

// index records the declaration of every package-level object and method.
func (p *Program) index(pkg *Package) {
	for _, file := range pkg.Files {
		for _, d := range file.Decls {
			switch d := d.(type) {
			case *ast.FuncDecl:
				if obj := p.Info.Defs[d.Name]; obj != nil {
					p.Decls[obj] = d
					p.DeclFile[obj] = file
				}
			case *ast.GenDecl:
				for _, s := range d.Specs {
					switch s := s.(type) {
					case *ast.TypeSpec:
						if obj := p.Info.Defs[s.Name]; obj != nil {
							p.Decls[obj] = s
							p.DeclFile[obj] = file
						}
					case *ast.ValueSpec:
						for _, n := range s.Names {
							if obj := p.Info.Defs[n]; obj != nil {
								p.Decls[obj] = s
								p.DeclFile[obj] = file
							}
						}
					}
				}
			}
		}
	}
}

// inModule reports whether obj belongs to a package loaded from source.
func (p *Program) inModule(obj types.Object) bool {
	return obj != nil && obj.Pkg() != nil && p.ByPath[obj.Pkg().Path()] != nil
}

// shortPkg turns "github.com/x/y/internal/scanner" into "scanner".
func (p *Program) shortPkg(path string) string {
	if pkg := p.ByPath[path]; pkg != nil {
		return pkg.Name
	}
	return path[strings.LastIndex(path, "/")+1:]
}

func (p *Program) pos(n ast.Node) string {
	pos := p.Fset.Position(n.Pos())
	rel := pos.Filename
	if pkg := p.pkgOfFile(pos.Filename); pkg != nil {
		rel = strings.TrimPrefix(pkg.Path, p.Module+"/") + "/" + filepath.Base(pos.Filename)
	}
	return fmt.Sprintf("%s:%d", rel, pos.Line)
}

func (p *Program) pkgOfFile(name string) *Package {
	dir := filepath.Dir(name)
	for _, pkg := range p.Pkgs {
		if pkg.Dir == dir {
			return pkg
		}
	}
	return nil
}
