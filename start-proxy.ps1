# ============================================================================
# start-proxy.ps1 - one-shot launcher for the LiteLLM proxy (Windows native).
#
# WHAT IT DOES, IN ORDER:
#   1. Checks that Ollama is running (the proxy is useless without it)
#   2. Makes sure the model you configured is actually pulled
#   3. Starts the LiteLLM proxy with litellm-config.yaml
#   4. Saves ALL proxy output to a timestamped log file (your debugging layer)
#   5. Prints the URL to point clients at
#
# HOW TO RUN IT (from this folder, in PowerShell):
#   .\start-proxy.ps1
# If Windows blocks the script with an "execution policy" error, run this
# ONCE (it allows local scripts only, stays on your machine):
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# TO STOP THE PROXY: focus this window and press Ctrl+C.
# The log file keeps whatever was written up to that point.
# ============================================================================

# --- 0. Fail fast if anything LiteLLM needs is missing ----------------------

# Test-Path checks a file/folder exists; "Get-Command X -ErrorAction SilentlyContinue"
# returns nothing if the command X isn't installed.
if (-not (Get-Command litellm -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'litellm' command not found." -ForegroundColor Red
    Write-Host "Install it first:  pip install `"litellm[proxy]`""
    exit 1
}

# --- 1. Check Ollama is running ----------------------------------------------
# Ollama runs as a background app and serves HTTP on port 11434.
# We just poke its API; if it answers, it's alive. No HTTP 200 = not running.
$ollamaOk = $false
try {
    # Invoke-RestMethod makes the HTTP GET and parses the JSON for us.
    # -TimeoutSec 3 stops us hanging forever if nothing is listening.
    $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3
    $ollamaOk = $true
    Write-Host "[ok] Ollama is running." -ForegroundColor Green
} catch {
    Write-Host "[!!] Ollama is NOT reachable at http://localhost:11434" -ForegroundColor Red
    Write-Host "     Start it first: launch the 'Ollama' app from the Start menu,"
    Write-Host "     or run 'ollama serve' in another terminal."
    exit 1
}

# --- 2. Check the default model is pulled ------------------------------------
# 'local-fast' maps to qwen2.5-coder:7b in litellm-config.yaml. If it isn't
# pulled yet, requests will fail with a confusing error, so check up front.
# (We only check the fast model - the heavy one takes ages to pull and you
#  might not want it yet.)
$requiredModel = "qwen2.5-coder:7b"
try {
    $tags = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3
    # The JSON has a "models" array; each item has a "name" like "qwen2.5-coder:7b".
    $pulled = $tags.models | Where-Object { $_.name -eq $requiredModel }
    if ($pulled) {
        Write-Host "[ok] Model '$requiredModel' is pulled." -ForegroundColor Green
    } else {
        Write-Host "[!!] Model '$requiredModel' is NOT pulled yet." -ForegroundColor Yellow
        Write-Host "     Run:  ollama pull $requiredModel   (one-time, ~5 GB download)"
        exit 1
    }
} catch {
    Write-Host "[??] Could not read Ollama's model list: $_" -ForegroundColor Yellow
    Write-Host "     Continuing anyway - if requests fail, run: ollama pull $requiredModel"
}

# --- 3. Prepare the log file --------------------------------------------------
# LiteLLM has no built-in "log to file" option that actually works (the
# LITELLM_LOG_FILE env var is documented but not implemented). The honest
# approach: capture everything the proxy prints. LiteLLM logs requests to
# stdout, so the file gets them all.

# Make sure the log folder exists (it's gitignored, see .gitignore).
New-Item -ItemType Directory -Path ".\proxy-logs" -Force | Out-Null

# Build a timestamped filename like proxy-20260928-153000.log so every run
# gets its own file and you can diff "what did the agent send at 3pm?".
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = ".\proxy-logs\proxy-$timestamp.log"

# LITELLM_LOG controls how chatty the proxy is: INFO shows request summaries;
# DEBUG shows full request/response detail (much bigger logs). Start at INFO.
$env:LITELLM_LOG = "INFO"

# --- 4. Start the proxy -------------------------------------------------------
Write-Host ""
Write-Host "Starting LiteLLM proxy..." -ForegroundColor Cyan
Write-Host "  config : litellm-config.yaml (in this folder)" -ForegroundColor Gray
Write-Host "  log    : $logFile" -ForegroundColor Gray
Write-Host "  console output below is ALSO saved to the log file" -ForegroundColor Gray
Write-Host ""

# The heart of the script. Breaking down the pieces:
#   litellm --config litellm-config.yaml   -> run the proxy with our routing table
#   --port 4000                            -> listen on port 4000 (LiteLLM's default)
#   2>&1                                   -> merge error output into the same stream
#   | Tee-Object -FilePath $logFile        -> show output on screen AND write it
#                                             to the log file at the same time.
# Tee-Object is the PowerShell equivalent of Linux's `tee`.
litellm --config litellm-config.yaml --port 4000 2>&1 | Tee-Object -FilePath $logFile

# --- 5. We only reach here after Ctrl+C ---------------------------------------
Write-Host ""
Write-Host "Proxy stopped. Full log saved to: $logFile" -ForegroundColor Cyan
