import os, sys, cv2, numpy as np
os.environ["INSIGHTFACE_HOME"]="/models"
from insightface.app import FaceAnalysis
app = FaceAnalysis(name="buffalo_l", root="/models", allowed_modules=["detection","recognition"])
app.prepare(ctx_id=-1, det_size=(640,640))
img = cv2.imread("/probes/v1.jpg")
print("image shape:", None if img is None else img.shape)
faces = app.get(img)
print("num faces:", len(faces))
if faces:
    f = max(faces, key=lambda x: (x.bbox[2]-x.bbox[0])*(x.bbox[3]-x.bbox[1]))
    print("bbox:", f.bbox.tolist())
    print("det_score:", f.det_score)
    print("embedding shape:", None if f.embedding is None else f.embedding.shape)
    print("normed shape:", None if f.normed_embedding is None else f.normed_embedding.shape)
    print("has recognizer:", hasattr(f, "embedding"))
    print("first 10 normed:", f.normed_embedding[:10].tolist() if f.normed_embedding is not None else None)
