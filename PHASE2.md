# PHASE2 — later ideas (documentation only, nothing installed)

Short notes for where this stack could go. None of this is needed for the
core pipeline; do not install any of it until Phase 1 is boring and stable.

> **The build-out roadmap now lives in [ARCHITECTURE.md](ARCHITECTURE.md)**
> (orchestration, model registry, escalation, later phases). This file
> keeps the *access-surface* ideas: how you reach the stack from elsewhere.

## Open WebUI over Ollama — chat from your phone

Open WebUI is a self-hosted ChatGPT-style web interface that talks to
Ollama directly. Run it on the laptop (Docker is the usual way:
`docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway
-v open-webui:/app/backend/data --name open-webui --restart always
ghcr.io/open-webui/open-webui:main`) and browse to `http://localhost:3000`.
On the same Wi-Fi, your phone can hit `http://<laptop-LAN-IP>:3000` for a
free private ChatGPT. Note it bypasses the LiteLLM proxy (talks to Ollama
directly) — that's fine; it's a chat surface, not an agent surface.

## Tailscale — reach the stack from anywhere

A free VPN that gives every device a stable private IP, no port forwarding.
Install on laptop + phone, and the phone can reach Ollama, LiteLLM, or
Open WebUI from anywhere as if on home Wi-Fi. If you do this, uncomment
`master_key` in litellm-config.yaml first — anything exposed past localhost
needs an API key. One caveat: Ollama by default only accepts requests from
localhost; exposing it to Tailscale needs `OLLAMA_HOST=0.0.0.0` and a
firewall rule — a real project, not a config line.

## Where a custom MCP server would slot in

MCP (Model Context Protocol) is a standard way to give agents extra tools
(search your notes, query a database, control an app). If you write your
own MCP server, it plugs into **OpenCode's** config (`mcp` section in
`opencode.json`), NOT into LiteLLM. The pipeline stays exactly as-is:
LiteLLM routes model requests; OpenCode owns tools. Your custom server
would sit beside OpenCode's built-in shell/file tools, and the model calls
it through the same agent loop, over the same proxy. (LiteLLM does have an
MCP feature that attaches tools at the proxy layer, but keeping tools in
the client is simpler and easier to debug for now.)
