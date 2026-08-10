package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/herdr-bootstrap/herdr-code-gate-go/internal/gate"
	"github.com/herdr-bootstrap/herdr-code-gate-go/internal/proj"
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
	fmt.Fprintf(os.Stderr, `herdr-code-gate-go — strict Go format/lint/check

Usage:
  herdr-code-gate-go check [--current] [--fix] [--force]
  herdr-code-gate-go hook agent-status

Policy: gofmt -l, go vet, staticcheck, go build;
no //nolint, no //lint:ignore, no golangci disable/skip configs.
Cheap auto-hook skips large trees; --force always runs.
`)
}

func cmdCheck(args []string) int {
	fix := false
	force := false
	for _, a := range args {
		switch a {
		case "--fix":
			fix = true
		case "--force":
			force = true
		}
	}
	cwd, _ := os.Getwd()
	if _, ok := proj.GoModRoot(cwd); !ok {
		cwd = proj.ContextCwd()
	}
	root, ok := proj.GoModRoot(cwd)
	if !ok {
		fmt.Println("[SKIP] no go.mod above", cwd)
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
	root, ok := proj.GoModRoot(cwd)
	if !ok {
		return 0
	}
	r := gate.Run(root, false, false)
	if r.Skipped {
		return 0
	}
	if !r.OK {
		body := r.Reason + ": " + firstFinding(r)
		proj.Notify("Go code gate FAIL", short(root)+" — "+body)
		fmt.Print(gate.Format(r))
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
	if i := strings.LastIndex(root, "/"); i >= 0 {
		return root[i+1:]
	}
	return root
}
