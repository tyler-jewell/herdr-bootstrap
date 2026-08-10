# herdr-code-gate-go

Herdr plugin: **strict Go** quality gate when a `go.mod` project is in play.

## Checks (fail on any)

1. **No suppressions** — `//nolint`, `//lint:ignore` in `.go`
2. **No local ignore configs** — `.golangci.y*ml` disable/skip/exclude, etc.
3. **`gofmt -l`** (clean)
4. **`go vet ./...`**
5. **`staticcheck ./...`** (required on PATH)
6. **`go build ./...`**

## Cheap vs force

- Auto **hook** (agent `done`/`idle`): only if `.go` count/size under limits.
- Manual: `check --force` always runs.

## Usage

```bash
cd plugins/herdr-code-gate-go
go build -o bin/herdr-code-gate-go ./cmd/herdr-code-gate-go
herdr plugin link "$PWD"

# staticcheck (once):
GOBIN=~/.local/bin go install honnef.co/go/tools/cmd/staticcheck@latest

herdr-code-gate-go check --current
herdr-code-gate-go check --current --fix
```

Herdr actions: **Go code gate (current space)**.
