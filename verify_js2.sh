echo '=== main.dart.js: count chấm công ==='
docker exec zkteco_api grep -c -F 'chấm công' /app/wwwroot/main.dart.js
echo '=== part.js: count chấm công ==='
docker exec zkteco_api grep -c -F 'chấm công' /app/wwwroot/main.dart.js_1.part.js
echo '=== part.js: Duyệt chấm công ==='
docker exec zkteco_api grep -c -F 'Duyệt chấm công' /app/wwwroot/main.dart.js_1.part.js
echo '=== part.js: corrupted Duy?t (literal) ==='
docker exec zkteco_api grep -c -F 'Duy?t ch?m c?ng' /app/wwwroot/main.dart.js_1.part.js
echo '=== part.js samples ==='
docker exec zkteco_api grep -o -F -e 'Tên nhân viên' -e 'Hoãn duyệt' -e 'Tất cả loại' /app/wwwroot/main.dart.js_1.part.js | sort -u