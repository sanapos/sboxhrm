#!/bin/bash
TOKEN=$(curl -s http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"Admin@123"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token','') if d.get('data') else 'FAIL:'+str(d))")
echo "TOKEN_LEN=${#TOKEN}"
if [ ${#TOKEN} -gt 20 ]; then
  curl -s "http://localhost:7070/api/Assets/inventories" -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('isSuccess:', d.get('isSuccess'))
data=d.get('data',[])
print('data type:', type(data).__name__, 'count:', len(data) if isinstance(data,list) else 'N/A')
if isinstance(data,list):
  for i,x in enumerate(data[:3]):
    print(f'  [{i}]', {k:v for k,v in x.items() if k in ['id','name','status','totalAssets']})
else:
  print('data:', str(data)[:300])
"
else
  echo "Login failed: $TOKEN"
fi