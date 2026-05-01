#!/bin/bash
which python3
docker cp zkteco_api:/app/ZKTecoADMS.Api.dll /tmp/api.dll
python3 -c "
data = open('/tmp/api.dll','rb').read()
print('Vang khong phep:', 'V\u1eafng kh\u00f4ng ph\u00e9p'.encode('utf-16-le') in data)
print('Nghi le        :', 'Ngh\u1ec9 l\u1ec5'.encode('utf-16-le') in data)
print('Nghi phep      :', 'Ngh\u1ec9 ph\u00e9p'.encode('utf-16-le') in data)
print('Di muon        :', '\u0110i mu\u1ed9n'.encode('utf-16-le') in data)
print('matchingHolid  :', b'm\x00a\x00t\x00c\x00h\x00i\x00n\x00g\x00H\x00o\x00l\x00i\x00d' in data)
"