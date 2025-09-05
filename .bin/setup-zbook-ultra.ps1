<#  setup-zbook-ultra.ps1 — Cohesive developer setup for HP ZBook Ultra G1a (Ryzen AI) or similar
    What this does (idempotent):
      • Enables WSL2 + installs Ubuntu 24.04 (preferred)
      • Writes %USERPROFILE%\.wslconfig (resources)
      • Creates Windows acceleration tiers:
          - Tier 2: Miniforge Python 3.11 with torch-directml
          - Tier 3: Python 3.13 venv with onnxruntime-directml (+ genai)
      • Installs a smart launcher:  %USERPROFILE%\.bin\run-accelerated.ps1
      • Bootstraps Ubuntu 24.04 with dev tooling, systemd, Docker CLI, ROCm tools, and a GPU probe
      • Shuts WSL down once to apply config
    Usage:
      - Run in an elevated PowerShell (Admin). If Ubuntu installs for the first time,
        complete its first-run user creation, then re-run this script.
#>

# ---------------- Safety / helpers ----------------
$ErrorActionPreference = "Stop"

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Please re-run in an **elevated** PowerShell (Run as Administrator)."
  }
}
Require-Admin

function Step($msg) { Write-Host ">>> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Ok($msg)   { Write-Host "✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "⚠ $msg" -ForegroundColor Yellow }

# ---------------- Config you may tweak ----------------
# Sensible defaults for a 12C/24T / 32 GB RAM laptop. Adjust as you like.
$WSL_Processors = 12
$WSL_MemoryGB   = 12
$WSL_SwapGB     = 16

$WinBin = Join-Path $env:USERPROFILE ".bin"
$OnnxVenv = Join-Path $env:USERPROFILE "venvs\onnx-dml-313"   # Py 3.13 venv path
$CondaRoot = Join-Path $env:USERPROFILE "miniforge3"          # Miniforge install dir
$CondaExe  = Join-Path $CondaRoot "Scripts\conda.exe"
$TorchEnv  = "ai-dml-py311"                                   # Py 3.11 env name

# ---------------- 0) Enable Windows features + WSL2 ----------------
Step "Enable Windows features (WSL + VM Platform)"
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart  | Out-Null
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform            /all /norestart  | Out-Null

Step "Set WSL default version to 2"
wsl --set-default-version 2 | Out-Null

# Install Ubuntu 24.04 if missing
Step "Install Ubuntu-24.04 (if missing)"
$haveUbuntu = (wsl -l -q) -contains "Ubuntu-24.04"
if (-not $haveUbuntu) {
  wsl --install -d Ubuntu-24.04
  Warn "Ubuntu-24.04 will prompt for a Linux username/password on first launch."
  Warn "After completing first-run, re-run THIS script to continue."
  return
} else {
  Ok "Ubuntu-24.04 already installed"
}

# ---------------- 1) Write %USERPROFILE%\.wslconfig ----------------
Step "Write %USERPROFILE%\.wslconfig (resources)"
$wslcfg = @"
[wsl2]
processors=$WSL_Processors
memory=${WSL_MemoryGB}GB
swap=${WSL_SwapGB}GB
localhostForwarding=true
"@
$wslcfgPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslcfg | Out-File -Encoding ASCII -NoNewline $wslcfgPath
Ok "Wrote $wslcfgPath"

# ---------------- 2) Create Windows .bin + smart launcher ----------------
Step "Create Windows bin dir"
New-Item -ItemType Directory -Path $WinBin -Force | Out-Null

Step "Install/Update smart launcher: run-accelerated.ps1"
$launcherPath = Join-Path $WinBin "run-accelerated.ps1"
$launcher = @"
param(
  [Parameter(Mandatory=\$true)][string] \$Script,
  [string[]] \$Args
)

# Preference order:
# 1) WSL Ubuntu-24.04 w/ ROCm GPU agent
# 2) Windows torch-directml (Miniforge Py 3.11)
# 3) Windows ONNX Runtime (DirectML) on Python 3.13 venv
# 4) CPU fallback

\$PreferredDistros = @("Ubuntu-24.04","Ubuntu")
\$OnnxVenv   = Join-Path \$env:USERPROFILE "venvs\onnx-dml-313"
\$Py313Exe   = "py"  # Windows Python launcher
\$CondaRoot  = Join-Path \$env:USERPROFILE "miniforge3"
\$CondaExe   = Join-Path \$CondaRoot "Scripts\conda.exe"
\$TorchEnv   = "ai-dml-py311"

function Convert-PathToWSL(\$winPath) {
  if (\$winPath -match '^[A-Za-z]:\\') {
    \$drive = \$winPath.Substring(0,1).ToLower()
    \$rest  = \$winPath.Substring(2) -replace '\\','/'
    return "/mnt/\$drive/\$rest"
  } else {
    return \$winPath -replace '\\','/'
  }
}

