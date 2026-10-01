# ============================================================================
# install.ps1 - one-shot installer for the whole local-agent-stack pipeline.
#
# WHAT IT INSTALLS (same as the README, in the same order):
#   1. Ollama          (winget)  - runs the models on your GPU
#   2. LiteLLM proxy   (pip)     - routes requests to the right model
#   3. OpenCode        (npm)     - the AI coding agent you interact with
#   4. Model weights   (ollama)  - qwen2.5-coder:7b (and optionally the 30b)
#   5. OpenCode config (optional)- points OpenCode at the LiteLLM proxy
#
# HOW TO RUN (from this folder, in PowerShell):
#   .\install.ps1
#
# IT IS SAFE TO RE-RUN: every step first checks if the thing is already
# installed and skips it. Running this twice does nothing the second time.
#
# NOTE ON PATH: installers add their commands to the PATH stored in the
# registry, not to the terminal you are in right now. This script refreshes
# its own PATH after each install, so it keeps working in one go. If a
# command looks missing afterward, open a NEW PowerShell window.
# ============================================================================

# --- Helper: reload PATH from the registry (machine + user) ------------------
# Installers update PATH in the registry; this pulls the fresh value in.
function Update-Path {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

# --- Helper: is a command available on PATH? --------------------------------
function Has-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# --- Helper: pull a model with retries --------------------------------------
# Big downloads over flaky connections die mid-stream. Ollama keeps the
# partial download and RESUMES from where it stopped, so retrying is cheap
# and safe. We try up to 3 times with a pause between attempts.
function Pull-Model($model) {
    foreach ($attempt in 1..3) {
        Write-Host "[..] Pulling $model (attempt $attempt of 3)..." -ForegroundColor Cyan
        ollama pull $model
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[ok] $model is ready." -ForegroundColor Green
            return $true
        }
        Write-Host "[!!] Pull attempt $attempt failed (network hiccup?)." -ForegroundColor Yellow
        if ($attempt -lt 3) {
            Write-Host "     Waiting 30 seconds before retrying (download resumes)..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        }
    }
    return $false
}

Write-Host "=== local-agent-stack installer ===" -ForegroundColor Cyan
Write-Host ""

# --- 0. winget must exist (it ships with Windows 11) --------------------------
if (-not (Has-Command winget)) {
    Write-Host "[!!] 'winget' not found. It is built into Windows 11;" -ForegroundColor Red
    Write-Host "     if missing, install 'App Installer' from the Microsoft Store."
    exit 1
}
Write-Host "[ok] winget available." -ForegroundColor Green

# --- 1. Ollama ---------------------------------------------------------------
if (Has-Command ollama) {
    Write-Host "[ok] Ollama already installed." -ForegroundColor Green
} else {
    Write-Host "[..] Installing Ollama (this downloads ~1 GB, be patient)..." -ForegroundColor Cyan
    winget install --id Ollama.Ollama --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!!] Ollama install failed (exit $LASTEXITCODE)." -ForegroundColor Red
        Write-Host "     Install manually, then re-run this script to continue:"
        Write-Host "     winget install Ollama.Ollama"
        exit 1
    }
    Update-Path
    Write-Host "[ok] Ollama installed." -ForegroundColor Green
}

# --- 2. LiteLLM proxy (needs Python + pip) -----------------------------------
if (-not (Has-Command pip)) {
    Write-Host "[..] pip not found - installing Python 3.12 first..." -ForegroundColor Cyan
    winget install --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!!] Python install failed. Install it manually and re-run:" -ForegroundColor Red
        Write-Host "     winget install Python.Python.3.12"
        exit 1
    }
    Update-Path
    Write-Host "[ok] Python installed." -ForegroundColor Green
}

if (Has-Command litellm) {
    Write-Host "[ok] LiteLLM proxy already installed." -ForegroundColor Green
} else {
    Write-Host "[..] Installing LiteLLM proxy (pip package with extras)..." -ForegroundColor Cyan
    # The quotes matter: "litellm[proxy]" means "litellm plus the proxy
    # extras" (the web server parts). Without [proxy] you only get the
    # Python library, not the 'litellm' command.
    pip install "litellm[proxy]"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!!] LiteLLM install failed. Try manually: pip install `"litellm[proxy]`"" -ForegroundColor Red
        exit 1
    }
    Update-Path
    Write-Host "[ok] LiteLLM proxy installed." -ForegroundColor Green
}

# --- 3. OpenCode (needs Node.js + npm) ---------------------------------------
if (-not (Has-Command npm)) {
    Write-Host "[..] npm not found - installing Node.js LTS first..." -ForegroundColor Cyan
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!!] Node.js install failed. Install manually and re-run:" -ForegroundColor Red
        Write-Host "     winget install OpenJS.NodeJS.LTS"
        exit 1
    }
    Update-Path
    Write-Host "[ok] Node.js installed." -ForegroundColor Green
}

