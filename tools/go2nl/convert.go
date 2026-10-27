package main

type Result struct {
	Converted, Failed int
	Problems          []string
}

func convert(p *Program, r *Reach, cfg *Config) *Result { return &Result{} }

func (r *Result) writeTo(dir string) error { return nil }