function Get-FirstExistingDistro([string[]]\$names) {
  try {
    \$list = wsl.exe -l -q | ForEach-Object { \$_.Trim() } | Where-Object { \$_ }
    foreach (\$n in \$names) { if (\$list -contains \$n) { return \$n } }
    return \$null
  } catch { return \$null }
}

function Test-WSLROCm([string]\$distro) {
  if (-not \$distro) { return \$false }
  try {
    # Detect 'Device Type: GPU' in rocminfo
    \$cmd = "bash -lc `"command -v rocminfo >/dev/null 2>&1 && rocminfo | awk '/Agent/{p=1} p && /Device Type:/{print; exit}' || true`" 
    \$out = & wsl.exe -d \$distro --% \$cmd
    return (\$out -match 'Device Type:\s+GPU')
  } catch { return \$false }
}

function Ensure-OnnxVenv([string]\$venvPath) {
  \$python = Join-Path \$venvPath "Scripts\python.exe"
  if (-not (Test-Path \$python)) {
    Write-Host "[Windows] Creating venv for ONNX Runtime (DirectML) @ \$venvPath" -ForegroundColor Cyan
    & \$Py313Exe -3.13 -m venv \$venvPath
  }
  Write-Host "[Windows] Ensuring onnxruntime-directml is installed" -ForegroundColor Cyan
  & \$python -m pip install --upgrade pip
  & \$python -m pip install --upgrade onnxruntime-directml onnxruntime-genai-directml 2>\$null
  return \$python
}

function Test-CondaTorchDML() {
  if (-not (Test-Path \$CondaExe)) { return \$false }
  try {
    \$ok = & \$CondaExe run -n \$TorchEnv python - << 'PY'
try:
    import torch, torch_directml  # noqa
    print("OK")
except Exception as e:
    print("ERR", e)
PY
    return (\$ok -match '^OK')
  } catch { return \$false }
}

function Run-CondaTorchDML([string]\$script, [string[]]\$args) {
  if (-not (Test-Path \$CondaExe)) {
    throw "Conda executable not found at \$CondaExe"
  }
  & \$CondaExe run -n \$TorchEnv python \$script @args
  return \$LASTEXITCODE
}

# 1) Prefer WSL Ubuntu-24.04 if ROCm GPU agent is visible
\$distro = Get-FirstExistingDistro \$PreferredDistros
if (Test-WSLROCm \$distro) {
  Write-Host "[WSL/\$distro] ROCm GPU agent detected — running inside WSL" -ForegroundColor Green
  \$wslPath = Convert-PathToWSL (Resolve-Path \$Script).Path
  \$argline = (\$Args -join ' ')
  \$cmd = "bash -lc `"python3 '\$wslPath' \$argline`""
  & wsl.exe -d \$distro --% \$cmd
  exit \$LASTEXITCODE
}

# 2) Try torch-directml (Miniforge Py 3.11)
if (Test-CondaTorchDML) {
  Write-Host "[Windows] torch-directml (Miniforge Py 3.11) — running on DirectML" -ForegroundColor Green
  \$code = Run-CondaTorchDML (Resolve-Path \$Script).Path \$Args
  exit \$code
}

# 3) Fallback: ONNX Runtime (DirectML) on Python 3.13
\$py = Ensure-OnnxVenv \$OnnxVenv
Write-Host "[Windows] Using ONNX Runtime (DirectML) on Python 3.13" -ForegroundColor Yellow
& \$py (Resolve-Path \$Script).Path @Args
exit \$LASTEXITCODE
"@
$launcher | Out-File -Encoding ASCII $launcherPath
Ok "Wrote $launcherPath"

# Ensure PATH includes ~/.bin
if (-not (($env:PATH -split ';') -contains $WinBin)) {
  Step "Add $WinBin to PATH"
  setx PATH "$env:PATH;$WinBin" | Out-Null
  Warn "Open a NEW PowerShell window to pick up the PATH change."
}

# ---------------- 3) Tier-2: Miniforge + torch-directml (Py 3.11) -------------
Step "Install Miniforge (if missing)"
if (!(Test-Path $CondaRoot)) {
  $url = "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe"
  $tmp = Join-Path $env:TEMP "Miniforge3.exe"
  Invoke-WebRequest $url -OutFile $tmp
  Start-Process $tmp -ArgumentList "/InstallationType=JustMe","/AddToPath=1","/RegisterPython=0","/S","/D=$CondaRoot" -Wait
  Ok "Miniforge installed"
} else {
  Info "Miniforge already present at $CondaRoot"
}

Step "Create/Update Py 3.11 env with torch-directml"
& $CondaExe env list | Out-Null
$exists = (& $CondaExe env list) -match ("^" + [regex]::Escape($TorchEnv) + "\s")
if (-not $exists) {
  & $CondaExe create -y -n $TorchEnv python=3.11
}
& $CondaExe run -n $TorchEnv python -m pip install --upgrade pip
& $CondaExe run -n $TorchEnv pip install torch-directml
Ok "torch-directml environment ready: $TorchEnv"

# ---------------- 4) Tier-3: ONNX Runtime DML (Py 3.13 venv) ------------------
Step "Create Windows Python 3.13 venv for ONNX Runtime (DirectML)"
$pyExe = Join-Path $OnnxVenv "Scripts\python.exe"
if (-not (Test-Path $pyExe)) {
  py -3.13 -m venv $OnnxVenv
}
& $pyExe -m pip install --upgrade pip
& $pyExe -m pip install --upgrade onnxruntime-directml onnxruntime-genai-directml
Ok "ONNX Runtime DML venv ready: $OnnxVenv"

# ---------------- 5) Ubuntu bootstrap (inside WSL 24.04) ----------------------
Step "Write Ubuntu bootstrap scripts and run"
$bootstrap = @'
#!/usr/bin/env bash
set -euo pipefail
phase(){ echo; echo "=== $* ==="; echo; }

phase "System info"
uname -a || true
. /etc/os-release
echo "OS: $PRETTY_NAME"

phase "Ensure ~/.bin exists"
mkdir -p "$HOME/.bin"

phase "Write /etc/wsl.conf (systemd, user, interop, resolv)"
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true

[user]
default=%USER%

[network]
generateResolvConf=true

[interop]
appendWindowsPath=false
EOF
sudo sed -i "s/%USER%/$USER/g" /etc/wsl.conf

phase "Base dev toolchain"
sudo apt update
sudo apt -y install build-essential git curl zip unzip jq tree ripgrep fd-find \
  python3 python3-venv python3-pip pipx cmake ninja-build pkg-config htop \
  openssh-client docker.io docker-compose-plugin

# Add pipx to PATH for interactive shells
if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
pipx ensurepath >/dev/null 2>&1 || true
pipx install uv || true

# Docker group (Docker Desktop + WSL integration recommended)
sudo usermod -aG docker "$USER" || true

phase "ROCm tools (Ubuntu 24.04) — gpu_probe depends on rocminfo"
# Note: ROCm-on-WSL GPU agent visibility on 24.04 may be pending upstream support
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/rocm-6.4.2.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rocm-6.4.2.gpg] https://repo.radeon.com/rocm/apt/6.4.2 noble main" \
  | sudo tee /etc/apt/sources.list.d/rocm-6.4.2.list
