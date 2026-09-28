# local-agent-stack

Infrastructure for running AI coding agents on your own Windows machine,
with free local models instead of paid cloud APIs.

## What this is

One pipeline, three layers. Local models (via Ollama) and Google's free
Gemini tier sit behind a single **LiteLLM proxy** — a small local server
that speaks the "OpenAI-compatible" API every AI tool already knows. Any
client — OpenCode today, something else tomorrow — points at the proxy and
asks for a model by a friendly name like `local-fast`; the proxy routes the
request to the right place and logs everything that passes through, which
makes it your debugging layer for the whole stack.

```
[Ollama local models + Gemini free tier]  -->  [LiteLLM proxy]  -->  [OpenCode / any OpenAI-compatible client]
        (the models)                           (the router)              (the thing you use)
                     localhost:11434                localhost:4000
```

Everything runs on your machine. Nothing costs money. No repo contains a
secret key.

## What's in here

| File | What it is |
|---|---|
| `litellm-config.yaml` | The proxy's routing table: friendly names → real models. Heavily commented. |
| `start-proxy.ps1` | PowerShell script: checks Ollama, starts the proxy, saves logs. |
| `verify.md` | First-run checklist — follow it once, top to bottom. |
| `PHASE2.md` | Future ideas (phone access, remote access, MCP). Docs only, nothing installed. |

## Install (Windows 11, native — no WSL)

Each command installs one layer. Run them in PowerShell.

```powershell
# Ollama: the app that runs models locally on your GPU.
winget install Ollama.Ollama

# LiteLLM proxy: the router between clients and models.
pip install "litellm[proxy]"

# OpenCode: the AI coding agent (terminal UI) that will use the models.
npm install -g opencode-ai
```

Prerequisites those assume: **Git** (`winget install Git.Git`), **Node.js**
for npm (`winget install OpenJS.NodeJS.LTS`), and **Python** for pip
(`winget install Python.Python.3.12`). If `pip`, `npm`, or `git` already
work in your terminal, you have what you need.

> Tip: after installing, open a NEW PowerShell window so the fresh
> `PATH` entries are picked up.

## Pull the models

Downloads the model weights to your machine (one time each). Sized for an
8 GB VRAM laptop GPU.

```powershell
# ~5 GB. The 7B coder model: fits fully in your 8 GB VRAM, runs fast.
# This is your everyday model ("local-fast").
ollama pull qwen2.5-coder:7b

# ~19 GB. The 30B model: too big for VRAM, so Ollama keeps part in system
# RAM. Expect several seconds per response at best. For heavy generation
# jobs where you can wait ("local-heavy").
ollama pull qwen3-coder:30b
```

## Start everything

1. **Ollama** — launch the Ollama app from the Start menu (it runs in the
   background; its icon appears in the system tray).
2. **The proxy** — in this repo's folder, in PowerShell:

   ```powershell
   .\start-proxy.ps1
   ```

   First run only, if Windows blocks the script:

   ```powershell
   # Allows local scripts to run. Does not change anything for downloaded scripts.
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

   The proxy is now at **http://localhost:4000** and logging every request
   to `proxy-logs\proxy-<timestamp>.log` (gitignored — logs contain your
   prompts, so they never get committed).

3. **OpenCode** — configure it (next section), then run `opencode` in any
   project folder.

## Point OpenCode at the proxy

OpenCode needs to know your proxy exists and which models it offers. Save
this as `opencode.json` in the folder where you run OpenCode (or globally at
`%USERPROFILE%\.config\opencode\opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "litellm/local-fast",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM (local)",
      "options": {
        "baseURL": "http://localhost:4000/v1",
        "apiKey": "no-key-needed"
      },
      "models": {
        "local-fast": { "name": "qwen2.5-coder:7b via proxy" },
        "local-heavy": { "name": "qwen3-coder:30b via proxy" }
      }
    }
  }
}
```

Line-by-line, because every field matters:

| Field | Meaning |
|---|---|
| `"model": "litellm/local-fast"` | Your default model: the `local-fast` model from the provider named `litellm`. Format is always `provider/model`. |
| `"npm": "@ai-sdk/openai-compatible"` | Tells OpenCode to speak the OpenAI-compatible API — the dialect LiteLLM serves. |
| `"options.baseURL"` | Where the proxy lives. **Must include `/v1`** — that's the API version path LiteLLM serves. |
| `"options.apiKey"` | LiteLLM (our config) doesn't check keys locally, but the client library requires *some* value — any string works. |
| `"models"` | The models OpenCode shows in its picker. Keys must match the `model_name` values in `litellm-config.yaml`. |

Inside OpenCode, the model picker (Tab → models, or the `/models` command)
should now show a "LiteLLM (local)" provider with `local-fast` and
`local-heavy`. Pick `local-fast`.

## Verify it works

Open **[verify.md](verify.md)** and follow the four steps. Short version:

```powershell
# 1. Ollama alive? -> JSON listing your models
curl.exe http://localhost:11434/api/tags

