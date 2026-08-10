package policy

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Policy is the machine-level llm-wiki policy (subset TOML).
type Policy struct {
	PolicyVersion      int
	WikiRoot           string
	MaxPageLines       int
	RequireIndex       bool
	RequireLog         bool
	RequireFrontmatter bool
	ForbidOverlap      bool
	RequiredSkill      string
	// weights
	WHerdrConfig int
	WPolicyPin   int
	WIndex       int
	WLog         int
	WAgentsMD    int
	WPageLines   int
	WFrontmatter int
	WOverlap     int
	WStatus      int
	WFreshness   int
}

func Default() Policy {
	return Policy{
		PolicyVersion:      1,
		WikiRoot:           "docs",
		MaxPageLines:       280,
		RequireIndex:       true,
		RequireLog:         true,
		RequireFrontmatter: true,
		ForbidOverlap:      true,
		RequiredSkill:      "docs-wiki",
		WHerdrConfig:       10,
		WPolicyPin:         10,
		WIndex:             15,
		WLog:               10,
		WAgentsMD:          15,
		WPageLines:         15,
		WFrontmatter:       10,
		WOverlap:           5,
		WStatus:            5,
		WFreshness:         5,
	}
}

// ResolvePath finds policy/llm-wiki.toml near plugin root or bootstrap repo.
func ResolvePath() string {
	if p := os.Getenv("HERDR_WIKI_POLICY"); p != "" {
		return p
	}
	// Plugin root: .../plugins/herdr-docs-wiki
	if root := os.Getenv("HERDR_PLUGIN_ROOT"); root != "" {
		cand := filepath.Join(root, "..", "..", "policy", "llm-wiki.toml")
		if st, err := os.Stat(cand); err == nil && !st.IsDir() {
			return cand
		}
	}
	// Walk up from executable / cwd
	start, _ := os.Getwd()
	for dir := start; dir != "/" && dir != "."; dir = filepath.Dir(dir) {
		cand := filepath.Join(dir, "policy", "llm-wiki.toml")
		if st, err := os.Stat(cand); err == nil && !st.IsDir() {
			return cand
		}
		// plugins/herdr-docs-wiki -> repo root
		cand = filepath.Join(dir, "..", "..", "policy", "llm-wiki.toml")
		if st, err := os.Stat(cand); err == nil && !st.IsDir() {
			abs, _ := filepath.Abs(cand)
			return abs
		}
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "herdr-bootstrap", "llm-wiki.toml")
}

// Load reads a minimal TOML subset into Policy.
func Load(path string) (Policy, error) {
	p := Default()
	b, err := os.ReadFile(path)
	if err != nil {
		return p, fmt.Errorf("read policy %s: %w", path, err)
	}
	sc := bufio.NewScanner(strings.NewReader(string(b)))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if i := strings.Index(line, " #"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key := strings.TrimSpace(k)
		val := strings.TrimSpace(v)
		val = strings.Trim(val, `"'`)
		switch key {
		case "policy_version":
			p.PolicyVersion, _ = strconv.Atoi(val)
		case "wiki_root":
			p.WikiRoot = val
		case "max_page_lines":
			p.MaxPageLines, _ = strconv.Atoi(val)
		case "require_index":
			p.RequireIndex = val == "true"
		case "require_log":
			p.RequireLog = val == "true"
		case "require_frontmatter":
			p.RequireFrontmatter = val == "true"
		case "forbid_overlap":
			p.ForbidOverlap = val == "true"
		case "required_skill":
			p.RequiredSkill = val
		case "weight_herdr_config":
			p.WHerdrConfig, _ = strconv.Atoi(val)
		case "weight_policy_pin":
			p.WPolicyPin, _ = strconv.Atoi(val)
		case "weight_index":
			p.WIndex, _ = strconv.Atoi(val)
		case "weight_log":
			p.WLog, _ = strconv.Atoi(val)
		case "weight_agents_md":
			p.WAgentsMD, _ = strconv.Atoi(val)
		case "weight_page_lines":
			p.WPageLines, _ = strconv.Atoi(val)
		case "weight_frontmatter":
			p.WFrontmatter, _ = strconv.Atoi(val)
		case "weight_overlap":
			p.WOverlap, _ = strconv.Atoi(val)
		case "weight_status":
			p.WStatus, _ = strconv.Atoi(val)
		case "weight_freshness":
			p.WFreshness, _ = strconv.Atoi(val)
		}
	}
	if p.MaxPageLines <= 0 {
		p.MaxPageLines = 280
	}
	if p.WikiRoot == "" {
		p.WikiRoot = "docs"
	}
	return p, nil
}
