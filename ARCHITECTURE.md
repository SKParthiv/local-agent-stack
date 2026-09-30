# ARCHITECTURE — where this stack is going (design doc, no code)

This file captures the **target design** for later phases. Nothing in here is
built, installed, or required for Phase 1 to work. It exists so that when
Phase 1 is boring and stable, the next steps are already thought through.

> **Rule that governs this file:** Phase 1 must pass verify.md end-to-end on
> the real machine — including a successful tool call — before any Phase 2
> code is written. Evidence from the proxy logs decides when that is.

## The one distinction that matters: model router vs. task router

These are two different jobs that must never be merged:

- **Model router (LiteLLM, already built):** answers *"where should this
  model request go?"* — `local-fast` → Ollama, `cloud-reasoning` → Gemini.
  It is a dumb, reliable pipe. It does not decide what work happens.
- **Task router (future, if ever needed):** answers *"should this task run
  locally, by which worker, with which model, and when should it escalate?"*
  This is decision-making logic, and it would be custom code.

LiteLLM stays underneath everything as the model gateway. The task layer —
if it ever gets built — sits above it and calls *through* it.

## Phase 1 (now): the pipeline, verified

```
OpenCode ──> LiteLLM proxy ──> Ollama (local-fast / local-heavy)
```

One client, one user, one proxy, two models. The proxy logs are the
debugging layer. This is complete when verify.md's four steps pass on the
real Windows machine — especially Step 4, the tool call.

## Phase 2 (candidate): orchestration foundation

**Trigger to start:** Phase 1 is stable AND there's evidence in the proxy
logs that a single agent loop can't handle the workload (e.g. tasks that
genuinely need parallel workers, or repeated cases where the local model
fails and a cloud model would have succeeded).

The minimal honest version:

```
User ──> Admin agent ──> Task schema ──> Task router ──> workers ──> LiteLLM ──> models
```

Pieces, in build order (each one earns its existence before the next):

1. **Model registry** (`config/models.yaml`) — capability-based names
   instead of fast/heavy: `local_code_fast`, `local_reasoning`,
   `cloud_reasoning`. Capabilities would need *measured* scores, not
   invented ones — benchmark each model on your actual tasks first.
2. **Task schema** — a simple, versioned JSON format for a unit of work:
   id, type, inputs, required capabilities, status, result.
3. **Agent registry + task router** — map task types to workers/models.
4. **Escalation rule** — the simplest possible version: "if the local model
   errors or times out N times, retry on the cloud model." Note the hard
   problem below.
5. **Structured logging** — extend the proxy log capture with task IDs so
   every request can be traced to the task that caused it.

## Problems this design has NOT solved (be honest about these)

- **Confidence signals.** "Local model was unsure, escalate to cloud"
   needs a reliable confidence measure. Small local models don't emit one.
   The workable substitute is outcome-based: error, timeout, or failed
   validation → escalate. That's implementable; a numeric confidence score
   is a research project.
- **VRAM-aware scheduling.** Refusing to launch a model that doesn't fit
   requires real GPU/RAM telemetry on Windows (nvidia-smi polling at
   minimum) plus a model-size table. A genuine sub-project, not a config
   file. Until it exists, the honest rule is manual: `local-heavy` is an
   experiment you run deliberately, not a default worker.
- **Budget management.** With a zero-spend rule, "budget" means: the cloud
   tier's free rate limits and a kill switch. A cost-tracking dashboard is
   pointless when everything costs zero.

## Later phases (sketches only)

- **Phase 3:** persistent agent state — where Letta-style memory would slot
  in, if the workload shows agents need to remember across tasks.
- **Phase 4:** specialized workers and multi-agent execution — only once
  the task router demonstrably improves results over one agent loop.
- **Phase 5:** concurrent workers, GPU-aware scheduling, automatic model
  selection. The most speculative layer; each piece is a real project.

## What stays true in every phase

- LiteLLM remains the single model gateway; nothing calls Ollama or cloud
  APIs directly.
- No secrets in the repo.
- Every phase must be verifiable from the proxy logs.
- The repo stays as small as the current phase honestly needs. The failure
  mode of agent systems is a 47-agent YAML monarchy; the countermeasure is
  building only what the previous phase's evidence demands.
