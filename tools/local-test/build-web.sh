#!/bin/bash
# Build Flutter web cho kiểm thử local (API qua proxy web_proxy.py cùng cổng).
#   SBOX_WEB_PORT   cổng web proxy (mặc định 8190)
#   FLUTTER         đường dẫn flutter (mặc định: flutter trong PATH)
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${SBOX_WEB_PORT:-8190}"
FLUTTER="${FLUTTER:-flutter}"
cd "$ROOT/flutter_client"
"$FLUTTER" build web --release --dart-define=API_BASE_URL="http://localhost:$PORT" --no-tree-shake-icons 2>&1 \
  | grep -E "Error|error:|Built" | head -20
sed -i "s#__API_BASE_URL__#http://localhost:$PORT#" build/web/config.js 2>/dev/null || true
echo "Xong: flutter_client/build/web (API qua http://localhost:$PORT)"
