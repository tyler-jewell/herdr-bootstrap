package gate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIsGoProject(t *testing.T) {
	dir := t.TempDir()
	if IsGoProject(dir) {
		t.Fatal("empty dir should not be go project")
	}
	if err := os.WriteFile(filepath.Join(dir, "go.mod"), []byte("module example\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !IsGoProject(dir) {
		t.Fatal("dir with go.mod should be go project")
	}
}

func TestScanNolintRealCommentFails(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "bad.go")
	// real end-of-line suppression comment
	body := "package p\n\nfunc f() error { return nil } //nolint:errcheck\n"
	if err := os.WriteFile(src, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	findings := scanSuppressions(dir)
	if len(findings) == 0 {
		t.Fatal("expected //nolint finding")
	}
	if !strings.Contains(findings[0], "nolint") {
		t.Fatalf("unexpected finding: %v", findings)
	}
}

func TestScanNolintInStringDoesNotFail(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "ok.go")
	body := "package p\n\nconst msg = \"do not use //nolint casually\"\n"
	if err := os.WriteFile(src, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	findings := scanSuppressions(dir)
	if len(findings) != 0 {
		t.Fatalf("string mention should not count: %v", findings)
	}
}

func TestRunForceOnSelfModulePasses(t *testing.T) {
	// Drive the shipped Run entry against this module's real tree.
	// Resolve module root from this test file location.
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	// test runs with cwd = package dir internal/gate → module root is ../..
	root := filepath.Clean(filepath.Join(wd, "..", ".."))
	if !IsGoProject(root) {
		t.Fatalf("expected go.mod at %s", root)
	}
	r := Run(root, false, true)
	if r.Skipped {
		t.Fatalf("unexpected skip: %s", r.Reason)
	}
	if !r.OK {
		t.Fatalf("gate failed on self module: %s\n%v", r.Reason, r.Findings)
	}
}
