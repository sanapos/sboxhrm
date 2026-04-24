import sys
import numpy as np
import onnxruntime as ort
from PIL import Image

MODEL = "/tmp/w600k_mbf.onnx"
sess = ort.InferenceSession(MODEL)
in_name = sess.get_inputs()[0].name

def embed(path, mode):
    img = Image.open(path).convert("RGB").resize((112, 112))
    arr = np.asarray(img, dtype=np.float32)
    if mode == "BGR":
        arr = arr[:, :, ::-1]
    arr = (arr - 127.5) / 127.5
    arr = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32).copy()
    out = sess.run(None, {in_name: arr})[0][0]
    out = out / (np.linalg.norm(out) + 1e-9)
    return out

def cos(a, b):
    return float(np.dot(a, b))

ref = "/tmp/r1.jpg"          # Linh male ref
t_thao = "/tmp/t1.jpg"       # Thao female
t_linh = "/tmp/t2.jpg"       # Linh male

for mode in ("RGB", "BGR"):
    e_ref = embed(ref, mode)
    e_thao = embed(t_thao, mode)
    e_linh = embed(t_linh, mode)
    print(f"[{mode}]  Linh->Linh ref cos = {cos(e_linh, e_ref):.3f}   Thao->Linh ref cos = {cos(e_thao, e_ref):.3f}")
