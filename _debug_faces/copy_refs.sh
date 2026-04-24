#!/bin/sh
for id in 6b6c4ea1-31e7-43e4-925f-d4dce88af11e 46b2bc12-bf0b-4943-ba5e-fe02adecf5c9 b6b55ef5-d912-4521-a648-5d9cc1ee319c 547e1819-6542-4079-8d01-81a85b512fab cb39c20e-414a-4fcf-abd5-fb2c8d668c28
do
  docker cp zkteco_api:/app/wwwroot/stores/demo/uploads/face-registrations/$id.jpg /tmp/ref_$id.jpg
done
ls -lh /tmp/ref_*.jpg
