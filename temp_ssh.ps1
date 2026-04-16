$ErrorActionPreference = 'Continue'
$result = & 'C:\Program Files\PuTTY\plink.exe' -ssh root@103.133.224.176 -pw 'Linh@@3103' -hostkey 'SHA256:qelnSJl9f7g6rShZBymCYGY4fVZt54kLucoMQLw3g34' -batch 'docker ps --format "{{.Names}} {{.Status}}" && echo "---DB_CHECK---" && docker exec zkteco_db psql -U postgres -d ZKTecoADMS -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = '\''MobileAttendanceSettings'\'' ORDER BY ordinal_position;" && echo "---API_LOGS---" && docker logs zkteco_api --tail 30 2>&1 | tail -20' 2>&1
$result | ForEach-Object { $_.ToString() }
