#!/usr/bin/env bash
set -euo pipefail

# WSL-native HIP launcher (no container), falls back to Windows DirectML

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PY_VER="${PY_VER:-python3}"
WSL_VENV="${WSL_VENV:-$PROJECT_DIR/.venv_wsl}"
WSL_REQ="${WSL_REQ:-$PROJECT_DIR/requirements_rocm.txt}"
TORCH_ROCM_INDEX="${TORCH_ROCM_INDEX:-https://download.pytorch.org/whl/rocm6.1}"

WIN_PS="${WIN_PS:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"
WIN_SCRIPT_WSL="${WIN_SCRIPT_WSL:-$PROJECT_DIR/windows_dml.ps1}"

log(){ echo -e "\033[1;36m[launcher]\033[0m $*"; }

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Run this from WSL."
  exit 1
fi

if [ ! -f "$PROJECT_DIR/train.py" ]; then
  echo "train.py not found in $PROJECT_DIR"
  exit 1
fi

if command -v rocminfo >/dev/null 2>&1 && [ -e /dev/dxg ]; then
  log "Trying HIP natively in WSL…"
  if [ ! -d "$WSL_VENV" ]; then
    "$PY_VER" -m venv "$WSL_VENV"
  fi
  source "$WSL_VENV/bin/activate"
  python -m pip install -U pip wheel setuptools
  if [ -f "$WSL_REQ" ]; then
    pip install -r "$WSL_REQ"
  fi
  pip install --index-url "$TORCH_ROCM_INDEX" torch torchvision torchaudio
  python - <<'PY'
import torch, sys
ok = torch.cuda.is_available()
print("[probe] HIP available:", ok)
sys.exit(0 if ok else 3)
PY
  if [ $? -eq 0 ]; then
    BACKEND=hip python "$PROJECT_DIR/train.py" ${@:-}
    exit 0
  fi
  log "HIP probe failed; falling back to Windows DirectML."
else
  log "ROCm tools or /dev/dxg missing; falling back to Windows DirectML."
fi

# Fallback to Windows DirectML runner
WIN_SCRIPT_WIN="$(wslpath -w "$WIN_SCRIPT_WSL")"
WIN_REQ_WIN="$(wslpath -w "$PROJECT_DIR/requirements_dml.txt")"
WIN_PROJ_WIN="$(wslpath -w "$PROJECT_DIR")"

"$WIN_PS" -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT_WIN" `
  -ProjectDir "$WIN_PROJ_WIN" `
  -EnvPath "$Env:USERPROFILE\dml-run" `
  -Requirements "$WIN_REQ_WIN" `
  -TrainArgs "$*"
