import urllib.request, json, ssl
req = urllib.request.Request(
    "https://sbox.sana.vn/api/auth/AdminLogin",
    data=json.dumps({"userName": "sanapos.vn@gmail.com", "password": "123456aA@"}).encode(),
    headers={"Content-Type": "application/json"},
)
ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
try:
    r = urllib.request.urlopen(req, context=ctx)
    print("HTTP", r.status)
    print(r.read()[:400].decode())
except urllib.error.HTTPError as e:
    print("HTTP", e.code)
    print(e.read()[:400].decode())
