docker exec zkteco_api grep -c -F 'Duyệt chấm công' /app/wwwroot/main.dart.js
echo '--- corrupted (expect 0) ---'
docker exec zkteco_api grep -F 'Duy?t' /app/wwwroot/main.dart.js | head -c 50
echo
echo '--- correct samples ---'
docker exec zkteco_api grep -o -F -e 'Tên nhân viên' -e 'Trạng thái' -e 'Hoãn duyệt' /app/wwwroot/main.dart.js | sort -u