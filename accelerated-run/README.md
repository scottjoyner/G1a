# accelerated-run (HIP-first, DirectML fallback)

This toolkit lets you train the same `train.py` with **ROCm/HIP in WSL** when available,
and automatically **fallback to DirectML on Windows** when not.

- **WSL ROCm container path**: `docker compose --profile rocm run --rm trainer`
- **WSL native HIP path**: `./launcher.sh` (uses HIP if available, otherwise kicks Windows fallback)
- **Windows DirectML path**: `windows_dml.ps1` (invoked automatically by the launchers when ROCm/HIP isn't present)

> Container GPU access on WSL with AMD ROCm is still evolving. This repo prefers HIP in WSL,
> but will gracefully fallback to DirectML on Windows so you always have acceleration.

## Prereqs

- Windows 11 + WSL2 with Ubuntu (22.04 or 24.04)
- Latest AMD Radeon/WSL driver (Adrenalin) on Windows
- Docker Desktop installed and WSL integration enabled
- `/dev/dxg` present inside WSL
- For ROCm in WSL (native or container), install AMD ROCm userspace packages
  (see AMD docs for `amdgpu-install --usecase=wsl,rocm --no-dkms`).

## Layout

```
accelerated-run/
├─ README.md
├─ .dockerignore
├─ docker-compose.yml
├─ Dockerfile.rocm
├─ container-launcher.sh
├─ launcher.sh
├─ windows_dml.ps1
├─ train.py
├─ requirements_rocm.txt
├─ requirements_dml.txt
└─ .env.example
```

## Quick start (container HIP path)

From WSL in this folder:

```bash
# build (pulls a ROCm + PyTorch base image)
docker compose --profile rocm build

# run with GPU (HIP) inside container; mounts the repo at /workspace
docker compose --profile rocm run --rm trainer
```

If the container exits complaining about HIP/GPU not available on your setup, use the **universal launcher**:

```bash
# Try HIP (native) first; if not viable, launches Windows DirectML automatically
./container-launcher.sh
```

## Quick start (native HIP path)

```bash
./launcher.sh
```

This tries ROCm/HIP **inside WSL (no container)**. If HIP isn’t available, it will call the Windows DirectML fallback.

## Windows DirectML only

From Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
# Run the helper to create a DirectML venv and start train.py:
& "$PWD\windows_dml.ps1"
```

## Caching

Hugging Face cache is set to `~/.cache/huggingface` (WSL) by default and mounted into the container at `/opt/hf`.
You can override in `.env`.

## Notes

- The ROCm container uses the image tag validated for ROCm 6.4 on Ubuntu 24.04 with PyTorch 2.5/2.6.
- On some systems, ROCm in WSL containers may still be limited. If you don’t see a GPU in the container,
  the launchers will run the **DirectML** path so you can work productively today.
