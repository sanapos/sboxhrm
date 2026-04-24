import numpy as np
import onnxruntime as ort
from PIL import Image

REC = "/opt/zkteco/ZKTecoADMS.Api/wwwroot/models/w600k_r50.onnx"
DET = "/tmp/ultraface.onnx"

rec = ort.InferenceSession(REC, providers=["CPUExecutionProvider"])
det = ort.InferenceSession(DET, providers=["CPUExecutionProvider"])
in_rec = rec.get_inputs()[0].name
in_det = det.get_inputs()[0].name
print("Rec input shape:", rec.get_inputs()[0].shape)

def best_face(boxes, scores, w, h, thresh=0.7):
    best = None
    for i, s in enumerate(scores):
        if s < thresh: continue
        if best is None or s > best[0]:
            best = (s, boxes[i][0]*w, boxes[i][1]*h, boxes[i][2]*w, boxes[i][3]*h)
    return best

def detect(pil):
    img = pil.resize((320, 240))
    arr = np.asarray(img, dtype=np.float32)
    arr = (arr - 127.0) / 128.0
    arr = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32)
    scores, boxes = det.run(None, {in_det: arr})
    return best_face(boxes[0], scores[0,:,1], pil.width, pil.height)

def embed(pil):
    face = detect(pil)
    if face is not None:
        _, x1, y1, x2, y2 = face
        w, h = x2-x1, y2-y1
        x1 = max(0, int(x1 - 0.05*w)); y1 = max(0, int(y1 - 0.05*h))
        x2 = min(pil.width, int(x2 + 0.05*w)); y2 = min(pil.height, int(y2 + 0.05*h))
        pil = pil.crop((x1, y1, x2, y2))
    pil = pil.resize((112, 112))
    arr = np.asarray(pil, dtype=np.float32)
    arr = (arr - 127.5) / 127.5
    arr = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32).copy()
    out = rec.run(None, {in_rec: arr})[0][0]
    return out / (np.linalg.norm(out) + 1e-9)

paths = {"ref": "/tmp/r1.jpg", "Thao": "/tmp/t1.jpg", "Linh": "/tmp/t2.jpg"}
imgs = {k: Image.open(v).convert("RGB") for k, v in paths.items()}
embs = {k: embed(v) for k, v in imgs.items()}
print(f"Linh->ref = {float(np.dot(embs['Linh'], embs['ref'])):.3f}")
print(f"Thao->ref = {float(np.dot(embs['Thao'], embs['ref'])):.3f}")
