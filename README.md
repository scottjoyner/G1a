# 🚀 ZBook Ultra AI Dev Environment

End-to-end setup for the **HP ZBook Ultra G1a (Ryzen AI)** (and similar
AMD laptops) to run containers, AI models, and GPU-accelerated
frameworks on both **WSL Ubuntu 24.04** and **Windows**.

This repo includes:

-   **`setup-zbook-ultra.ps1`** → one-shot installer (run in
    **PowerShell Admin**)\
-   **`run-accelerated.ps1`** → smart launcher for AI workloads
    (installed into `C:\Users\<you>\.bin`)\
-   **Ubuntu scripts** (`~/.bin/bootstrap_dev.sh`,
    `~/.bin/gpu_probe.sh`) → Linux bootstrap + GPU probe

------------------------------------------------------------------------

## 📂 Repository Layout

    .
    ├── setup-zbook-ultra.ps1   # Main installer script (PowerShell, run once as Admin)
    ├── README.md               # This file
    └── examples/               # Optional test scripts
        ├── dml_torch_test.py   # Test DirectML (PyTorch, Windows Py3.11 Miniforge)
        └── onnx_dml_test.py    # Test DirectML (ONNX Runtime, Windows Py3.13)

> During setup, additional scripts will be installed into your
> environment:
>
> -   Windows: `C:\Users\<you>\.bin\run-accelerated.ps1`
> -   Ubuntu: `~/.bin/bootstrap_dev.sh`, `~/.bin/gpu_probe.sh`

------------------------------------------------------------------------

## ⚙️ What the Installer Does

When you run `setup-zbook-ultra.ps1`, it:

1.  **Enables WSL2 & VirtualMachinePlatform** features.\

2.  **Installs Ubuntu 24.04** if missing.\

3.  Creates `%USERPROFILE%\.wslconfig` with sane defaults:

    ``` ini
    [wsl2]
    processors=12
    memory=12GB
    swap=16GB
    localhostForwarding=true
    ```

4.  Bootstraps **Ubuntu 24.04** with:

    -   `systemd` enabled (`/etc/wsl.conf`)
    -   dev tooling (`build-essential`, `git`, `cmake`, `pipx`, `uv`,
        etc.)
    -   Docker CLI (for Docker Desktop integration)
    -   ROCm userspace tools (`rocminfo`, HIP runtime)
    -   GPU probe script (`~/.bin/gpu_probe.sh`)

5.  Sets up **Windows acceleration tiers**:

    -   **Tier 1 (preferred):** WSL Ubuntu-24.04 with ROCm GPU agent\
    -   **Tier 2:** Miniforge Python 3.11 with `torch-directml`\
    -   **Tier 3:** Python 3.13 venv with `onnxruntime-directml` (+
        GenAI)\
    -   **Tier 4:** CPU fallback

6.  Installs **`run-accelerated.ps1`** launcher in
    `C:\Users\<you>\.bin`.

------------------------------------------------------------------------

## 🚦 Usage

### 1. Run the installer

Open **PowerShell as Administrator** and run:

``` powershell
.\setup-zbook-ultra.ps1
```

-   If this is the first WSL install, Ubuntu will launch and ask you to
    set a Linux username/password.\
-   After finishing, re-run the script once to complete bootstrapping.

### 2. Use the smart launcher

``` powershell
run-accelerated.ps1 C:\path\to\your_script.py --flag1 value
```

The launcher: 1. Runs in WSL (Ubuntu-24.04) if `rocminfo` shows a GPU
agent\
2. Otherwise, tries `torch-directml` (Windows Miniforge Py3.11)\
3. Otherwise, uses ONNX Runtime DirectML (Windows Py3.13)\
4. Otherwise, CPU fallback

### 3. Check GPU status in Ubuntu

``` bash
~/.bin/gpu_probe.sh
```

Shows `/dev/dxg` passthrough status and the first 80 lines of
`rocminfo`.

------------------------------------------------------------------------

## 🧪 Test Scripts

Included in `examples/`:

**PyTorch + DirectML test** (`dml_torch_test.py`)

``` python
import torch, torch_directml as dml
dev = dml.device()
x = torch.randn(2048, 2048, device=dev)
y = torch.randn(2048, 2048, device=dev)
print("Torch:", torch.__version__, "| Device:", dev)
print("OK:", (x@y).shape)
```

**ONNX Runtime + DirectML test** (`onnx_dml_test.py`)

``` python
import onnxruntime as ort
print("ORT:", ort.__version__, "| Providers:", ort.get_available_providers())
print("DML?", "DmlExecutionProvider" in ort.get_available_providers())
```

Run via the launcher:

``` powershell
run-accelerated.ps1 examples\dml_torch_test.py
run-accelerated.ps1 examples\onnx_dml_test.py
```

------------------------------------------------------------------------

## 📌 Notes & Best Practices

-   **Keep your code in the Linux filesystem** (`~/code`) for
    performance. Avoid `/mnt/c/...` paths.\
-   **Docker:** Use **Docker Desktop** with WSL2 integration for
    container workflows.\
-   **GPU on WSL:** As of now, ROCm GPU agent visibility on Ubuntu 24.04
    in WSL may depend on AMD driver updates. If not visible, launcher
    falls back to DirectML automatically.\
-   **Updating:** Re-run `setup-zbook-ultra.ps1` after driver or WSL
    updates --- it's safe to reapply.\
-   **Resource tuning:** Adjust `.wslconfig` values for your workload
    (processors/memory/swap).

------------------------------------------------------------------------

## ✅ Quick Checklist After Install

-   [ ] `wsl -l -v` shows **Ubuntu-24.04** with WSL2\
-   [ ] `~/.bin/gpu_probe.sh` runs without errors\
-   [ ] `run-accelerated.ps1` works from PowerShell\
-   [ ] `examples\dml_torch_test.py` runs on **DirectML** (if ROCm agent
    not present)

------------------------------------------------------------------------

💡 With this setup, you're future-proof: the same workflow will prefer
ROCm in WSL once AMD enables it fully on Ubuntu 24.04, but works today
with DirectML on Windows.
