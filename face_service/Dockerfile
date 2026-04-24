FROM python:3.10-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 build-essential g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install wheels in two passes so the insightface sdist has numpy+cython
# available at build time.
RUN pip install --no-cache-dir \
    numpy==1.26.4 \
    cython==3.0.10

RUN pip install --no-cache-dir \
    onnxruntime==1.19.2 \
    opencv-python-headless==4.10.0.84 \
    fastapi==0.115.0 \
    uvicorn[standard]==0.30.6 \
    python-multipart==0.0.9 \
    insightface==0.7.3

# Drop build toolchain to shrink image.
RUN apt-get purge -y --auto-remove build-essential g++ && rm -rf /var/lib/apt/lists/*

COPY app.py /app/app.py

ENV INSIGHTFACE_HOME=/models
EXPOSE 8000

CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
