"""Isolate Chromium's vendored protobuf from system dist-packages (Py3.13).

System protobuf (e.g. 7.x with upb) + Chromium third_party/protobuf/python
mix causes: AttributeError FrozenInstanceError / SystemError on import of
google._upb._message while running gen_on_device_proto_descriptors.py.
"""
import os
import sys

os.environ.setdefault("PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION", "python")

_cleaned = []
for p in sys.path:
    if not p:
        _cleaned.append(p)
        continue
    low = p.replace("\\", "/").lower()
    if "dist-packages" in low or "/site-packages" in low or low.endswith("site-packages"):
        continue
    _cleaned.append(p)
sys.path[:] = _cleaned
