package proj

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func HerdrBin() string {
	if p := os.Getenv("HERDR_BIN_PATH"); p != "" {
		return p
	}
	return "herdr"
}

func Notify(title, body string) {
	_ = exec.Command(HerdrBin(), "notification", "show", title, "--body", body).Run()
}

func GoModRoot(start string) (string, bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", false
	}
	for {
		if fileExists(filepath.Join(dir, "go.mod")) {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

func ContextCwd() string {
	raw := os.Getenv("HERDR_PLUGIN_CONTEXT_JSON")
	if raw != "" {
		var m map[string]any
		if json.Unmarshal([]byte(raw), &m) == nil {
			for _, k := range []string{"cwd", "pane_cwd", "focused_pane_cwd"} {
				if v, ok := m[k].(string); ok && v != "" {
					return v
				}
			}
			if pane, ok := m["pane"].(map[string]any); ok {
				if v, ok := pane["cwd"].(string); ok && v != "" {
					return v
				}
			}
		}
	}
	out, err := exec.Command(HerdrBin(), "api", "snapshot").Output()
	if err == nil {
		var wrap struct {
			Result struct {
				Snapshot struct {
					Panes []struct {
						Cwd     string `json:"cwd"`
						Focused bool   `json:"focused"`
					} `json:"panes"`
				} `json:"snapshot"`
			} `json:"result"`
		}
		if json.Unmarshal(out, &wrap) == nil {
			for _, p := range wrap.Result.Snapshot.Panes {
				if p.Focused && p.Cwd != "" {
					return p.Cwd
				}
			}
			for _, p := range wrap.Result.Snapshot.Panes {
				if p.Cwd != "" {
					return p.Cwd
				}
			}
		}
	}
	wd, _ := os.Getwd()
	return wd
}

func ParseAgentStatus(eventJSON string) string {
	raw := eventJSON
	if raw == "" {
		raw = os.Getenv("HERDR_PLUGIN_EVENT_JSON")
	}
	for _, key := range []string{`"agent_status"`, `"status"`} {
		if i := strings.Index(raw, key); i >= 0 {
			rest := raw[i+len(key):]
			if j := strings.Index(rest, `"`); j >= 0 {
				rest = rest[j+1:]
				if k := strings.Index(rest, `"`); k >= 0 {
					return strings.ToLower(rest[:k])
				}
			}
		}
	}
	return ""
}

func ParseEventCwd(eventJSON string) string {
	raw := eventJSON
	if raw == "" {
		raw = os.Getenv("HERDR_PLUGIN_EVENT_JSON")
	}
	for _, key := range []string{`"cwd"`, `"foreground_cwd"`} {
		if i := strings.Index(raw, key); i >= 0 {
			rest := raw[i+len(key):]
			if j := strings.Index(rest, `"`); j >= 0 {
				rest = rest[j+1:]
				if k := strings.Index(rest, `"`); k >= 0 {
					return rest[:k]
				}
			}
		}
	}
	return ""
}