sudo apt update
sudo apt -y install rocminfo hip-runtime-amd rocm-hip-runtime rocm-hip-libraries rocm-utils || true

phase "Drop gpu_probe.sh"
cat > "$HOME/.bin/gpu_probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "== /dev/dxg =="
if [ -e /dev/dxg ]; then ls -l /dev/dxg; else echo "MISSING: /dev/dxg"; fi
echo
echo "== rocminfo (first 80 lines) =="
if command -v rocminfo >/dev/null 2>&1; then
  rocminfo | sed -n '1,80p' || true
  echo
  echo "== Agent summary =="
  rocminfo | awk '/^Agent /{print} /Device Type:/{print}' || true
else
  echo "rocminfo not installed."
fi
EOF
chmod +x "$HOME/.bin/gpu_probe.sh"

phase "All done (Ubuntu). Try: ~/.bin/gpu_probe.sh"
'@

# Write and run bootstrap in WSL
wsl -d Ubuntu-24.04 -- bash -lc "mkdir -p ~/.bin && printf %s @'$bootstrap' > ~/.bin/bootstrap_dev.sh && chmod +x ~/.bin/bootstrap_dev.sh && ~/.bin/bootstrap_dev.sh"

# ---------------- 6) Restart WSL to apply config ------------------------------
Step "Restart WSL to apply systemd and settings"
/Windows/System32/wsl.exe --shutdown | Out-Null
Ok "WSL shut down. Reopen Ubuntu-24.04 from Windows Terminal to start with systemd."

# ---------------- 7) Final guidance ----------------
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Magenta
Write-Host "  • Open a NEW PowerShell window so PATH includes $WinBin"
Write-Host "  • Launch Ubuntu-24.04 and run: ~/.bin/gpu_probe.sh" -ForegroundColor Gray
Write-Host "  • Use the smart launcher:" -ForegroundColor Gray
Write-Host "      run-accelerated.ps1 C:\path\to\your_script.py --flags" -ForegroundColor Gray
Write-Host "    (It prefers WSL ROCm GPU agent; else torch-directml (Py 3.11); else ORT DML (Py 3.13))" -ForegroundColor Gray
Ok "All set 🎉"
