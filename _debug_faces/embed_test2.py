import numpy as np
import onnxruntime as ort
from PIL import Image

REC = "/tmp/w600k_mbf.onnx"
DET = "/tmp/ultraface.onnx"

rec = ort.InferenceSession(REC)
det = ort.InferenceSession(DET)
in_rec = rec.get_inputs()[0].name
in_det = det.get_inputs()[0].name

DET_W, DET_H = 320, 240

def softnms_best(boxes, scores, img_w, img_h, thresh=0.7):
    best = None
    for i, s in enumerate(scores):
        if s < thresh:
            continue
        if best is None or s > best[0]:
            x1, y1, x2, y2 = boxes[i]
            best = (s, x1 * img_w, y1 * img_h, x2 * img_w, y2 * img_h)
    return best

def detect(pil):
    img = pil.resize((DET_W, DET_H))
    arr = np.asarray(img, dtype=np.float32)
    arr = (arr - 127.0) / 128.0
    arr = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32)
    scores, boxes = det.run(None, {in_det: arr})
    # scores [1,N,2], boxes [1,N,4]
    s = scores[0, :, 1]  # face prob
    b = boxes[0]
    return softnms_best(b, s, pil.width, pil.height)

def embed(pil, mode="BGR"):
    # Detect and crop face
    face = detect(pil)
    if face is not None:
        _, x1, y1, x2, y2 = face
        # Expand 5%
        w, h = x2 - x1, y2 - y1
        x1 = max(0, int(x1 - 0.05 * w))
        y1 = max(0, int(y1 - 0.05 * h))
        x2 = min(pil.width, int(x2 + 0.05 * w))
        y2 = min(pil.height, int(y2 + 0.05 * h))
        pil = pil.crop((x1, y1, x2, y2))
        face_size = f"{x2-x1}x{y2-y1}"
    else:
        face_size = "NONE"
    pil = pil.resize((112, 112))
    arr = np.asarray(pil, dtype=np.float32)
    if mode == "BGR":
        arr = arr[:, :, ::-1]
    arr = (arr - 127.5) / 127.5
    arr = np.transpose(arr, (2, 0, 1))[None, ...].astype(np.float32).copy()
    out = rec.run(None, {in_rec: arr})[0][0]
    out = out / (np.linalg.norm(out) + 1e-9)
    return out, face_size

paths = {
    "ref_Linh":  "/tmp/r1.jpg",
    "test_Thao": "/tmp/t1.jpg",
    "test_Linh": "/tmp/t2.jpg",
}
imgs = {k: Image.open(v).convert("RGB") for k, v in paths.items()}
for mode in ("RGB", "BGR"):
    embs = {}
    for k, v in imgs.items():
        e, fs = embed(v, mode)
        embs[k] = e
        print(f"[{mode}] {k}: detected face {fs}")
    a = float(np.dot(embs["test_Linh"], embs["ref_Linh"]))
    b = float(np.dot(embs["test_Thao"], embs["ref_Linh"]))
    print(f"[{mode}]  Linh->Linh ref = {a:.3f}   Thao->Linh ref = {b:.3f}")
    print()
