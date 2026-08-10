package herdrcli

import (
	"encoding/json"
	"os"
	"os/exec"
	"strings"
)

func Bin() string {
	if p := os.Getenv("HERDR_BIN_PATH"); p != "" {
		return p
	}
	return "herdr"
}

// Notify shows a herdr notification (best-effort).
func Notify(title, body string) error {
	args := []string{"notification", "show", title}
	if body != "" {
		args = append(args, "--body", body)
	}
	cmd := exec.Command(Bin(), args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

// SnapshotCwdForWorkspace returns a pane cwd for workspace id if possible.
func SnapshotCwdForWorkspace(workspaceID string) (string, error) {
	cmd := exec.Command(Bin(), "api", "snapshot")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	var wrap struct {
		Result struct {
			Snapshot struct {
				Panes []struct {
					WorkspaceID string `json:"workspace_id"`
					Cwd         string `json:"cwd"`
					Focused     bool   `json:"focused"`
				} `json:"panes"`
			} `json:"snapshot"`
		} `json:"result"`
	}
	if err := json.Unmarshal(out, &wrap); err != nil {
		return "", err
	}
	var fallback string
	for _, p := range wrap.Result.Snapshot.Panes {
		if workspaceID != "" && p.WorkspaceID != workspaceID {
			continue
		}
		if p.Cwd == "" {
			continue
		}
		if p.Focused {
			return p.Cwd, nil
		}
		if fallback == "" {
			fallback = p.Cwd
		}
	}
	// if no workspace filter match, any focused
	if workspaceID == "" {
		for _, p := range wrap.Result.Snapshot.Panes {
			if p.Focused && p.Cwd != "" {
				return p.Cwd, nil
			}
		}
	}
	return fallback, nil
}

// ContextWorkspaceID from env.
func ContextWorkspaceID() string {
	return strings.TrimSpace(os.Getenv("HERDR_WORKSPACE_ID"))
}

// ContextPaneCwd: try HERDR_PLUGIN_CONTEXT_JSON then env.
func ContextPaneCwd() string {
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
				if v, ok := pane["cwd"].(string); ok {
					return v
				}
			}
		}
	}
	return ""
}