if (Has-Command opencode) {
    Write-Host "[ok] OpenCode already installed." -ForegroundColor Green
} else {
    Write-Host "[..] Installing OpenCode globally via npm..." -ForegroundColor Cyan
    npm install -g opencode-ai
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!!] OpenCode install failed. Try manually: npm install -g opencode-ai" -ForegroundColor Red
        exit 1
    }
    Update-Path
    Write-Host "[ok] OpenCode installed." -ForegroundColor Green
}

# --- 4. Model weights --------------------------------------------------------
# The Ollama *server* must be running to pull models. If it is not up yet,
# try to start the app; if that fails, tell the user to launch it.
$ollamaUp = $false
try {
    $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 3
    $ollamaUp = $true
} catch { }

if (-not $ollamaUp) {
    Write-Host "[..] Ollama server not running - trying to start the app..." -ForegroundColor Cyan
    # The Windows Ollama install lives here by default; launching it starts
    # the background server (you get the system tray icon).
    $ollamaApp = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama app.exe"
    if (Test-Path $ollamaApp) {
        Start-Process -FilePath $ollamaApp
    } else {
        # Fallback for custom install locations: 'ollama serve' runs the
        # server directly (works, but no tray icon).
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
    }
    # Give it up to 10 seconds to come up, then verify.
    foreach ($i in 1..10) {
        Start-Sleep -Seconds 1
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 2
            $ollamaUp = $true
            break
        } catch { }
    }
}

if (-not $ollamaUp) {
    Write-Host "[!!] Could not start the Ollama server." -ForegroundColor Red
    Write-Host "     Launch the Ollama app from the Start menu, then re-run this script."
    Write-Host "     (Already-installed parts above were skipped, so the re-run is quick.)"
    exit 1
}
Write-Host "[ok] Ollama server is running." -ForegroundColor Green

# Pull the fast model. (Idempotent: 'ollama pull' on an existing model
# just verifies it and exits immediately. Interrupted pulls resume.)
$fast = "qwen2.5:7b-instruct"
if (-not (Pull-Model $fast)) {
    Write-Host "[!!] Pull kept failing. Re-run this script later - it will resume" -ForegroundColor Red
    Write-Host "     the download where it stopped. Or retry manually: ollama pull $fast"
    exit 1
}

# The heavy model is a 19 GB download that will NOT fit in 8 GB VRAM and
# runs slowly (partially in RAM). Only pull it if the user actively wants it.
$heavy = "qwen3-coder:30b"
$wantsHeavy = Read-Host "Also pull $heavy now? ~19 GB, slow on 8 GB VRAM. Recommended: add it later. [y/N]"
if ($wantsHeavy -eq 'y' -or $wantsHeavy -eq 'Y') {
    # Non-fatal if it fails - the fast model is what matters.
    if (-not (Pull-Model $heavy)) {
        Write-Host "[!!] Heavy model pull failed - not fatal, retry anytime (it resumes):" -ForegroundColor Yellow
        Write-Host "     ollama pull $heavy"
    }
} else {
    Write-Host "[ok] Skipping $heavy (pull it anytime with: ollama pull $heavy)" -ForegroundColor Gray
}

# --- 5. OpenCode config (optional) -------------------------------------------
# Writes the config that points OpenCode at the LiteLLM proxy
# (http://localhost:4000/v1) with local-fast as the default model.
$writeConfig = Read-Host "Write the OpenCode config now? (backs up any existing file) [Y/n]"
if ($writeConfig -ne 'n' -and $writeConfig -ne 'N') {
    # Global config location on Windows. Create the folder if needed.
    $ocDir = Join-Path $env:USERPROFILE ".config\opencode"
    New-Item -ItemType Directory -Path $ocDir -Force | Out-Null
    $ocFile = Join-Path $ocDir "opencode.json"

    # If a config already exists, do not destroy it - rename it with a
    # timestamp so you can merge/diff later.
    if (Test-Path $ocFile) {
        $backup = "$ocFile.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $ocFile $backup
        Write-Host "[ok] Existing config backed up to: $backup" -ForegroundColor Yellow
    }

    # This JSON is identical to the snippet in README.md (OpenCode v2 format).
    # It is written with a PowerShell here-string (@' ... '@) so the JSON
    # stays readable and nothing inside it gets accidentally interpreted.
    $ocJson = @'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "litellm/local-fast",
  "providers": {
    "litellm": {
      "package": "aisdk:@ai-sdk/openai-compatible",
      "name": "LiteLLM (local)",
      "settings": {
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
'@
    # Out-File with -Encoding utf8 writes UTF-8 (OpenCode expects UTF-8 JSON).
    $ocJson | Out-File -FilePath $ocFile -Encoding utf8
    Write-Host "[ok] OpenCode config written to: $ocFile" -ForegroundColor Green
} else {
    Write-Host "[ok] Skipped - the config snippet is in README.md when you want it." -ForegroundColor Gray
}

# --- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Start the proxy:     .\start-proxy.ps1"
Write-Host "  2. Verify everything:   follow verify.md (top to bottom)"
Write-Host "  3. Use it:              run 'opencode' in any project folder"
Write-Host ""
Write-Host "If any command above is 'not found' in THIS window, open a new"
Write-Host "PowerShell window first - PATH changes only land in new windows."
