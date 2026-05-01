#!/bin/bash
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT column_name FROM information_schema.columns WHERE table_name='Employees' AND column_name='ContractEndDate';"
echo "API logs (last 20):"
docker logs zkteco_api --tail=20
