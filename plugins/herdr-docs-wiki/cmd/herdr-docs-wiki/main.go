package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/herdr-bootstrap/herdr-docs-wiki/internal/discover"
	"github.com/herdr-bootstrap/herdr-docs-wiki/internal/doctor"
	"github.com/herdr-bootstrap/herdr-docs-wiki/internal/herdrcli"
	"github.com/herdr-bootstrap/herdr-docs-wiki/internal/policy"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	cmd := os.Args[1]
	args := os.Args[2:]

	polPath := policy.ResolvePath()
	pol, err := policy.Load(polPath)
	if err != nil {
		// still run with defaults
		pol = policy.Default()
		fmt.Fprintf(os.Stderr, "!!  policy load: %v (using defaults)\n", err)
	}

	switch cmd {
	case "startup":
		os.Exit(cmdStartup(pol, polPath))
	case "doctor":
		os.Exit(cmdDoctor(pol, args))
	case "fix":
		os.Exit(cmdFix(pol, args))
	case "nudge":
		os.Exit(cmdNudge(pol, args))
	case "hook":
		if len(args) < 1 {
			fmt.Fprintln(os.Stderr, "hook requires name")
			os.Exit(2)
		}
		os.Exit(cmdHook(pol, args[0]))
	case "help", "-h", "--help":
		usage()
		os.Exit(0)
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", cmd)
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `herdr-docs-wiki — doctor & hooks for docs/* LLM wikis

Usage:
  herdr-docs-wiki startup
  herdr-docs-wiki doctor [--current] [--json] [--strict] [--root PATH]
  herdr-docs-wiki fix --current --apply-policy
  herdr-docs-wiki nudge --current
  herdr-docs-wiki hook agent-status|workspace-focused
`)
}

func cmdStartup(pol policy.Policy, polPath string) int {
	fmt.Printf("docs-wiki startup policy_version=%d path=%s\n", pol.PolicyVersion, polPath)
	// warm discover cache optional
	root := os.Getenv("HERDR_DISCOVER_ROOT")
	if root == "" {
		home, _ := os.UserHomeDir()
		root = home
	}
	projects, err := discover.Find(root, 6)
	if err != nil {
		fmt.Fprintf(os.Stderr, "!!  discover: %v\n", err)
		return 0 // never fail startup hard
	}
	if state := os.Getenv("HERDR_PLUGIN_STATE_DIR"); state != "" {
		_ = os.MkdirAll(state, 0o755)
		// write simple list
		var lines []string
		for _, p := range projects {
			lines = append(lines, p.Root)
		}
		_ = os.WriteFile(filepath.Join(state, "projects.txt"), []byte(strings.Join(lines, "\n")+"\n"), 0o644)
	}
	fmt.Printf("discovered %d .herdr project(s)\n", len(projects))
	return 0
}

func cmdDoctor(pol policy.Policy, args []string) int {
	current := false
	asJSON := false
	strict := false
	rootScan := os.Getenv("HERDR_DISCOVER_ROOT")
	if rootScan == "" {
		home, _ := os.UserHomeDir()
		rootScan = home
	}
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--current":
			current = true
		case "--json":
			asJSON = true
		case "--strict":
			strict = true
		case "--root":
			if i+1 < len(args) {
				i++
				rootScan = args[i]
			}
		}
	}

	var results []doctor.Result
	if current {
		proj, ok := resolveCurrentProject()
		if !ok {
			fmt.Fprintln(os.Stderr, "XX  could not resolve current project (.herdr)")
			return 1
		}
		results = append(results, doctor.Check(proj, pol))
	} else {
		projects, err := discover.Find(rootScan, 6)
		if err != nil {
			fmt.Fprintf(os.Stderr, "XX  discover: %v\n", err)
			return 1
		}
		for _, p := range projects {
			results = append(results, doctor.Check(p.Root, pol))
		}
	}

	if asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(results)
	} else {
		if len(results) == 0 {
			fmt.Println("No .herdr projects found")
		}
		fails := 0
		for _, r := range results {
			fmt.Print(doctor.FormatHuman(r))
			if r.Grade == "F" || (strict && doctor.OverLineLimit(r.Root, pol)) {
				fails++
			}
			if strict {
				for _, f := range r.Findings {
					if strings.Contains(f, "page >") {
						fails++
						break
					}
				}
			}
		}
		fmt.Printf("\n%d project(s)\n", len(results))
		if strict && fails > 0 {
			return 1
		}
	}
	if strict {
		for _, r := range results {
			if r.Grade == "F" {
				return 1
			}
			if doctor.OverLineLimit(r.Root, pol) {
				return 1
			}
		}
	}
	return 0
}

