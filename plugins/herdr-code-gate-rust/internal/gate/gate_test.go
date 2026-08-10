package gate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIsRustProject(t *testing.T) {
	dir := t.TempDir()
	if IsRustProject(dir) {
		t.Fatal("empty dir should not be rust project")
	}
	if err := os.WriteFile(filepath.Join(dir, "Cargo.toml"), []byte("[package]\nname=\"x\"\nversion=\"0.1.0\"\nedition=\"2021\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !IsRustProject(dir) {
		t.Fatal("dir with Cargo.toml should be rust project")
	}
}

func TestRunNoCargoSkips(t *testing.T) {
	dir := t.TempDir()
	r := Run(dir, false, true)
	if !r.Skipped {
		t.Fatalf("expected skip without Cargo.toml, got OK=%v reason=%s findings=%v", r.OK, r.Reason, r.Findings)
	}
	if !r.OK {
		t.Fatal("skip should still set OK=true for hook-friendly semantics")
	}
	if !strings.Contains(strings.ToLower(r.Reason), "cargo") && !strings.Contains(strings.ToLower(r.Reason), "rust") {
		t.Fatalf("skip reason should mention cargo/rust: %q", r.Reason)
	}
}

func TestScanAllowAttribute(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "lib.rs")
	body := "#[allow(dead_code)]\nfn x() {}\n"
	if err := os.WriteFile(src, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	findings := scanSuppressions(dir)
	if len(findings) == 0 {
		t.Fatal("expected #[allow] finding")
	}
}
