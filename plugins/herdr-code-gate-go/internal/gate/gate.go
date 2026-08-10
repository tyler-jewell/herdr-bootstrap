package gate

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	MaxGoFilesCheap = 500
	MaxBytesCheap   = 10 << 20
	CmdTimeout      = 120 * time.Second
)

type Result struct {
	Root     string
	OK       bool
	Skipped  bool
	Reason   string
	Findings []string
	Steps    []string
}

func IsGoProject(root string) bool {
	st, err := os.Stat(filepath.Join(root, "go.mod"))
	return err == nil && !st.IsDir()
}

func CheapEnough(root string) (bool, string) {
	var n int
	var total int64
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == "vendor" || name == ".git" || name == "node_modules" || name == "bin" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, ".go") {
			n++
			if info, err := d.Info(); err == nil {
				total += info.Size()
			}
		}
		return nil
	})
	if n == 0 {
		return false, "no .go files"
	}
	if n > MaxGoFilesCheap {
		return false, fmt.Sprintf("too many .go files (%d > %d) for cheap gate", n, MaxGoFilesCheap)
	}
	if total > MaxBytesCheap {
		return false, fmt.Sprintf(".go payload too large (%d bytes) for cheap gate", total)
	}
	return true, ""
}

func Run(root string, fix bool, force bool) Result {
	r := Result{Root: root}
	if !IsGoProject(root) {
		r.Skipped = true
		r.Reason = "not a Go project (no go.mod)"
		r.OK = true
		return r
	}
	if !force {
		ok, why := CheapEnough(root)
		if !ok {
			r.Skipped = true
			r.Reason = why
			r.OK = true
			return r
		}
	}

	r.Findings = append(r.Findings, scanSuppressions(root)...)
	r.Findings = append(r.Findings, scanConfigOverrides(root)...)

	goFiles := listGoFiles(root)
	if fix {
		r.Steps = append(r.Steps, "gofmt -w")
		for _, f := range goFiles {
			_, _ = runCmd(root, CmdTimeout, "gofmt", "-w", f)
		}
	}

	r.Steps = append(r.Steps, "gofmt -l")
	if len(goFiles) > 0 {
		args := append([]string{"-l"}, goFiles...)
		out, err := runCmd(root, CmdTimeout, "gofmt", args...)
		if err != nil || strings.TrimSpace(out) != "" {
			if strings.TrimSpace(out) == "" && err != nil {
				r.Findings = append(r.Findings, "gofmt -l failed:\n"+trimOut(out+err.Error()))
			} else if strings.TrimSpace(out) != "" {
				r.Findings = append(r.Findings, "format not clean (gofmt -l):\n"+trimOut(out))
			}
		}
	}

	r.Steps = append(r.Steps, "go vet ./...")
	if out, err := runCmd(root, CmdTimeout, "go", "vet", "./..."); err != nil {
		r.Findings = append(r.Findings, "go vet failed:\n"+trimOut(out))
	}

	// staticcheck if available (stricter); required for world-class when present
	if _, err := exec.LookPath("staticcheck"); err == nil {
		r.Steps = append(r.Steps, "staticcheck ./...")
		if out, err := runCmd(root, CmdTimeout, "staticcheck", "./..."); err != nil {
			r.Findings = append(r.Findings, "staticcheck failed:\n"+trimOut(out))
		}
	} else {
		r.Steps = append(r.Steps, "staticcheck (missing — install for full gate)")
		r.Findings = append(r.Findings, "staticcheck not on PATH (required for Go code gate;: go install honnef.co/go/tools/cmd/staticcheck@latest)")
	}

	r.Steps = append(r.Steps, "go build ./...")
	if out, err := runCmd(root, CmdTimeout, "go", "build", "./..."); err != nil {
		r.Findings = append(r.Findings, "go build ./... failed:\n"+trimOut(out))
	}

	r.OK = len(r.Findings) == 0
	if !r.OK {
		r.Reason = fmt.Sprintf("%d finding(s)", len(r.Findings))
	} else {
		r.Reason = "pass"
	}
	return r
}

