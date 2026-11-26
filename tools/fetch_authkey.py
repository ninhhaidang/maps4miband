"""Fetch Mi Fitness bound devices on every IDC using AstroBox's saved Xiaomi session and store each
device's auth key (detail.encrypt_key) in the macOS Keychain. Never prints a key.

Port of fetch_mi_bound_devices / mi_service_call_encrypted from AstroBox-NG-Module-Account
(AGPL-3.0), branch fix/xiaomi-bound-devices-all-idc.

Usage: python3 -I fetch_authkey.py
Read a key later: security find-generic-password -s maps4miband-authkey -a <MAC> -w
"""
import base64, hashlib, json, os, random, subprocess, sys, time, urllib.parse, urllib.request

CRED = os.path.expanduser("~/Library/Application Support/moe.astralsight.astrobox/accounts/xiaomi_credentials_v1.json")
HOSTS = ["hlth.io.mi.com", "sg.hlth.io.mi.com", "de.hlth.io.mi.com", "ru.hlth.io.mi.com", "us.hlth.io.mi.com", "i2.hlth.io.mi.com"]
PATH = "/app/v1/source/get_source_list"
UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)"
KEYCHAIN_SERVICE = "maps4miband-authkey"

b64e = lambda b: base64.b64encode(b).decode()
b64d = base64.b64decode


def rc4(key: bytes):
    s = list(range(256)); j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) % 256; s[i], s[j] = s[j], s[i]
    i = j = 0
    def stream(data: bytes) -> bytes:
        nonlocal i, j
        out = bytearray()
        for c in data:
            i = (i + 1) % 256; j = (j + s[i]) % 256; s[i], s[j] = s[j], s[i]
            out.append(c ^ s[(s[i] + s[j]) % 256])
        return bytes(out)
    stream(bytes(1024))  # Xiaomi drops the first 1024 keystream bytes
    return stream


def signature(path, signed_nonce, params):
    raw = "&".join(["POST", path] + [f"{k}={params[k]}" for k in sorted(params)] + [signed_nonce])
    return b64e(hashlib.sha1(raw.encode()).digest())


def call(tok, host, plain):
    nonce = b64e(os.urandom(8) + (int(time.time() * 1000) // 60000).to_bytes(4, "big"))
    signed_nonce = b64e(hashlib.sha256(b64d(tok["ssecurity"]) + b64d(nonce)).digest())
    params = dict(plain, rc4_hash__=signature(PATH, signed_nonce, plain))
    enc = rc4(b64d(signed_nonce))
    params = {k: b64e(enc(params[k].encode())) for k in sorted(params)}
    params["signature"] = signature(PATH, signed_nonce, params)
    params["_nonce"] = nonce
    cookie = "; ".join([f"sdkVersion=accountsdk-18.8.15", "locale=en_us"]
                       + [f"{c}={tok[f]}" for c, f in (("deviceId", "device_id"), ("userId", "user_id"), ("cUserId", "c_user_id")) if tok.get(f, "").strip()]
                       + [f"serviceToken={tok['service_token']}"])
    tag = host.removesuffix(".hlth.io.mi.com") if host != "hlth.io.mi.com" else "cn"
    req = urllib.request.Request(f"https://{host}{PATH}", data=urllib.parse.urlencode(params).encode(), method="POST",
                                 headers={"User-Agent": UA, "region_tag": tag, "HandleParams": "true", "Cookie": cookie,
                                          "Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=15) as r:
        body = r.read().decode().strip().strip('"')
    return json.loads(rc4(b64d(signed_nonce))(b64d(body)).decode("utf-8", "replace"))


def main():
    tok = json.load(open(CRED))
    found = {}
    for host in HOSTS:
        try:
            resp = call(tok, host, {"data": json.dumps({"page_size": 50, "status": 1}, separators=(",", ":"))})
        except Exception as e:
            print(f"{host}: lỗi {type(e).__name__}: {str(e)[:120]}")
            continue
        lst = (resp.get("result") or {}).get("list") or []
        print(f"{host}: code={resp.get('code')} {resp.get('message')!r}, {len(lst)} thiết bị")
        for d in lst:
            found.setdefault(d.get("identifier"), d)
    if not found:
        sys.exit("Không thấy thiết bị nào trên mọi máy chủ.")
    for d in found.values():
        det = d.get("detail") or {}
        mac, key = det.get("mac", ""), det.get("encrypt_key", "")
        print(f"- {d.get('name')} | model={d.get('model')} | mac={mac} | auth key: {'có, ' + str(len(key)) + ' ký tự' if key else 'KHÔNG CÓ'}")
        if key and mac:
            old = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", mac, "-w"],
                                 capture_output=True, text=True).stdout.strip()
            if old:
                print(f"  → so với key đã lưu: {'GIỐNG' if old == key else 'KHÁC (key đã đổi)'}")
            # shortcut: the key is briefly visible in this Mac's process list as an argument to `security`
            subprocess.run(["security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", mac, "-w", key], check=True)
            print(f"  → đã lưu vào Keychain (service={KEYCHAIN_SERVICE}, account={mac})")


if __name__ == "__main__":
    main()
