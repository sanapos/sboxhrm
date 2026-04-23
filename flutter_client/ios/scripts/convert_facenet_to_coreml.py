#!/usr/bin/env python3
"""
Convert the ArcFace ONNX model used by the server (w600k_mbf.onnx,
512-dimensional MobileFaceNet backbone, same as InsightFace buffalo_sc/
buffalo_l MBF) to a CoreML `.mlpackage` so iOS can run it on the Neural
Engine / GPU without depending on `tflite_flutter`.

Inputs
------
  flutter_client/assets/w600k_mbf.onnx      (112x112x3 RGB, NCHW, normalized to [-1,1])

Outputs
-------
  flutter_client/ios/Runner/FaceNet.mlpackage

Run locally (macOS) or on Codemagic:
    pip install --quiet coremltools onnx onnxruntime
    python flutter_client/ios/scripts/convert_facenet_to_coreml.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ONNX_REL = "flutter_client/assets/w600k_mbf.onnx"
OUT_REL = "flutter_client/ios/Runner/FaceNet.mlpackage"


def main() -> int:
    # Resolve repo root: script lives in flutter_client/ios/scripts/
    here = Path(__file__).resolve()
    repo_root = here.parents[3]

    onnx_path = repo_root / ONNX_REL
    out_path = repo_root / OUT_REL

    if not onnx_path.exists():
        print(f"[convert] ERROR: ONNX model not found: {onnx_path}", file=sys.stderr)
        return 1

    # If a fresh .mlpackage already exists with a newer mtime, skip.
    if out_path.exists() and out_path.stat().st_mtime > onnx_path.stat().st_mtime:
        print(f"[convert] {out_path.name} is up to date; skipping.")
        return 0

    print(f"[convert] Converting {onnx_path} -> {out_path}")

    try:
        import coremltools as ct
        import onnx
    except ImportError as e:
        print(f"[convert] ERROR: missing dependency: {e}", file=sys.stderr)
        print("         pip install coremltools onnx", file=sys.stderr)
        return 2

    onnx_model = onnx.load(str(onnx_path))

    # Input spec: NCHW, (1, 3, 112, 112), values already in [-1, 1]. The
    # Swift side passes normalized Float32. Use ImageType so Xcode treats
    # the input as a VNImage-compatible tensor (faster on Neural Engine).
    # `scale` and `bias` below normalize 0..255 uint8 -> -1..1 Float32.
    # (mean = 127.5, std = 127.5)
    image_input = ct.ImageType(
        name="input",
        shape=(1, 3, 112, 112),
        color_layout=ct.colorlayout.RGB,
        scale=1.0 / 127.5,
        bias=[-1.0, -1.0, -1.0],
        channel_first=True,
    )

    ml_model = ct.convert(
        onnx_model,
        inputs=[image_input],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS15,
        compute_units=ct.ComputeUnit.ALL,   # Neural Engine + GPU + CPU
        compute_precision=ct.precision.FLOAT16,
    )

    ml_model.author = "ZKTecoADMS"
    ml_model.short_description = (
        "InsightFace w600k_mbf ArcFace 512-dim face embedding (MBF backbone)."
    )
    ml_model.input_description["input"] = "112x112 RGB face crop"
    # Output name from ArcFace MBF is typically 'fc1' or '683' depending
    # on export; leave as-is, Swift will pick the first output feature.

    if out_path.exists():
        import shutil
        shutil.rmtree(out_path, ignore_errors=True)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    ml_model.save(str(out_path))

    print(f"[convert] Saved {out_path}")
    print(f"[convert] Outputs: {[o.name for o in ml_model.output_description]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
