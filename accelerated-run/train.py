import os, sys, time
import torch

BACKEND = os.getenv("BACKEND", "").lower()

def pick_device():
    if BACKEND == "hip":
        if not torch.cuda.is_available():
            print("[train] Requested HIP but no HIP device available.")
            sys.exit(3)
        return torch.device("cuda")

    if BACKEND == "dml":
        try:
            import torch_directml as dml
        except ImportError:
            print("[train] BACKEND=dml but torch-directml not installed.")
            sys.exit(4)
        return dml.device()

    if torch.cuda.is_available():
        return torch.device("cuda")
    try:
        import torch_directml as dml
        return dml.device()
    except Exception:
        pass
    return torch.device("cpu")

def main():
    dev = pick_device()
    print(f"[train] Using device: {dev}")

    n = 4096 if str(dev) != "cpu" else 1024
    x = torch.randn(n, n, device=dev)
    y = torch.randn(n, n, device=dev)

    t0 = time.time()
    z = x @ y
    try:
        torch.cuda.synchronize()
    except Exception:
        pass
    dt = time.time() - t0

    print(f"[train] Matmul result: {z.shape}  elapsed={dt:.3f}s")

if __name__ == "__main__":
    main()
