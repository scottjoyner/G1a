param(
  [string]$ProjectDir = "$env:USERPROFILE\accelerated-run",
  [string]$EnvPath    = "$env:USERPROFILE\dml-run",
  [string]$Requirements = "$env:USERPROFILE\accelerated-run\requirements_dml.txt",
  [string]$TrainArgs = ""
)

function Log($msg) { Write-Host "[windows_dml] $msg" -ForegroundColor Cyan }

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
  throw "Python launcher 'py' not found on Windows PATH."
}

if (-not (Test-Path $EnvPath)) {
  Log "Creating venv at $EnvPath"
  py -m venv $EnvPath
}
Log "Activating venv"
& "$EnvPath\Scripts\Activate.ps1"

python -m pip install --upgrade pip wheel setuptools
pip install torch-directml

if (Test-Path $Requirements) {
  Log "Installing requirements from $Requirements"
  pip install -r $Requirements
} else {
  Log "No requirements_dml.txt at $Requirements (continuing)"
}

$train = Join-Path $ProjectDir "train.py"
if (-not (Test-Path $train)) {
  throw "train.py not found at $train"
}

$env:BACKEND = "dml"
Log "Running train.py with DirectML"
python $train $TrainArgs
