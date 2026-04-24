#!/bin/sh
cd /app/wwwroot/stores/demo/uploads/face-registrations/
for f in 9710c8ca-91c0-45e3-bcc7-566acf316e3e 40c3b151-4d2f-4937-8083-f41ec57986ce 7f01983a-fdae-4a51-a05f-439f761c3b4e 94c0d524-ae48-4921-b860-13e5699c28cd cf0a9f79-508d-4209-b3d3-6db71fb500a3 6b6c4ea1-31e7-43e4-925f-d4dce88af11e 46b2bc12-bf0b-4943-ba5e-fe02adecf5c9 b6b55ef5-d912-4521-a648-5d9cc1ee319c 547e1819-6542-4079-8d01-81a85b512fab cb39c20e-414a-4fcf-abd5-fb2c8d668c28; do
  if [ -f "$f.jpg" ]; then echo "OK: $f"; else echo "MISS: $f"; fi
done
