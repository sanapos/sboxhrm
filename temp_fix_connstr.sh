cd /opt/zkteco
sed -i 's/Database=ZKTecoIntegration/Database=ZKTecoADMS/g' docker-compose.yaml
docker restart zkteco_api
