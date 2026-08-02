# Ollama Model Testing — `_ping-test` (Terminal Agent)

Record of testing several local Ollama models as the backend for a NanoClaw agent group.

- **Date:** 2026-08-02 (JST)
- **Agent group:** `_ping-test` / Terminal Agent
- **Ollama host:** Windows host, reached from the agent container via `host.docker.internal:11434` (Docker Desktop). Ollama `0.22.0`, `OLLAMA_HOST=0.0.0.0`.
- **Test prompts:** `あなたの名前は？` and `使用しているモデルの名前を短く答えて`, sent via `pnpm run chat ...`.
- **GPU:** `RTX-2070` 

## Two independent requirements a model must satisfy

The NanoClaw agent-runner puts two hard constraints on any backend model. A model must pass **both** to be usable — most local models fail at least one.

1. **Tool support (function calling).** The agent-runner (Claude Agent SDK) sends tool definitions (Bash, Read, Edit, MCP tools, …) on *every* request. Ollama rejects models without a tool-capable template with:
   ```
   API Error: 400 ... "<model> does not support tools"
   ```
2. **`<message to="...">` output wrapping.** This group's `CLAUDE.local.md` requires every reply to be wrapped in a `<message to="local-cli">…</message>` block. Unwrapped output is **silently discarded** by the poll loop:
   ```
   [poll-loop] WARNING: agent output had no <message to="..."> blocks — nothing was sent
   ```
   The `pnpm run chat` client then times out after 300s (`exit code 3`) because no reply was ever delivered.

## Results

| Model | Size | Tool support | `<message>` wrapping | Verdict |
|-------|------|--------------|----------------------|---------|
| **qwen3.5:4b** | 4.7B | ✅ native | ✅ reliable after fix | **Chosen / working.** Initially intermittent (emitted bare `Claude` / `<Claude>` with no wrapper → discarded), but reliable after strengthening `CLAUDE.local.md` **and** clearing the resumed session — see [Resolution](#resolution). |
| **gemma4:latest** | ~12B | ✅ native | ❌ failed | Produced coherent text (`"I operate using the advanced models in the Claude family."`) but never wrapped it → discarded/timeout. Also claims to be Claude. |
| **llama3:latest** | 8B | ❌ 400 "does not support tools" | — | Unusable. Rejected before generating. |
| **deepseek-r1:8b** | 8B | ❌ 400 "does not support tools" | — | Unusable as-is (see experiment below). |
| **deepseek-r1-tools:8b** | 8B | ⚠️ capability added, unparseable | — | Custom derived model; tool capability enabled but tool-call format is not reliably parseable (see below). |

## deepseek-r1 tool-calling experiment

`deepseek-r1:8b` is **DeepSeek-R1-Distill-Llama-8B** — a reasoning distill that was **not trained for tool use**. Its stock Ollama template has capabilities `['completion','thinking']`, no `tools`.

Attempt: create a derived model `deepseek-r1-tools:8b` from the existing weights (no re-download) with a custom `TEMPLATE` that declares `.Tools`, via `POST /api/create`:

```bash
curl http://<ollama>:11434/api/create -d '{
  "model":"deepseek-r1-tools:8b",
  "from":"deepseek-r1:8b",
  "template":"... TEMPLATE that renders .Tools and .ToolCalls ...",
  "parameters":{"stop":["<｜end▁of▁sentence｜>", ...],"temperature":0.6,"top_p":0.95}
}'
```

Result: capability `tools` **was** added (the 400 disappeared), but the model **emits a different tool-call format on every generation**, none of which Ollama parses back into structured `tool_calls` (always `tool_calls: null`):

| Template format instructed | What the model actually emitted |
|----------------------------|---------------------------------|
| DeepSeek native tokens (`<｜tool▁calls▁begin｜>…`) | Correct format — but Ollama 0.22 didn't parse it |
| Hermes `<tool_call>{json}</tool_call>` | Bare JSON, no wrapper |
| Bare JSON `{"name":…,"arguments":…}` | Bare JSON (Ollama can't locate it after `<think>`) |
| `<tool_call>` wrapper + worked example | ` ```json ` code-fenced JSON |

**Conclusion:** this is a *weights* problem, not a template problem. The distill isn't trained to emit a single consistent tool-call format, so no template fixes it (community "tool-calling" repacks of the same base are expected to behave the same). Combined with heavy `<think>` output and the `<message>` wrapping requirement, deepseek-r1 is not viable as a NanoClaw agent backend.

## Root cause summary

- **llama3 / deepseek-r1** fail requirement #1 (no tool support). llama3 has none; deepseek-r1 can be given the *capability* but not reliable *behavior*.
- **qwen3.5:4b / gemma4** pass #1 but stumble on #2 — small models don't reliably follow the strict `<message to="local-cli">` wrapping rule, and both tend to hallucinate that they are Claude.

The recurring blocker for the two otherwise-usable models is the **message-wrapping requirement**, aggravated by small-model instruction-following.

## Recommendation & possible fixes

- **Use `qwen3.5:4b`** — the only model that supports tools *and* was observed producing a correctly-wrapped, delivered reply.
- To make wrapping reliable, either:
  1. **Strengthen `groups/_ping-test/CLAUDE.local.md`** — restate the `<message to="local-cli">` rule forcefully with a worked example (no code change; picked up on next container spawn), and add a line telling the model which local model it actually runs on (to stop the "I am Claude" hallucination); or
  2. **Make the runner lenient** — fall back to sending raw text when the agent output contains no `<message to="…">` block (code change in `container/agent-runner/src/`, needs a container rebuild).

## Resolution

`_ping-test` now runs reliably on **`qwen3.5:4b`**. Two changes were both required:

1. **Strengthened `groups/_ping-test/CLAUDE.local.md`** — the `<message to="local-cli">` rule restated forcefully with several worked examples (including the model-name question), plus a line telling the model it runs on a local Ollama model and must not claim to be Claude.
2. **Cleared the resumed session.** This was the non-obvious part. The agent-runner resumes the prior Claude Code session (`[poll-loop] Resuming agent session <id>`), which carries the old conversation history where the model had answered *without* wrapping. The strengthened `CLAUDE.local.md` only took full effect on a **fresh** session. Clear it while the container is stopped:
   ```bash
   docker kill $(docker ps --filter name=nanoclaw-v2-_ping-test --format '{{.Names}}')
   pnpm exec tsx scripts/q.ts \
     data/v2-sessions/ag-1778331463596-1kikh6/sess-1778331464197-8x22n1/outbound.db \
     "DELETE FROM session_state WHERE key='continuation:claude';"
   ```

After both changes, three test prompts (`使用しているモデルの名前を短く答えて`, a self-introduction, `3たす5は？`) all returned correctly-wrapped, delivered replies — and the model correctly stated it runs on `qwen3.5:4b` rather than claiming to be Claude.
