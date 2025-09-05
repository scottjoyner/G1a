#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "\033[1;35m[container-launcher]\033[0m $*"; }

# Ensure we're in WSL and docker is available
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "Run this from WSL."
  exit 1
fi
command -v docker >/dev/null || { echo "Docker not found in WSL."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || true

# Try to use HIP in a container (WSL GPU device is /dev/dxg)
if [ -e /dev/dxg ]; then
  log "/dev/dxg present. Trying ROCm container…"
  set +e
  docker compose --profile rocm build
  docker compose --profile rocm run --rm trainer
  RC=$?
  set -e
  if [ $RC -eq 0 ]; then
    log "Container (HIP) path succeeded."
    exit 0
  else
    log "Container (HIP) path failed with code $RC. Falling back to Windows DirectML."
  fi
else
  log "No /dev/dxg in WSL; cannot use GPU in container. Falling back to Windows DirectML."
fi

# Fallback to Windows DirectML runner
WIN_PS="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
SCRIPT_WIN="$(wslpath -w "$(pwd)/windows_dml.ps1")"
REQ_WIN="$(wslpath -w "$(pwd)/requirements_dml.txt")"
PROJ_WIN="$(wslpath -w "$(pwd)")"

"$WIN_PS" -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_WIN" `
  -ProjectDir "$PROJ_WIN" `
  -EnvPath "$Env:USERPROFILE\dml-run" `
  -Requirements "$REQ_WIN" `
  -TrainArgs ""
