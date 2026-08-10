package doctor

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unicode"

	"github.com/herdr-bootstrap/herdr-docs-wiki/internal/policy"
	"github.com/herdr-bootstrap/herdr-docs-wiki/internal/projectcfg"
)

var fmTitle = regexp.MustCompile(`(?m)^title:\s*(.+)$`)

// Result is a scored project.
type Result struct {
	Root       string   `json:"root"`
	Name       string   `json:"name"`
	Score      int      `json:"score"`
	Grade      string   `json:"grade"`
	Findings   []string `json:"findings"`
	PolicyWant int      `json:"policy_want"`
	PolicyHave int      `json:"policy_have"`
	WikiOn     bool     `json:"wiki_enabled"`
}

// Check scores one project root.
func Check(root string, pol policy.Policy) Result {
	r := Result{Root: root, PolicyWant: pol.PolicyVersion, WikiOn: true}
	var score int
	findings := []string{}

	cfgPath := filepath.Join(root, ".herdr", "config.toml")
	cfg, err := projectcfg.Load(cfgPath)
	if err != nil {
		findings = append(findings, "missing or unreadable .herdr/config.toml")
	} else {
		score += pol.WHerdrConfig
		r.Name = cfg.Name
		r.WikiOn = cfg.WikiEnabled
		r.PolicyHave = cfg.WikiPolicyVer
		if !cfg.HasWikiSection {
			findings = append(findings, "no [wiki] section in .herdr/config.toml")
		}
		if cfg.WikiPolicyVer == pol.PolicyVersion {
			score += pol.WPolicyPin
		} else {
			findings = append(findings, fmt.Sprintf("policy pin %d != machine %d", cfg.WikiPolicyVer, pol.PolicyVersion))
		}
	}
	if r.Name == "" {
		r.Name = filepath.Base(root)
	}

	if !r.WikiOn {
		// wiki disabled: full score on wiki-only criteria as N/A -> half credit? treat as skip wiki checks with note
		findings = append(findings, "wiki.enabled=false — structural wiki checks skipped")
		r.Score = score
		r.Grade = grade(score)
		r.Findings = findings
		return r
	}

	docs := filepath.Join(root, pol.WikiRoot)
	indexPath := filepath.Join(docs, "index.md")
	logPath := filepath.Join(docs, "log.md")

	if pol.RequireIndex {
		if st, err := os.Stat(indexPath); err == nil && !st.IsDir() {
			score += pol.WIndex
		} else {
			findings = append(findings, "missing docs/index.md")
		}
	}
	if pol.RequireLog {
		if st, err := os.Stat(logPath); err == nil && !st.IsDir() {
			score += pol.WLog
		} else {
			findings = append(findings, "missing docs/log.md")
		}
	}

	agentsPath := filepath.Join(root, "AGENTS.md")
	if b, err := os.ReadFile(agentsPath); err == nil {
		if strings.Contains(string(b), "<!-- docs-wiki:start -->") && strings.Contains(string(b), "<!-- docs-wiki:end -->") {
			score += pol.WAgentsMD
		} else {
			findings = append(findings, "AGENTS.md missing docs-wiki marker block")
		}
	} else {
		findings = append(findings, "missing AGENTS.md")
	}

	pages, overLimit, missingFM, titles := walkDocs(docs, pol.MaxPageLines)
	if len(pages) == 0 && dirExists(docs) {
		findings = append(findings, "docs/ has no markdown pages")
	}
	if len(overLimit) == 0 {
		score += pol.WPageLines
	} else {
		for _, p := range overLimit {
			findings = append(findings, fmt.Sprintf("page >%d lines: %s", pol.MaxPageLines, p))
		}
	}
	if !pol.RequireFrontmatter || len(missingFM) == 0 {
		score += pol.WFrontmatter
	} else {
		// partial credit if few missing
		if len(missingFM) <= 1 {
			score += pol.WFrontmatter / 2
		}
		for _, p := range missingFM {
			findings = append(findings, "missing frontmatter: "+p)
		}
	}

	if !pol.ForbidOverlap || !hasTitleDupes(titles) {
		score += pol.WOverlap
	} else {
		findings = append(findings, "possible overlapping page titles (duplicate titles)")
	}

	statusDir := filepath.Join(docs, "status")
	if dirExists(statusDir) {
		score += pol.WStatus
	} else {
		findings = append(findings, "optional: docs/status/ missing")
		// still award partial for optional - actually plan gave weight_status=5 for status presence
	}

	// Freshness soft: docs log or any docs mtime vs non-docs in last 7d — award if log exists and recently touched or no code newer
	if freshnessOK(root, docs) {
		score += pol.WFreshness
	} else {
		findings = append(findings, "docs may be stale vs project files (soft)")
	}

	if score > 100 {
		score = 100
	}
	r.Score = score
	r.Grade = grade(score)
	r.Findings = findings
	return r
}

func grade(score int) string {
	switch {
	case score >= 90:
		return "A"
	case score >= 75:
		return "B"
	case score >= 60:
		return "C"
	default:
		return "F"
	}
}

func dirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func walkDocs(docs string, maxLines int) (pages, over, missingFM, titles []string) {
	_ = filepath.WalkDir(docs, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(strings.ToLower(d.Name()), ".md") {
			return nil
		}
		rel, _ := filepath.Rel(docs, path)
		pages = append(pages, rel)
		// line count
		b, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		n := countLines(string(b))
		if n > maxLines {
			over = append(over, fmt.Sprintf("%s (%d)", rel, n))
		}
		base := filepath.Base(path)
		// allowlist: freeform ops/human docs without full FM
		if base != "log.md" && base != "README.md" && base != "HERDR_RULES.md" {
			if !hasFrontmatter(string(b)) {
				missingFM = append(missingFM, rel)
			} else if m := fmTitle.FindStringSubmatch(string(b)); len(m) > 1 {
				titles = append(titles, normalizeTitle(m[1]))
			}
		}
		return nil
	})
	return
}

func countLines(s string) int {
	if s == "" {
		return 0
	}
	n := strings.Count(s, "\n")
	if !strings.HasSuffix(s, "\n") {
		n++
	}
	return n
}

func hasFrontmatter(s string) bool {
	s = strings.TrimPrefix(s, "\uFEFF")
	if !strings.HasPrefix(s, "---\n") && !strings.HasPrefix(s, "---\r\n") {
		return false
	}
	rest := s[3:]
	if i := strings.Index(rest, "\n---"); i >= 0 {
		return true
	}
	return false
}

func normalizeTitle(t string) string {
	t = strings.TrimSpace(t)
	t = strings.Trim(t, `"'`)
	var b strings.Builder
	for _, r := range strings.ToLower(t) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func hasTitleDupes(titles []string) bool {
	seen := map[string]int{}
	for _, t := range titles {
		if t == "" {
			continue
		}
		seen[t]++
		if seen[t] > 1 {
			return true
		}
	}
	return false
}

func freshnessOK(root, docs string) bool {
	var newestDocs time.Time
	_ = filepath.WalkDir(docs, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if st, err := d.Info(); err == nil {
			if st.ModTime().After(newestDocs) {
				newestDocs = st.ModTime()
			}
		}
		return nil
	})
	if newestDocs.IsZero() {
		return false
	}
	// if any non-docs, non-.git file under root is newer by >1m and within last 14d of "code" activity without docs update — soft fail
	var newestOther time.Time
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			if name == ".git" || name == "node_modules" || name == "docs" || name == ".herdr" {
				return filepath.SkipDir
			}
			return nil
		}
		// skip binary-ish large dirs already pruned
		if st, err := d.Info(); err == nil {
			if st.ModTime().After(newestOther) {
				newestOther = st.ModTime()
			}
		}
		return nil
	})
	if newestOther.IsZero() {
		return true
	}
	// docs updated within 24h of newest other, or docs newer
	if !newestDocs.Before(newestOther.Add(-24 * time.Hour)) {
		return true
	}
	return false
}

// IsStale is used by hooks for a cheap check.
func IsStale(root string, pol policy.Policy) bool {
	docs := filepath.Join(root, pol.WikiRoot)
	if !dirExists(docs) {
		return true
	}
	return !freshnessOK(root, docs)
}

// OverLineLimit returns true if any page exceeds max.
func OverLineLimit(root string, pol policy.Policy) bool {
	docs := filepath.Join(root, pol.WikiRoot)
	_, over, _, _ := walkDocs(docs, pol.MaxPageLines)
	return len(over) > 0
}

// ReadAgentsTemplate loads templates/agents-docs-wiki.md from bootstrap.
func ReadAgentsTemplate(bootstrapHint string) (string, error) {
	cands := []string{
		filepath.Join(bootstrapHint, "templates", "agents-docs-wiki.md"),
		filepath.Join(os.Getenv("HERDR_PLUGIN_ROOT"), "..", "..", "templates", "agents-docs-wiki.md"),
	}
	if wd, err := os.Getwd(); err == nil {
		cands = append(cands, filepath.Join(wd, "templates", "agents-docs-wiki.md"))
		cands = append(cands, filepath.Join(wd, "..", "..", "templates", "agents-docs-wiki.md"))
	}
	for _, c := range cands {
		abs, _ := filepath.Abs(c)
		b, err := os.ReadFile(abs)
		if err == nil {
			return string(b), nil
		}
	}
	return defaultAgentsBlock(), nil
}

func defaultAgentsBlock() string {
	return "<!-- docs-wiki:start -->\n## Project wiki (`docs/`)\n\nUse skill **docs-wiki** / `/docs-wiki`. Keep pages ≤280 lines.\n<!-- docs-wiki:end -->\n"
}

