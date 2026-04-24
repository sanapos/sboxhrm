"""Compare server-like pipeline (no alignment) vs proper InsightFace (aligned) on
Linh refs + Linh probe + Thao probe, using w600k_r50. Decides whether alignment
is the missing piece."""
import numpy as np, cv2, os
from insightface.app import FaceAnalysis

MODEL_DIR = "/opt/zkteco/ZKTecoADMS.Api/wwwroot/models"
REF_DIR = "/tmp"
REFS = [f"ref_{x}.jpg" for x in [
    "6b6c4ea1-31e7-43e4-925f-d4dce88af11e",
    "46b2bc12-bf0b-4943-ba5e-fe02adecf5c9",
    "b6b55ef5-d912-4521-a648-5d9cc1ee319c",
    "547e1819-6542-4079-8d01-81a85b512fab",
    "cb39c20e-414a-4fcf-abd5-fb2c8d668c28",
]]
PROBES = [
    ("Thao (v1 red jersey)", "/tmp/v1.jpg"),
    ("Linh (v2 no shirt)",   "/tmp/v2.jpg"),
    ("Linh (v3 no shirt)",   "/tmp/v3.jpg"),
]

# Build pipeline with r50 + retinaface det_10g (need buffalo_l)
os.environ["HOME"] = "/root"
os.makedirs("/root/.insightface/models/buffalo_l", exist_ok=True)
for f in ["w600k_r50.onnx", "det_10g.onnx"]:
    dst = f"/root/.insightface/models/buffalo_l/{f}"
    if not os.path.exists(dst):
        os.symlink(f"{MODEL_DIR}/{f}", dst)

app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition"])
app.prepare(ctx_id=-1, det_size=(640, 640))

def get_emb(path):
    img = cv2.imread(path)
    faces = app.get(img)
    if not faces:
        print(f"  !! no face: {path}")
        return None
    f = max(faces, key=lambda x: (x.bbox[2]-x.bbox[0])*(x.bbox[3]-x.bbox[1]))
    e = f.normed_embedding
    return e

print("== Aligned InsightFace pipeline (R50 + RetinaFace + 5pt alignment) ==")
ref_embs = []
for r in REFS:
    e = get_emb(os.path.join(REF_DIR, r))
    if e is not None: ref_embs.append(e)
print(f"loaded {len(ref_embs)} refs")

for label, path in PROBES:
    e = get_emb(path)
    if e is None: continue
    cos = sorted([float(e @ r) for r in ref_embs], reverse=True)
    print(f"{label}: cos={[f'{c:.3f}' for c in cos]} top1={cos[0]:.3f} 2nd={cos[1]:.3f} mean={np.mean(cos):.3f}")
