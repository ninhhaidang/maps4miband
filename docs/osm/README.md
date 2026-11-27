# OpenStreetMap: đường xung quanh tuyến (#15)

[`overpass-nguyen-trai.json`](overpass-nguyen-trai.json) là phản hồi nguyên văn của Overpass ngày 2026-11-27 cho
40 điểm của tuyến fixture Vietmap (`../vietmap/route-motorcycle-nguyen-trai.json`), cùng truy vấn app gửi
(`Overpass.streets` trong `ios/Navigator`):

```
[out:json][timeout:180];way["highway"](around:150,<lat,lon của từng điểm, 5 chữ số>);out tags geom;
```

POST tới `https://overpass-api.de/api/interpreter`, thân `data=<truy vấn>`. 300 way, 175 KB; app giữ 202 (bỏ
`footway`, `steps`, `pedestrian`, `cycleway`, `proposed`).

Lấy lại: `curl -A "Maps4MiBand/0.1" --data-urlencode "data@query.txt" https://overpass-api.de/api/interpreter`.

- Không có User-Agent riêng (curl mặc định) → **406**.
- Máy chủ đầy → **502** "at capacity", thử lại sau vài chục giây (lần này được ở lượt thứ ba).
- Một truy vấn 2 điểm cũng mất ~34 s: phần lớn là xếp hàng, không phải kích thước.
