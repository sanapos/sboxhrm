#!/bin/bash
# Bật API LOCAL cho kiểm thử — build ra thư mục riêng (không khóa DLL của API đang chạy khác)
# và chạy ở cổng riêng, trỏ vào CSDL thử nghiệm (không bao giờ production).
#
#   SBOX_TEST_DB    tên CSDL PostgreSQL local (mặc định sbox_uidemo)
#   SBOX_API_PORT   cổng (mặc định 7199)
#
#   bash tools/local-test/start-api.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${SBOX_TEST_DB:-sbox_uidemo}"
PORT="${SBOX_API_PORT:-7199}"
OUT="${TMPDIR:-${TEMP:-/tmp}}/sbox-localtest-api"

cd "$ROOT/src/ZKTecoADMS.Api"
echo "==> Build API → $OUT"
dotnet build ZKTecoADMS.Api.csproj -c Debug -o "$OUT" -v q -nologo | grep -E " error |Build succeeded" || true

# Chuỗi kết nối lấy từ appsettings.Development.json, chỉ đổi tên CSDL.
CS=$(python -c "import json,re;c=json.load(open('appsettings.Development.json',encoding='utf-8-sig'))['ConnectionStrings']['DefaultConnection'];print(re.sub(r'(?i)database=[^;]*','Database=$DB',c))")
case "$CS" in *localhost*|*127.0.0.1*) ;; *) echo "Từ chối: chuỗi kết nối không phải localhost"; exit 2;; esac

export ASPNETCORE_ENVIRONMENT=Staging
export ConnectionStrings__DefaultConnection="$CS"
export ConnectionStrings__Redis="localhost:6379"
echo "==> API http://localhost:$PORT  (CSDL $DB)"
cd "$OUT"
exec dotnet ZKTecoADMS.Api.dll --urls "http://localhost:$PORT" --contentRoot "$ROOT/src/ZKTecoADMS.Api"
