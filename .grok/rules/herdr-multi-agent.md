# Herdr multi-agent messaging (machine-wide)

Applies whenever more than one coding agent runs under Herdr (`HERDR_ENV=1`), including supervisor + crew panes.

## Facts (do not invent product features)

- Herdr has **no** native agent “inbox” API that auto-wakes peers.
- Peer push is: `herdr agent prompt <name|pane_id> "<text>"` (see https://herdr.dev/docs/agent-automation/).
- Repo files (`docs/inbox/`, threads, tickets) are **durable notes only** — peers read them only if a turn opens them.
- `agent.prompt` while a Grok (or other) agent is **working** usually **queues** (`#1`, `#2`, …). It does not interrupt. Stale queue + API **Retrying** freezes progress on newer messages.

## MUST

- Before `herdr agent prompt`: `herdr agent list` (or `agent get <target>`). Prefer targets in **`idle` / `done`**.
- If target is **`working`**: write durable notes first; prompt **once** with a short “process notes” wake, or wait for idle — **do not** flood.
- If UI shows **Retrying (n/15)** or multi-minute **Waiting for response**: stop adding prompts; optional `herdr agent send-keys <target> esc` only when human intent is cancel (skill: herdr).
- When coordinating crews: one mission prompt per settle; reference file paths; tell agents to ignore older rates/build thrash unless regression.
- Use unique live agent **names** (`[a-z][a-z0-9_-]{0,31}`) and prompt by name.

## NEVER

- Treat `docs/inbox/*.md` (or any file drop) as delivery proof that a peer “got” a message without a turn that read it or an `agent.prompt`.
- Fire dozens of `herdr agent prompt` while all peers are `working` (builds multi-message queues of obsolete INBOX mail).
- Invent Herdr flags for inbox/queue/clear — only live CLI/docs: https://herdr.dev/docs/cli-reference/
- Assume `agent.prompt` outcome `ok` means the model finished the new mission — only that Herdr submitted text (often into Grok’s queue).

## Human visibility

Global Herdr config (bootstrap `config/herdr/config.toml`) should keep `[ui.toast] delivery = "herdr"` so finished/blocked background agents surface without focusing every pane. Toasts do **not** replace prompt hygiene.
