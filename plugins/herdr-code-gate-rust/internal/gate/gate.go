package gate

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Cheap limits: skip auto-hook if project is huge.
const (
	MaxRSFilesCheap = 400
	MaxBytesCheap   = 8 << 20 // 8 MiB of .rs
	CmdTimeout      = 120 * time.Second
)

var (
	reAllowAttr  = regexp.MustCompile(`#\[allow\s*\(`)
	reAllowInner = regexp.MustCompile(`#!\[allow\s*\(`)
	reExpect     = regexp.MustCompile(`#\[expect\s*\(`)
)

type Result struct {
	Root     string
	OK       bool
	Skipped  bool
	Reason   string
	Findings []string
	Steps    []string
}

func IsRustProject(root string) bool {
	st, err := os.Stat(filepath.Join(root, "Cargo.toml"))
	return err == nil && !st.IsDir()
}

func CheapEnough(root string) (bool, string) {
	var n int
	var bytes int64
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == "target" || name == ".git" || name == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, ".rs") {
			n++
			if info, err := d.Info(); err == nil {
				bytes += info.Size()
			}
		}
		return nil
	})
	if n == 0 {
		return false, "no .rs files"
	}
	if n > MaxRSFilesCheap {
		return false, fmt.Sprintf("too many .rs files (%d > %d) for cheap gate", n, MaxRSFilesCheap)
	}
	if bytes > MaxBytesCheap {
		return false, fmt.Sprintf(".rs payload too large (%d bytes) for cheap gate", bytes)
	}
	return true, ""
}

func Run(root string, fix bool, force bool) Result {
	r := Result{Root: root}
	if !IsRustProject(root) {
		r.Skipped = true
		r.Reason = "not a Rust project (no Cargo.toml)"
		r.OK = true
		return r
	}
	if !force {
		ok, why := CheapEnough(root)
		if !ok {
			r.Skipped = true
			r.Reason = why
			r.OK = true // skip is not fail for hooks
			return r
		}
	}

	// 1) Forbid local suppressions / overrides
	r.Findings = append(r.Findings, scanSuppressions(root)...)
	r.Findings = append(r.Findings, scanConfigOverrides(root)...)

	// 2) Format
	if fix {
		r.Steps = append(r.Steps, "cargo fmt --all")
		if out, err := runCmd(root, CmdTimeout, "cargo", "fmt", "--all"); err != nil {
			r.Findings = append(r.Findings, "cargo fmt failed:\n"+trimOut(out))
		}
	}
	r.Steps = append(r.Steps, "cargo fmt --all -- --check")
	if out, err := runCmd(root, CmdTimeout, "cargo", "fmt", "--all", "--", "--check"); err != nil {
		r.Findings = append(r.Findings, "format not clean (cargo fmt --check):\n"+trimOut(out))
	}

	// 3) Clippy: deny all warnings, no cap-lints allow
	r.Steps = append(r.Steps, "cargo clippy --all-targets -- -D warnings")
	if out, err := runCmd(root, CmdTimeout, "cargo", "clippy", "--all-targets", "--",
		"-D", "warnings",
		"-D", "clippy::all",
		"-D", "clippy::pedantic",
	); err != nil {
		// pedantic can be very noisy; if pedantic fails but user wants world-class, keep it.
		// Fallback message
		r.Findings = append(r.Findings, "clippy failed (zero-warning policy):\n"+trimOut(out))
	}

	// 4) Check / build (no run tests by default — not always cheap)
	r.Steps = append(r.Steps, "cargo check --all-targets")
	if out, err := runCmd(root, CmdTimeout, "cargo", "check", "--all-targets"); err != nil {
		r.Findings = append(r.Findings, "cargo check failed:\n"+trimOut(out))
	}

	r.OK = len(r.Findings) == 0
	if !r.OK {
		r.Reason = fmt.Sprintf("%d finding(s)", len(r.Findings))
	} else {
		r.Reason = "pass"
	}
	return r
}

func scanSuppressions(root string) []string {
	var findings []string
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == "target" || name == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".rs") {
			return nil
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		// Strip line/block comments that are only docs? We want to catch real attributes.
		// Match attribute forms outside strings roughly by line.
		rel, _ := filepath.Rel(root, path)
		for _, line := range strings.Split(string(b), "\n") {
			t := strings.TrimSpace(line)
			// skip pure string lines / raw strings for messages
			if strings.HasPrefix(t, "\"") || strings.HasPrefix(t, "`") || strings.HasPrefix(t, "//") {
				continue
			}
			if reAllowAttr.MatchString(t) || reAllowInner.MatchString(t) {
				findings = append(findings, "forbidden #[allow]/#![allow] attribute in "+rel)
				break
			}
			if reExpect.MatchString(t) {
				findings = append(findings, "forbidden #[expect(...)] attribute in "+rel)
				break
			}
		}
		return nil
	})
	return findings
}

func scanConfigOverrides(root string) []string {
	var findings []string
	for _, rel := range []string{
		".cargo/config.toml",
		".cargo/config",
		"clippy.toml",
		".clippy.toml",
	} {
		p := filepath.Join(root, rel)
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		low := strings.ToLower(string(b))
		if strings.Contains(low, "cap-lints") && strings.Contains(low, "allow") {
			findings = append(findings, "forbidden cap-lints=allow style override in "+rel)
		}
		if strings.Contains(low, "allow(warnings)") || strings.Contains(low, "allow(dead_code)") {
			findings = append(findings, "forbidden lint allow in "+rel)
		}
		if (rel == "clippy.toml" || rel == ".clippy.toml") &&
			(strings.Contains(low, "= allow") || strings.Contains(low, "=\"allow\"") || strings.Contains(low, "allow =")) {
			findings = append(findings, "forbidden clippy.toml allow overrides in "+rel)
		}
	}
	return findings
}

func runCmd(dir string, timeout time.Duration, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(),
		// force deny warnings at rustc level when possible
		"RUSTFLAGS=-Dwarnings",
	)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Start()
	if err != nil {
		return buf.String(), err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return buf.String(), err
	case <-time.After(timeout):
		_ = cmd.Process.Kill()
		return buf.String() + "\n(timeout)", fmt.Errorf("timeout after %s", timeout)
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
	fmt.Fprintf(&b, "[%s] rust-gate %s — %s\n", status, r.Root, r.Reason)
	for _, s := range r.Steps {
		fmt.Fprintf(&b, "  step: %s\n", s)
	}
	for _, f := range r.Findings {
		fmt.Fprintf(&b, "  - %s\n", f)
	}
	return b.String()
}
