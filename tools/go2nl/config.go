package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Config says what to convert and how. Every choice the converter cannot
// infer from the Go source (capacities, which functions are roots) lives here,
// so a run is reproducible from the config and the pinned upstream commit.
type Config struct {
	// Upstream records where the Go source came from; it is copied into reports.
	Upstream struct {
		Repo   string `json:"repo"`
		Commit string `json:"commit"`
	} `json:"upstream"`
	// Dir is the Go module directory to load from (relative to the config file).
	Dir string `json:"dir"`
	// Packages are go/packages patterns; their transitive dependencies inside the
	// same module are loaded from source too.
	Packages []string `json:"packages"`
	// Roots are the declarations reachability starts from: "pkgpath.Name",
	// "pkgpath.Type.Method", or "pkgpath.*" for every exported function and
	// method of the package.
	Roots []string `json:"roots"`
	// Capacities gives collection and string bounds. Keys are "default.slice",
	// "default.map", "default.string", or a symbol such as "pkg.Type.field".
	Capacities map[string]int64 `json:"capacities"`
	// Out is the output directory for the generated next-lang package (relative
	// to the config file).
	Out string `json:"out"`
}

func loadConfig(path string) (*Config, string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, "", err
	}
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, "", fmt.Errorf("%s: %w", path, err)
	}
	base := filepath.Dir(path)
	if c.Dir == "" {
		c.Dir = "."
	}
	c.Dir = resolve(base, c.Dir)
	c.Out = resolve(base, c.Out)
	return &c, base, nil
}

func (c *Config) capacity(key, fallbackKey string, fallback int64) int64 {
	if v, ok := c.Capacities[key]; ok {
		return v
	}
	if v, ok := c.Capacities[fallbackKey]; ok {
		return v
	}
	return fallback
}

// resolve expands $VARS and makes a path relative to the config file absolute.
func resolve(base, path string) string {
	path = os.ExpandEnv(path)
	if path == "" || filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(base, path)
}
