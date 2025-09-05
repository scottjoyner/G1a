import onnxruntime as ort

print("ORT:", ort.__version__, "| Providers:", ort.get_available_providers())
print("DML?", "DmlExecutionProvider" in ort.get_available_providers())
