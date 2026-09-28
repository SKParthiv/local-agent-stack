# First-run checklist — verify.md

Work through this top to bottom the first time. Each step tests one layer of
the pipeline, so when something breaks you know *exactly* which layer broke.

> **Windows curl note:** `curl` is built into Windows 10/11 PowerShell, but in
> PowerShell you may need to write `curl.exe` instead of `curl` (plain `curl`
> is an alias for `Invoke-WebRequest`, which has different flags). All
> commands below use `curl.exe`. Also: in PowerShell, double quotes inside
> double-quoted JSON need escaping — the commands below are written to work
> when pasted into PowerShell as-is.

---

## Step 1 — Ollama, directly

**What this proves:** Ollama is installed, running, and has your models.
(Nothing else in the stack is involved yet.)

```powershell
curl.exe http://localhost:11434/api/tags
```

**Expected:** JSON containing your pulled models, something like:

```json
{"models":[{"name":"qwen2.5-coder:7b","model":"qwen2.5-coder:7b", ...},
           {"name":"qwen3-coder:30b","model":"qwen3-coder:30b", ...}]}
```

If you see `qwen2.5-coder:7b` in there, layer 1 is good.
Empty `"models":[]` → you haven't pulled anything yet (see README).
Connection refused → Ollama isn't running; launch the Ollama app.

---

## Step 2 — LiteLLM proxy, chat completion

**What this proves:** the proxy started, read its config, and can route a
request to `local-fast` (which forwards to Ollama).

Start the proxy first (in this repo's folder):

```powershell
.\start-proxy.ps1
```

Then in a **second** terminal:

```powershell
curl.exe http://localhost:4000/v1/chat/completions -d '{\"model\": \"local-fast\", \"messages\": [{\"role\": \"user\", \"content\": \"Say the word banana and nothing else.\"}]}'
```

**Expected:** JSON with a completion, like:

```json
{"id":"chatcmpl-...","object":"chat.completion","model":"local-fast",
 "choices":[{"index":0,"message":{"role":"assistant","content":"banana"}, ...}]}
```

The key detail: `"model":"local-fast"` — the proxy accepted the friendly
name and routed it. Check the proxy terminal (or the `proxy-logs\*.log`
file): you should see the request logged there too.

If this fails but Step 1 passed, the problem is the proxy layer — read the
proxy terminal output, it names the exact error.

---

## Step 3 — OpenCode through the proxy

**What this proves:** OpenCode is actually talking to your proxy and not
 silently off to some cloud provider.

1. Make sure the OpenCode config from the README (the `opencode.json`
   snippet) is saved and the proxy is still running.
2. In any project folder, run `opencode`.
3. In OpenCode's model picker, select the `litellm/local-fast` model
   (provider "litellm", model "local-fast").
4. Ask it something simple: `Reply with exactly: pipeline works`.

**Expected:** the model replies.

**The real check:** switch to the proxy terminal (or open the newest file
in `proxy-logs\`). You should see a request logged at the moment you sent
the message. If nothing appears in the proxy log, OpenCode is NOT going
through your proxy — re-check the `opencode.json` snippet and that you
picked the `litellm/...` model, not a built-in cloud one.

---

## Step 4 — Tool calling (the real test)

**What this proves:** the whole point of the stack — an agent that can
*act*, not just chat. OpenCode's shell tool goes: OpenCode decides to call
a tool → sends the tool call through the proxy → qwen2.5-coder:7b has to
understand and produce a valid tool call → OpenCode runs the command →
sends the result back through the proxy for the model to read.

In OpenCode, ask:

```
Run this shell command and tell me what it printed: echo hello-from-agent
```

**Expected:**

1. OpenCode shows it's running a command (a permission prompt the first
   time — approve it).
2. It reports the output: `hello-from-agent`.

If the model replies with text *about* the command but never runs it
("Sure, I would run echo hello-from-agent..."), that's a tool-calling
failure — the model didn't emit a proper tool call. Things to check:

- Confirm you're on `local-fast` (qwen2.5-coder:7b is specifically good at
  tool calling; a generic chat model may not be).
- Look in the proxy log for the request — check the tools were attached.
- Try re-asking once; small local models are less reliable at tool calls
  than cloud models, and a retry sometimes lands it.

If all four steps pass: the pipeline is live. Everything an agent does now
flows through the LiteLLM proxy, and its logs are your debugging layer.
