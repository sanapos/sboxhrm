"""Minimal InsightFace embedding sidecar.

Receives an image (multipart upload), returns the 512-d L2-normalized ArcFace
embedding using the buffalo_l pipeline (SCRFD det_10g + 5pt alignment + R50).
The .NET API calls this to compare faces correctly — C# equivalent would
require re-implementing SCRFD decoding + Umeyama similarity transform.
"""
import os
import io
import logging
from typing import List

import numpy as np
import cv2
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from insightface.app import FaceAnalysis

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("face-sidecar")

MODEL_ROOT = os.environ.get("INSIGHTFACE_HOME", "/models")
os.environ["INSIGHTFACE_HOME"] = MODEL_ROOT
# insightface expects models at $INSIGHTFACE_HOME/models/buffalo_l/*.onnx
os.makedirs(f"{MODEL_ROOT}/models/buffalo_l", exist_ok=True)

app_fa = FaceAnalysis(
    name="buffalo_l",
    root=MODEL_ROOT,
    allowed_modules=["detection", "recognition"],
)
app_fa.prepare(ctx_id=-1, det_size=(640, 640))
log.warning("FaceAnalysis ready (det_10g + w600k_r50)")

api = FastAPI(title="face-sidecar")


def _decode(data: bytes):
    arr = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail="decode failed")
    return img


def _largest_face(faces):
    return max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))


@api.get("/health")
def health():
    return {"ok": True, "model": "buffalo_l (det_10g+w600k_r50)"}


@api.post("/embed")
async def embed(file: UploadFile = File(...)):
    data = await file.read()
    img = _decode(data)
    faces = app_fa.get(img)
    if not faces:
        return JSONResponse({"ok": False, "reason": "no_face"}, status_code=200)
    f = _largest_face(faces)
    e = f.normed_embedding.astype(float).tolist()
    return {
        "ok": True,
        "embedding": e,
        "bbox": [float(x) for x in f.bbox.tolist()],
        "detScore": float(f.det_score),
    }
