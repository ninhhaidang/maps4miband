# Vietmap: kết quả kiểm tra (#5)

Kiểm tra ngày 2026-11-27 bằng key Trial, gọi thẳng `https://maps.vietmap.vn/api/...`. Kết luận: **dùng được Vietmap**.

## Điều khoản

- Trang đăng ký dẫn tới "Điều khoản sử dụng" là <https://maps.vietmap.vn/console/privacy-policy>, thực chất là
  *Vietmap Privacy Policy* (chính sách dữ liệu cá nhân). Không có điều khoản nào về việc hiển thị kết quả API trên
  bản đồ của bên khác hay trên thiết bị đeo, không bắt ghi nguồn (attribution) cho Route/Autocomplete.
- Tài liệu chính thức cho phép xử lý lại kết quả: *"You may implement caching or response filtering as appropriate."*
  (<https://maps.vietmap.vn/docs/map-api/overview/>, mục tích hợp backend). Với Autocomplete: *"Do not cache `ref_id`
  long-term … Resolve to `lat/lng` and store those."* (<https://maps.vietmap.vn/docs/assets/agents/search-geocoding.txt>).
- Phản hồi Route có trường `"license": "vietmap"` nhưng tài liệu không giải thích trường này hay kèm điều kiện gì.
- Kết luận: không có trích dẫn nào cho phép rõ ràng, nhưng cũng không tìm thấy điều nào cấm vẽ tuyến lên Apple MapKit hay đẩy chỉ dẫn lên vòng. Rủi ro còn lại: điều
  khoản hợp đồng không công bố; nếu cần chắc chắn thì hỏi maps.info@vietmap.vn.
- Lưu ý: Vietmap khuyên giữ *services key* ở backend. App này để mỗi người dùng nhập key của chính mình vào Keychain
  (dùng cá nhân, không phát hành), nên chấp nhận gọi thẳng từ iPhone.
- Hạn mức Trial: Route 500 lượt/ngày, Place 500/ngày, Autocomplete không giới hạn ngày (200/phút)
  (<https://maps.vietmap.vn/docs/map-api/console/usage-limitation/>).

## Xe máy có tránh cầu cạn/cao tốc không

So sánh `vehicle=car` với `vehicle=motorcycle` (tên đường lấy từ `street_name` của các bước):

| Tuyến | Ô tô | Xe máy | Đúng? |
| --- | --- | --- | --- |
| Ngã Tư Sở → Ngã Tư Vọng (VĐ2 trên cao) | "Cầu Cạn Trường Chinh" | Trường Chinh dưới đất, rồi Đại La | ✓ |
| Trung Hoà → An Khánh (VĐ3 trên cao + Đại lộ Thăng Long) | "Cầu Vượt Bắc Linh Đàm Mai Dịch", làn chính ĐL Thăng Long | Phạm Hùng dưới đất, ngõ Mễ Trì; trên ĐL Thăng Long chạy song song cách làn ô tô 40–70 m (đường gom) | ✓ |
| Cổ Nhuế → Linh Đàm (VĐ3) | lên bằng nhánh "ở bên phải", xuống ở "Đi Hà Đông", 15 phút | Phạm Văn Đồng → Phạm Hùng → Nguyễn Xiển dưới đất, 23 phút | ✓ |
| Linh Đàm → Phủ Lý (cao tốc Pháp Vân–Cầu Giẽ) | "Dẫn Vào Cao Tốc Cầu Giẽ" 44,9 km | Ngọc Hồi → Quốc lộ 1 | ✓ |
| Xã Đàn → Khương Thượng (ngõ) | 2,62 km, theo phố lớn | 2,19 km, đi Ngõ 180 Kim Hoa, Ngõ 72 Tôn Thất Tùng | ✓ |

Ngoài tuyến ngõ ở bảng, tuyến xe máy nào cũng chui ngõ khi ngắn hơn: Ngõ 36 Miếu Đầm, Ngõ 50 Mễ Trì Thượng (Trung Hoà),
Ngách 191A/38 Đại La (VĐ2), ngõ/ngách/hẻm 213 Giáp Nhất (fixture). Kết luận dựa trên tên đường và khoảng lệch hình
học, chưa đi thử thực địa.

## Fixture

[`route-motorcycle-nguyen-trai.json`](route-motorcycle-nguyen-trai.json) là phản hồi nguyên văn của Route v4
(không chứa key), tuyến 1,45 km ở Thanh Xuân/Đống Đa:

```
point=21.0020,105.8200  point=21.0060,105.8150  vehicle=motorcycle  heading=135
```

Có rẽ phải (2), chếch phải (1), **quay đầu (-8)** trên Nguyễn Trãi, bốn lần rẽ trái (-2) vào ngõ/ngách/hẻm, đích (4).

### `interval` lệch so với `points` — phải sửa khi parse

`interval` **không** trỏ đúng vào mảng `points` đã giải mã: polyline có thêm một điểm ở mỗi ranh giới giữa hai bước,
nên điểm thật của bước thứ `k` (đếm từ 0) là

```
index = instructions[k].interval[0] + k
```

Đã kiểm trên fixture (9/9 chỗ rẽ khớp với góc gãy của polyline, và khớp với tổng dồn `distance`) và trên 8 tuyến
khác (luôn có `instructions.last.interval[0] + (n - 1) == points.count - 1`). Parser nên kiểm đúng đẳng thức đó; nếu
thay vào đó `instructions.last.interval[0] == points.count - 1` thì Vietmap đã sửa lỗi, dùng `interval[0]` nguyên.

Các trường khác: `heading`/`last_heading` chỉ có giá trị ở bước đầu (trong fixture là 231/230.9), các bước sau là
0/null, nên không dùng để suy góc rẽ. Vòng xuyến không có trường số lối ra; số lối
ra chỉ nằm trong `text` (`"Tại vòng xoay, rẽ lối rẽ 2 vào đường …"`), lấy bằng regex `lối rẽ (\d+)`.

## Bảng `sign`

Tài liệu Vietmap chỉ liệt kê -3…6 (<https://maps.vietmap.vn/docs/assets/agents/routing.txt>); bảng đầy đủ nằm trong
một file Figma. Các mã còn lại theo quy ước GraphHopper mà Vietmap dùng, cột "Đã gặp" là đã thấy trong phản hồi thật.
Góc mũi tên theo bản Android (+ = phải, ±45/±90/±135); mới thêm: giữ làn ±30, quay đầu theo chiều của sign
(Android luôn 180, trên vòng trông như nhau). Câu chỉ dẫn = câu gốc + `" vào {street_name}"` khi `street_name` không rỗng.
Không dùng `text` của Vietmap vì viết thường và dịch sai (sign 3 → "rẽ phải ngay lập tức", sign 7 → "ở bên phải").

| sign | Loại | Câu gốc | Góc | Đã gặp |
| ---: | --- | --- | ---: | :---: |
| -98 | quay đầu (không rõ chiều) | Quay đầu | -180 | |
| -8 | quay đầu bên trái | Quay đầu | -180 | ✓ |
| -7 | giữ bên trái | Đi về bên trái | -30 | ✓ |
| -6 | ra khỏi vòng xuyến | Ra khỏi vòng xuyến | null | |
| -3 | rẽ gắt trái | Rẽ gắt trái | -135 | ✓ |
| -2 | rẽ trái | Rẽ trái | -90 | ✓ |
| -1 | chếch trái | Chếch trái | -45 | |
| 0 | đi tiếp (đổi tên đường) | Đi thẳng | 0 | ✓ |
| 1 | chếch phải | Chếch phải | 45 | ✓ |
| 2 | rẽ phải | Rẽ phải | 90 | ✓ |
| 3 | rẽ gắt phải | Rẽ gắt phải | 135 | ✓ |
| 4 | đến nơi | Đến nơi | null | ✓ |
| 5 | qua điểm dừng | Đã qua điểm dừng | null | |
| 6 | vòng xuyến | Vòng xuyến, lối ra thứ N (không có N: "Đi vào vòng xuyến") | null | ✓ |
| 7 | giữ bên phải | Đi về bên phải | 30 | ✓ |
| 8 | quay đầu bên phải | Quay đầu | 180 | |
| khác | không rõ | Đi tiếp | null | |

Bước đầu tiên (k = 0) là điểm xuất phát: câu "Xuất phát", góc null, như bản Android. Vòng xuyến để góc null vì
Vietmap không cho biết hướng ra. sign 0 xuất hiện rất nhiều (mỗi lần đổi tên đường); spec hiện rung cho mọi maneuver, việc có
bỏ rung cho sign 0 hay không để #6 quyết.

## Tìm kiếm

Autocomplete v4 (`display_type=1`, `focus` = vị trí hiện tại) rồi Place v4 (`refid`) để lấy `lat`/`lng`:

| Gõ | Kết quả đầu |
| --- | --- |
| `1 Đại Cồ Việt` | 1 Đường Đại Cồ Việt, Phường Bạch Mai ✓ |
| `ngõ 165 Cầu Giấy` | Ngõ 165 Cầu Giấy, Phường Cầu Giấy ✓ |
| `ngach 191A/38 dai la` (không dấu) | Ngách 191A/38 Đại La ở vị trí 2 ✓ |
| `ngo 36 mieu dam` (không dấu) | Ngõ 36 Miếu Đầm ✓ |
| `benh vien bach mai` | Bệnh Viện Bạch Mai, Đường Giải Phóng ✓ |
| `số 35 Hàng Bông` | 35 Phố Hàng Bông → Place v4 trả 21.03086, 105.84833 ✓ |
| `18 ngõ 81 Láng Hạ` | chỉ ra Ngõ 81 Láng Hạ (không có số nhà trong ngõ) ~ |
| `Hồ Gươm` | toàn POI quanh hồ, không có chính cái hồ ~ |

Kết luận: đủ tốt cho ô tìm kiếm. Số nhà trong ngõ thì rơi về đầu ngõ; trường hợp đó dùng tìm kiếm Apple
(dự phòng trong spec) hoặc nhập toạ độ. Mỗi lần chọn kết quả tốn thêm một lượt Place (hạn mức ở trên).

Fixture: [`autocomplete-benh-vien-bach-mai.json`](autocomplete-benh-vien-bach-mai.json) (`text=benh vien bach mai`,
`focus=21.0020,105.8200`) và [`place-benh-vien-bach-mai.json`](place-benh-vien-bach-mai.json) (Place v4 của kết quả
đầu). Không có kết quả thì Autocomplete trả `[]`; `refid` sai thì Place trả 404 rỗng; key sai thì 401. App chưa dùng
tìm kiếm Apple: kết quả trên đủ tốt.
