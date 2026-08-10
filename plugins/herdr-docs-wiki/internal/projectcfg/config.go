package projectcfg

import (
	"bufio"
	"os"
	"strconv"
	"strings"
)

// Config is a minimal parse of .herdr/config.toml.
type Config struct {
	Name           string
	Enabled        bool
	WikiEnabled    bool
	WikiPolicyVer  int
	HasWikiSection bool
}

func Load(path string) (Config, error) {
	c := Config{Enabled: true, WikiEnabled: true, WikiPolicyVer: 0}
	b, err := os.ReadFile(path)
	if err != nil {
		return c, err
	}
	section := "root"
	sc := bufio.NewScanner(strings.NewReader(string(b)))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			sec := strings.TrimSpace(line[1 : len(line)-1])
			section = sec
			if sec == "wiki" {
				c.HasWikiSection = true
			}
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key := strings.TrimSpace(k)
		val := strings.Trim(strings.TrimSpace(v), `"'`)
		if i := strings.Index(val, " #"); i >= 0 {
			val = strings.TrimSpace(val[:i])
		}
		switch section {
		case "root":
			switch key {
			case "name":
				c.Name = val
			case "enabled":
				c.Enabled = val == "true"
			}
		case "wiki":
			switch key {
			case "enabled":
				c.WikiEnabled = val == "true"
			case "policy_version":
				c.WikiPolicyVer, _ = strconv.Atoi(val)
			}
		}
	}
	return c, nil
}