// ApplyPolicy scaffolds docs + pin + AGENTS block.
func ApplyPolicy(root string, pol policy.Policy, agentsBlock string) error {
	docs := filepath.Join(root, pol.WikiRoot)
	if err := os.MkdirAll(filepath.Join(docs, "status"), 0o755); err != nil {
		return err
	}
	index := filepath.Join(docs, "index.md")
	if _, err := os.Stat(index); os.IsNotExist(err) {
		name := filepath.Base(root)
		body := fmt.Sprintf("---\ntitle: Wiki index\nupdated: %s\ntags: [index]\nsummary: Master index\n---\n\n# Wiki index\n\n| Page | Summary |\n|------|---------|\n| [status/current](status/current.md) | Live status |\n", time.Now().Format("2006-01-02"))
		if err := os.WriteFile(index, []byte(body), 0o644); err != nil {
			return err
		}
		_ = name
	}
	logPath := filepath.Join(docs, "log.md")
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		body := "# Wiki log\n\nYYYY-MM-DD | title | change\n\n"
		if err := os.WriteFile(logPath, []byte(body), 0o644); err != nil {
			return err
		}
	}
	status := filepath.Join(docs, "status", "current.md")
	if _, err := os.Stat(status); os.IsNotExist(err) {
		body := fmt.Sprintf("---\ntitle: Current status\nupdated: %s\ntags: [status]\nsummary: Live project status\n---\n\n# Current status\n\n_Fill in as work proceeds._\n", time.Now().Format("2006-01-02"))
		if err := os.WriteFile(status, []byte(body), 0o644); err != nil {
			return err
		}
	}

	// Update .herdr/config.toml [wiki]
	cfgPath := filepath.Join(root, ".herdr", "config.toml")
	if err := upsertWikiSection(cfgPath, pol.PolicyVersion); err != nil {
		return err
	}

	// AGENTS.md marker replace/append
	agentsPath := filepath.Join(root, "AGENTS.md")
	return upsertAgentsBlock(agentsPath, agentsBlock)
}

func upsertWikiSection(cfgPath string, ver int) error {
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		return err
	}
	text := string(b)
	section := fmt.Sprintf("\n[wiki]\nenabled = true\npolicy_version = %d\n", ver)
	if strings.Contains(text, "[wiki]") {
		// rewrite wiki section simply: remove old [wiki] until next [ or EOF
		lines := strings.Split(text, "\n")
		var out []string
		inWiki := false
		for _, line := range lines {
			trim := strings.TrimSpace(line)
			if trim == "[wiki]" {
				inWiki = true
				continue
			}
			if inWiki {
				if strings.HasPrefix(trim, "[") && trim != "[wiki]" {
					inWiki = false
					out = append(out, line)
				}
				continue
			}
			out = append(out, line)
		}
		text = strings.TrimRight(strings.Join(out, "\n"), "\n") + "\n" + section
	} else {
		text = strings.TrimRight(text, "\n") + "\n" + section
	}
	return os.WriteFile(cfgPath, []byte(text), 0o644)
}

func upsertAgentsBlock(path, block string) error {
	block = strings.TrimSpace(block) + "\n"
	var text string
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return os.WriteFile(path, []byte(block), 0o644)
		}
		return err
	}
	text = string(b)
	start := "<!-- docs-wiki:start -->"
	end := "<!-- docs-wiki:end -->"
	si := strings.Index(text, start)
	ei := strings.Index(text, end)
	if si >= 0 && ei > si {
		// replace including end marker line
		endIdx := ei + len(end)
		// consume trailing newline
		if endIdx < len(text) && text[endIdx] == '\n' {
			endIdx++
		}
		text = text[:si] + block + text[endIdx:]
	} else {
		if !strings.HasSuffix(text, "\n") {
			text += "\n"
		}
		text += "\n" + block
	}
	return os.WriteFile(path, []byte(text), 0o644)
}

// FormatHuman prints a result.
func FormatHuman(r Result) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s  %s  score=%d grade=%s  %s\n", r.Grade, r.Name, r.Score, r.Grade, r.Root)
	for _, f := range r.Findings {
		fmt.Fprintf(&b, "  - %s\n", f)
	}
	return b.String()
}

// ParseEventJSON extracts agent_status and cwd-ish fields loosely.
func ParseEventJSON(raw string) (status string, cwd string) {
	// avoid heavy JSON deps: string hunt
	// "agent_status":"done" or "status":"done"
	for _, key := range []string{`"agent_status"`, `"status"`} {
		if i := strings.Index(raw, key); i >= 0 {
			rest := raw[i+len(key):]
			if j := strings.Index(rest, `"`); j >= 0 {
				rest = rest[j+1:]
				if k := strings.Index(rest, `"`); k >= 0 {
					status = rest[:k]
					break
				}
			}
		}
	}
	for _, key := range []string{`"cwd"`, `"foreground_cwd"`, `"path"`} {
		if i := strings.Index(raw, key); i >= 0 {
			rest := raw[i+len(key):]
			if j := strings.Index(rest, `"`); j >= 0 {
				rest = rest[j+1:]
				if k := strings.Index(rest, `"`); k >= 0 {
					cwd = rest[:k]
					break
				}
			}
		}
	}
	return status, cwd
}

// FirstLine is a tiny helper for scanners.
func FirstLine(s string) string {
	sc := bufio.NewScanner(strings.NewReader(s))
	if sc.Scan() {
		return sc.Text()
	}
	return s
}
