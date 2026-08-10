package discover

import (
	"os"
	"path/filepath"
	"strings"
)

var prune = map[string]struct{}{
	"Library": {}, "Movies": {}, "Music": {}, "Pictures": {}, "Public": {},
	"Applications": {}, ".Trash": {}, "node_modules": {}, ".git": {},
	"target": {}, "dist": {}, "build": {}, ".cache": {}, ".npm": {},
	".cargo": {}, ".rustup": {}, ".nvm": {}, ".pyenv": {}, ".local": {},
	".config": {}, ".orbstack": {}, ".docker": {}, ".vscode": {},
	".cursor": {}, ".codex": {}, ".claude": {}, ".grok": {},
	"venv": {}, ".venv": {}, "__pycache__": {}, "DerivedData": {}, "Pods": {},
}

// Project is a repo root with .herdr/config.toml.
type Project struct {
	Root       string
	ConfigPath string
}

// Find walks root for .herdr/config.toml up to maxDepth.
func Find(root string, maxDepth int) ([]Project, error) {
	root, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	var out []Project
	seen := map[string]struct{}{}

	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil // skip unreadable
		}
		if !d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		if rel != "." {
			depth := strings.Count(rel, string(os.PathSeparator)) + 1
			if depth > maxDepth {
				return filepath.SkipDir
			}
		}
		name := d.Name()
		if name != "." && name != ".." {
			if _, bad := prune[name]; bad {
				return filepath.SkipDir
			}
			if strings.HasPrefix(name, ".") && name != ".herdr" {
				return filepath.SkipDir
			}
		}
		if name == ".herdr" {
			cfg := filepath.Join(path, "config.toml")
			if st, err := os.Stat(cfg); err == nil && !st.IsDir() {
				projRoot := filepath.Dir(path)
				if _, ok := seen[projRoot]; !ok {
					seen[projRoot] = struct{}{}
					out = append(out, Project{Root: projRoot, ConfigPath: cfg})
				}
			}
			return filepath.SkipDir
		}
		return nil
	})
	return out, err
}

// ProjectRootFromCwd walks up looking for .herdr/config.toml.
func ProjectRootFromCwd(start string) (string, bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", false
	}
	for {
		cfg := filepath.Join(dir, ".herdr", "config.toml")
		if st, err := os.Stat(cfg); err == nil && !st.IsDir() {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}
