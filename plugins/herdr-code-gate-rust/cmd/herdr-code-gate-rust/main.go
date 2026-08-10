package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/herdr-bootstrap/herdr-code-gate-rust/internal/gate"
	"github.com/herdr-bootstrap/herdr-code-gate-rust/internal/proj"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "check":
		os.Exit(cmdCheck(os.Args[2:]))
	case "hook":
		if len(os.Args) < 3 {
			os.Exit(0)
		}
		os.Exit(cmdHook(os.Args[2]))
	case "help", "-h", "--help":
		usage()
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `herdr-code-gate-rust — strict Rust format/lint/check

Usage:
  herdr-code-gate-rust check [--current] [--fix] [--force]
  herdr-code-gate-rust hook agent-status

Policy: cargo fmt --check, clippy -D warnings (+ pedantic), cargo check,
no #[allow]/#! [allow]/#[expect], no cap-lints allow in .cargo/config.
Cheap auto-hook skips large trees; --force always runs.
`)
}

func cmdCheck(args []string) int {
	current := true
	fix := false
	force := false
	for _, a := range args {
		switch a {
		case "--current":
			current = true
		case "--fix":
			fix = true
		case "--force":
			force = true
		}
	}
	_ = current
	// Prefer process cwd for CLI; Herdr context only when no local cargo/go.mod
	cwd, _ := os.Getwd()
	if _, ok := proj.CargoRoot(cwd); !ok {
		cwd = proj.ContextCwd()
	}
	root, ok := proj.CargoRoot(cwd)
	if !ok {
		fmt.Println("[SKIP] no Cargo.toml above", cwd)
		return 0
	}
	r := gate.Run(root, fix, force)
	fmt.Print(gate.Format(r))
	if r.Skipped {
		return 0
	}
	if !r.OK {
		return 1
	}
	return 0
}

func cmdHook(name string) int {
	// never crash Herdr
	defer func() { _ = recover() }()
	if name != "agent-status" {
		return 0
	}
	st := proj.ParseAgentStatus("")
	if st != "done" && st != "idle" {
		return 0
	}
	cwd := proj.ParseEventCwd("")
	if cwd == "" {
		cwd = proj.ContextCwd()
	}
	root, ok := proj.CargoRoot(cwd)
	if !ok {
		return 0
	}
	r := gate.Run(root, false, false)
	if r.Skipped {
		return 0
	}
	if !r.OK {
		body := r.Reason + ": " + firstFinding(r)
		proj.Notify("Rust code gate FAIL", short(root)+" — "+body)
		fmt.Print(gate.Format(r))
		return 0 // hooks stay 0 so Herdr is fine
	}
	return 0
}

func firstFinding(r gate.Result) string {
	if len(r.Findings) == 0 {
		return r.Reason
	}
	line := r.Findings[0]
	if i := strings.Index(line, "\n"); i > 0 {
		return line[:i]
	}
	if len(line) > 120 {
		return line[:120]
	}
	return line
}

func short(root string) string {
	return filepathBase(root)
}

func filepathBase(p string) string {
	if i := strings.LastIndex(p, "/"); i >= 0 {
		return p[i+1:]
	}
	return p
}
