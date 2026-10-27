package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// runCorpus is the oracle test: every program under dir/<name>/ is a Go main
// package. It runs under `go run`, is converted, and runs under `nlc run`; the
// two must print the same output, and either both succeed or both fail.
func runCorpus(dir, nlc, outRoot, only string) int {
	entries, err := os.ReadDir(dir)
	check(err)
	var names []string
	for _, e := range entries {
		if e.IsDir() && (only == "" || strings.Contains(e.Name(), only)) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	failed := 0
	for _, name := range names {
		status, detail := corpusOne(dir, name, nlc, filepath.Join(outRoot, name))
		if status != "pass" {
			failed++
		}
		fmt.Printf("%-28s %s\n", name, status)
		if detail != "" {
			for _, l := range strings.Split(strings.TrimRight(detail, "\n"), "\n") {
				fmt.Printf("    %s\n", l)
			}
		}
	}
	fmt.Printf("\n%d of %d corpus programs match Go\n", len(names)-failed, len(names))
	if failed > 0 {
		return 1
	}
	return 0
}

func run(dir string, timeout time.Duration, name string, args ...string) (string, string, int) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	var out, errb bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errb
	err := cmd.Run()
	code := 0
	if err != nil {
		code = -1
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		}
	}
	return out.String(), errb.String(), code
}

func corpusOne(dir, name, nlc, out string) (string, string) {
	goOut, goErr, goCode := run(dir, 2*time.Minute, "go", "run", "./"+name)
	if goCode == -1 {
		return "go-error", goErr
	}
	prog, err := load(dir, []string{"./" + name})
	if err != nil {
		return "load-error", err.Error()
	}
	cfg := &Config{}
	cfgPath := filepath.Join(dir, name, "go2nl.json")
	if _, err := os.Stat(cfgPath); err == nil {
		c, _, err := loadConfig(cfgPath)
		if err != nil {
			return "config-error", err.Error()
		}
		cfg = c
	}
	pkgPath := prog.Pkgs[len(prog.Pkgs)-1].Path
	cfg.Roots = []string{pkgPath + ".main"}
	roots, err := prog.resolveRoots(cfg.Roots)
	if err != nil {
		return "root-error", err.Error()
	}
	res := convert(prog, prog.reach(roots), cfg)
	if err := res.writeTo(out); err != nil {
		return "write-error", err.Error()
	}
	if len(res.Problems) > 0 {
		var b strings.Builder
		for _, p := range res.Problems {
			fmt.Fprintf(&b, "%s %s: %s: %s\n", p.Pos, p.Symbol, p.Category, p.Message)
		}
		return "not-converted", b.String()
	}
	nlOut, nlErr, nlCode := run(out, 5*time.Minute, nlc, "run", ".")
	if nlCode == 2 && strings.Contains(nlErr, "error:") {
		return "nlc-rejects", firstLines(nlErr, 6)
	}
	if nlOut != goOut {
		return "output-differs", diffHint(goOut, nlOut) + firstLines(nlErr, 3)
	}
	if (goCode == 0) != (nlCode == 0) {
		return "status-differs", fmt.Sprintf("go exit %d, next-lang exit %d\n%s", goCode, nlCode, firstLines(nlErr, 3))
	}
	return "pass", ""
}

func firstLines(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > n {
		lines = append(lines[:n], "...")
	}
	return strings.Join(lines, "\n") + "\n"
}

func diffHint(want, got string) string {
	wl := strings.Split(want, "\n")
	gl := strings.Split(got, "\n")
	for i := 0; i < len(wl) || i < len(gl); i++ {
		var w, g string
		if i < len(wl) {
			w = wl[i]
		}
		if i < len(gl) {
			g = gl[i]
		}
		if w != g {
			return fmt.Sprintf("line %d: go %q, next-lang %q\n", i+1, w, g)
		}
	}
	return ""
}