func listGoFiles(root string) []string {
	var files []string
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == "vendor" || name == ".git" || name == "node_modules" || name == "bin" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, ".go") {
			rel, err := filepath.Rel(root, path)
			if err == nil {
				files = append(files, rel)
			} else {
				files = append(files, path)
			}
		}
		return nil
	})
	return files
}

func scanSuppressions(root string) []string {
	var findings []string
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == "vendor" || name == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		inRaw := false
		for _, line := range strings.Split(string(b), "\n") {
			code, nextRaw := stripGoLineStrings(line, inRaw)
			inRaw = nextRaw
			if i := strings.Index(code, "//"); i >= 0 {
				rest := strings.TrimSpace(code[i+2:])
				if strings.HasPrefix(rest, "nolint") {
					findings = append(findings, "forbidden //nolint comment in "+rel)
					break
				}
				if strings.HasPrefix(rest, "lint:ignore") {
					findings = append(findings, "forbidden //lint:ignore comment in "+rel)
					break
				}
			}
		}
		return nil
	})
	return findings
}

// stripGoLineStrings removes "..." `...` and '...' so // inside strings is ignored.
// inRaw tracks multi-line raw strings across lines.
func stripGoLineStrings(line string, inRaw bool) (string, bool) {
	var b strings.Builder
	inD, inS := false, false
	for i := 0; i < len(line); i++ {
		c := line[i]
		if inRaw {
			if c == '`' {
				inRaw = false
			}
			b.WriteByte(' ')
			continue
		}
		if inD {
			if c == '\\' && i+1 < len(line) {
				i++
				b.WriteByte(' ')
				b.WriteByte(' ')
				continue
			}
			if c == '"' {
				inD = false
			}
			b.WriteByte(' ')
			continue
		}
		if inS {
			if c == '\\' && i+1 < len(line) {
				i++
				b.WriteByte(' ')
				b.WriteByte(' ')
				continue
			}
			if c == '\'' {
				inS = false
			}
			b.WriteByte(' ')
			continue
		}
		switch c {
		case '`':
			inRaw = true
			b.WriteByte(' ')
		case '"':
			inD = true
			b.WriteByte(' ')
		case '\'':
			inS = true
			b.WriteByte(' ')
		default:
			b.WriteByte(c)
		}
	}
	return b.String(), inRaw
}

func scanConfigOverrides(root string) []string {
	var findings []string
	for _, rel := range []string{
		".golangci.yml",
		".golangci.yaml",
		"golangci.yml",
		"golangci.yaml",
		"staticcheck.conf",
	} {
		p := filepath.Join(root, rel)
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		low := strings.ToLower(string(b))
		// any disable / skip of linters is a local override — hard fail
		if strings.Contains(low, "disable:") || strings.Contains(low, "disable-all") ||
			strings.Contains(low, "skip-dirs") || strings.Contains(low, "skip-files") ||
			strings.Contains(low, "exclude-rules") || strings.Contains(low, "nolint:") {
			findings = append(findings, "forbidden local linter override/disable in "+rel+" (remove; world-class = no local ignore config)")
		}
	}
	return findings
}

func runCmd(dir string, timeout time.Duration, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Start(); err != nil {
		return buf.String(), err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return buf.String(), err
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		return buf.String() + "\n(timeout)", fmt.Errorf("timeout")
	}
}

func trimOut(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 4000 {
		return s[:4000] + "\n…(truncated)"
	}
	return s
}

func Format(r Result) string {
	var b strings.Builder
	status := "PASS"
	if r.Skipped {
		status = "SKIP"
	} else if !r.OK {
		status = "FAIL"
	}
	fmt.Fprintf(&b, "[%s] go-gate %s — %s\n", status, r.Root, r.Reason)
	for _, s := range r.Steps {
		fmt.Fprintf(&b, "  step: %s\n", s)
	}
	for _, f := range r.Findings {
		fmt.Fprintf(&b, "  - %s\n", f)
	}
	return b.String()
}