# 2. Proxy routes? -> JSON chat completion, "model":"local-fast"
curl.exe http://localhost:4000/v1/chat/completions -d '{\"model\": \"local-fast\", \"messages\": [{\"role\": \"user\", \"content\": \"Say banana.\"}]}'
```

```powershell
# 3. Proxy's own health endpoint -> JSON with deployment statuses
curl.exe http://localhost:4000/health
```

Step 4 in verify.md is the real test: ask OpenCode to run a shell command
and watch it work — that's a full agent loop (model → tool call → result →
model) through your proxy.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `start-proxy.ps1` says Ollama not reachable | Ollama app not launched. Start menu → Ollama. |
| `litellm` not found | New terminal needed after install, or pip isn't on PATH. |
| Proxy started but requests 404 | Client baseURL missing `/v1`, or model name typo'd — must match `model_name` in the YAML exactly. |
| Requests hang forever on `local-heavy` | Expected-ish: the 30B model is partially in RAM. Switch to `local-fast`. |
| OpenCode ignores your config | Check you saved it as `opencode.json` (not `.json.txt`) in the right folder, and picked the `litellm/...` model in the picker. |
| Want to see exactly what agents send | Set `$env:LITELLM_LOG = "DEBUG"` in start-proxy.ps1, restart, read `proxy-logs\`. |

## Glossary

- **Model server** — A program that runs AI models and serves them over the
  network. Ollama is your model server: it loads model files onto your GPU
  and answers requests on port 11434.
- **Proxy** — A middleman server that sits between clients and backends.
  LiteLLM is your proxy: clients talk only to it, and it forwards each
  request to the right model server. Its logs show every request, which is
  why it doubles as your debugging layer.
- **OpenAI-compatible API** — A de-facto standard request/response format
  (endpoints like `/v1/chat/completions`) that OpenAI popularized and most
  tools now speak. Because LiteLLM speaks it, any tool built for OpenAI can
  use your local models with zero code changes.
- **MCP server** — A server implementing the Model Context Protocol, a
  standard way to expose extra tools (search, databases, apps) to AI agents.
  OpenCode can connect to MCP servers directly; see PHASE2.md.
- **Tool calling** — A model's ability to output not just text but a
  structured request to run a specific tool ("run this shell command",
  "read this file"). The client executes the tool and feeds the result back
  to the model. This is what makes an agent able to *act*.
- **Agent loop** — The cycle: model responds → maybe requests a tool → tool
  runs → result goes back to the model → repeat until the task is done.
  Each cycle is one or more requests through your proxy.
- **Context window** — The model's working memory: everything (system
  prompt, conversation, tool results) it can "see" at once, measured in
  tokens. qwen2.5-coder:7b handles ~32k tokens; long sessions eventually
  overflow it, which is why agents summarize as they go.

## Honest status

| Component | Status |
|---|---|
| Config files, scripts, docs | Written and reviewed; YAML validated |
| `start-proxy.ps1` on Windows | **UNTESTED** — written on a Linux sandbox with standard PowerShell patterns; run once to confirm |
| End-to-end (OpenCode → proxy → Ollama) | **UNTESTED here** — that's what verify.md walks you through on your machine |
| Gemini free tier | **UNTESTED** — entry is commented out in litellm-config.yaml until you add a key |

This repo is infrastructure, not a product. When something breaks, the
answer is almost always in the proxy logs.