func cmdFix(pol policy.Policy, args []string) int {
	current := false
	apply := false
	for _, a := range args {
		if a == "--current" {
			current = true
		}
		if a == "--apply-policy" {
			apply = true
		}
	}
	if !current || !apply {
		fmt.Fprintln(os.Stderr, "usage: fix --current --apply-policy")
		return 2
	}
	proj, ok := resolveCurrentProject()
	if !ok {
		fmt.Fprintln(os.Stderr, "XX  could not resolve current project")
		return 1
	}
	// bootstrap root for templates
	hint := ""
	if pr := os.Getenv("HERDR_PLUGIN_ROOT"); pr != "" {
		hint, _ = filepath.Abs(filepath.Join(pr, "..", ".."))
	}
	block, err := doctor.ReadAgentsTemplate(hint)
	if err != nil {
		fmt.Fprintf(os.Stderr, "!!  template: %v\n", err)
	}
	if err := doctor.ApplyPolicy(proj, pol, block); err != nil {
		fmt.Fprintf(os.Stderr, "XX  fix: %v\n", err)
		return 1
	}
	fmt.Println("applied policy to", proj)
	r := doctor.Check(proj, pol)
	fmt.Print(doctor.FormatHuman(r))
	return 0
}

func cmdNudge(pol policy.Policy, args []string) int {
	current := false
	for _, a := range args {
		if a == "--current" {
			current = true
		}
	}
	if !current {
		fmt.Fprintln(os.Stderr, "usage: nudge --current")
		return 2
	}
	proj, ok := resolveCurrentProject()
	if !ok {
		fmt.Fprintln(os.Stderr, "XX  could not resolve current project")
		return 1
	}
	if !doctor.IsStale(proj, pol) && !doctor.OverLineLimit(proj, pol) {
		fmt.Println("wiki looks fresh enough:", proj)
		return 0
	}
	title := "docs wiki needs update"
	body := filepath.Base(proj) + ": update docs/ (index + log) before treating work as done"
	if err := herdrcli.Notify(title, body); err != nil {
		fmt.Fprintf(os.Stderr, "!!  notify: %v\n", err)
		fmt.Println(title+":", body)
	} else {
		fmt.Println("notified:", body)
	}
	return 0
}

func cmdHook(pol policy.Policy, name string) int {
	// always exit 0 — hooks must not break Herdr
	defer func() { _ = recover() }()

	switch name {
	case "agent-status":
		raw := os.Getenv("HERDR_PLUGIN_EVENT_JSON")
		status, cwd := doctor.ParseEventJSON(raw)
		status = strings.ToLower(status)
		if status != "done" && status != "idle" {
			return 0
		}
		if cwd == "" {
			cwd = herdrcli.ContextPaneCwd()
		}
		if cwd == "" {
			return 0
		}
		root, ok := discover.ProjectRootFromCwd(cwd)
		if !ok {
			return 0
		}
		if doctor.IsStale(root, pol) || doctor.OverLineLimit(root, pol) {
			_ = herdrcli.Notify(
				"Update docs wiki",
				filepath.Base(root)+": agent settled; docs/ looks stale or over line limit",
			)
		}
	case "workspace-focused":
		// cheap: resolve cwd for focused workspace, soft notify on F grade only
		wid := herdrcli.ContextWorkspaceID()
		cwd := herdrcli.ContextPaneCwd()
		if cwd == "" {
			var err error
			cwd, err = herdrcli.SnapshotCwdForWorkspace(wid)
			if err != nil || cwd == "" {
				return 0
			}
		}
		root, ok := discover.ProjectRootFromCwd(cwd)
		if !ok {
			return 0
		}
		r := doctor.Check(root, pol)
		if r.Grade == "F" || r.PolicyHave != r.PolicyWant {
			_ = herdrcli.Notify(
				"docs wiki doctor",
				fmt.Sprintf("%s grade=%s pin=%d want=%d", r.Name, r.Grade, r.PolicyHave, r.PolicyWant),
			)
		}
	}
	return 0
}

func resolveCurrentProject() (string, bool) {
	// 1. cwd from context
	if cwd := herdrcli.ContextPaneCwd(); cwd != "" {
		if root, ok := discover.ProjectRootFromCwd(cwd); ok {
			return root, true
		}
	}
	// 2. snapshot focused pane
	if cwd, err := herdrcli.SnapshotCwdForWorkspace(herdrcli.ContextWorkspaceID()); err == nil && cwd != "" {
		if root, ok := discover.ProjectRootFromCwd(cwd); ok {
			return root, true
		}
	}
	// 3. process cwd
	wd, err := os.Getwd()
	if err == nil {
		if root, ok := discover.ProjectRootFromCwd(wd); ok {
			return root, true
		}
	}
	return "", false
}
