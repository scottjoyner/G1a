import torch, torch_directml as dml

dev = dml.device()
x = torch.randn(2048, 2048, device=dev)
y = torch.randn(2048, 2048, device=dev)
print("Torch:", torch.__version__, "| Device:", dev)
print("OK:", (x@y).shape)
