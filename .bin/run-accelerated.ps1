param(
  [Parameter(Mandatory=$true)][string]$Script,  # Path to your Python script (Windows path OK)
  [string[]]$Args
)

# ---------------- Config ----------------
$PreferredDistros = @("Ubuntu-24.04","Ubuntu")
$OnnxVenv   = Join-Path $env:USERPROFILE "venvs\onnx-dml-313"  # Py 3.13 venv
$Py313Exe   = "py"                                             # Python launcher
$CondaRoot  = Join-Path $env:USERPROFILE "miniforge3"          # Miniforge root
$CondaExe   = Join-Path $CondaRoot "Scripts\conda.exe"
$TorchEnv   = "ai-dml-py311"                                   # Py 3.11 env name

# ---------------- Helpers ----------------
function Convert-PathToWSL($winPath) {
  if ($winPath -match '^[A-Za-z]:\\') {
    $drive = $winPath.Substring(0,1).ToLower()
    $rest  = $winPath.Substring(2) -replace '\\','/'
    return "/mnt/$drive/$rest"
  } else {
    return $winPath -replace '\\','/'
  }
}

function Get-FirstExistingDistro([string[]]$names) {
  try {
    $list = wsl.exe -l -q | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($n in $names) { if ($list -contains $n) { return $n } }
    return $null
  } catch { return $null }
}

function Test-WSLROCm([string]$distro) {
  if (-not $distro) { return $false }
  try {
    # print 'Device Type: GPU' if present
    $cmd = "bash -lc `"command -v rocminfo >/dev/null 2>&1 && rocminfo | awk '/Agent/{p=1} p && /Device Type:/{print; exit}' || true`" 
    $out = & wsl.exe -d $distro --% $cmd
    return ($out -match 'Device Type:\s+GPU')
  } catch { return $false }
}

function Ensure-OnnxVenv([string]$venvPath) {
  $python = Join-Path $venvPath "Scripts\python.exe"
  if (-not (Test-Path $python)) {
    Write-Host "[Windows] Creating venv for ONNX Runtime (DirectML) @ $venvPath" -ForegroundColor Cyan
    & $Py313Exe -3.13 -m venv $venvPath
  }
  Write-Host "[Windows] Ensuring onnxruntime-directml is installed" -ForegroundColor Cyan
  & $python -m pip install --upgrade pip
  & $python -m pip install --upgrade onnxruntime-directml onnxruntime-genai-directml 2>$null
  return $python
}

function Test-CondaTorchDML() {
  if (-not (Test-Path $CondaExe)) { return $false }
  try {
    $ok = & $CondaExe run -n $TorchEnv python - << 'PY'
try:
    import torch, torch_directml  # noqa: F401
    print("OK")
except Exception as e:
    print("ERR", e)
PY
    return ($ok -match '^OK')
  } catch { return $false }
}

function Run-CondaTorchDML([string]$script, [string[]]$args) {
  if (-not (Test-Path $CondaExe)) {
    throw "Conda executable not found at $CondaExe"
  }
  & $CondaExe run -n $TorchEnv python $script @args
  return $LASTEXITCODE
}

# ---------------- Main flow ----------------
# 1) Prefer WSL Ubuntu-24.04 with ROCm GPU agent
$distro = Get-FirstExistingDistro $PreferredDistros
if (Test-WSLROCm $distro) {
  Write-Host "[WSL/$distro] ROCm GPU agent detected — running inside WSL" -ForegroundColor Green
  $wslPath = Convert-PathToWSL (Resolve-Path $Script).Path
  $argline = ($Args -join ' ')
  $cmd = "bash -lc `"python3 '$wslPath' $argline`""
  & wsl.exe -d $distro --% $cmd
  exit $LASTEXITCODE
}

# 2) Try torch-directml in Miniforge Py 3.11
if (Test-CondaTorchDML) {
  Write-Host "[Windows] torch-directml (Miniforge Py 3.11) — running on DirectML" -ForegroundColor Green
  $code = Run-CondaTorchDML (Resolve-Path $Script).Path $Args
  exit $code
}

# 3) Fallback: ONNX Runtime DirectML on Python 3.13 venv
$py = Ensure-OnnxVenv $OnnxVenv
Write-Host "[Windows] Using ONNX Runtime (DirectML) on Python 3.13" -ForegroundColor Yellow
& $py (Resolve-Path $Script).Path @Args
exit $LASTEXITCODE
