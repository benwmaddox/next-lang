// go2nl converts typed Go source into next-lang, deterministically: the same
// config and the same Go source always give the same output. It converts only
// the declarations reachable from the configured roots, and it fails closed:
// a construct it has no rule for is reported with its location, never guessed.
//
//	go2nl census  -config cfg.json [-detail N]   report what the roots reach
//	go2nl convert -config cfg.json               write the next-lang package
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	cmd := os.Args[1]
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	cfgPath := fs.String("config", "go2nl.json", "config file")
	detail := fs.Int("detail", 20, "sites listed per census category (-1 for all)")
	out := fs.String("out", "", "output directory (overrides the config)")
	fs.Parse(os.Args[2:])

	cfg, _, err := loadConfig(*cfgPath)
	check(err)
	prog, err := load(cfg.Dir, cfg.Packages)
	check(err)
	roots, err := prog.resolveRoots(cfg.Roots)
	check(err)
	reach := prog.reach(roots)

	switch cmd {
	case "census":
		prog.census(reach).write(os.Stdout, prog, reach, cfg, *detail)
	case "convert":
		dir := *out
		if dir == "" {
			dir = cfg.Out
		}
		res := convert(prog, reach, cfg)
		check(res.writeTo(dir))
		fmt.Fprintf(os.Stderr, "go2nl: %d declarations converted, %d failed (%d problems); see %s\n",
			res.Converted, res.Failed, len(res.Problems), filepath.Join(dir, "go2nl-report.md"))
		if len(res.Problems) > 0 {
			os.Exit(1)
		}
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: go2nl census|convert -config cfg.json")
	os.Exit(2)
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "go2nl:", err)
		os.Exit(1)
	}
}
