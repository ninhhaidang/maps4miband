# Màn hình vòng (Smart Band 11, 212×520)

Số đo cho bố cục dẫn đường (#13). Ô **?** là chưa đo trên vòng thật.

| Đo gì | Kết quả | Trong code |
|---|---|---|
| Cạnh dài bị che (px) | 0 | `SAFE.side = 0` (band/src/common/render.js) |
| Góc bo | bán kính ~100 px: hai đầu gần như nửa hình tròn (bảng dưới) | `SAFE.radius = 100`, `inset(y)` |
| Số đoạn vẽ mượt, cập nhật mỗi giây | ? | tuyến 700 m thường ~30–80 đoạn |
| Pin tụt sau 10 phút ở 50 / 100 / 200 đoạn | ? / ? / ? | |
| Tin nhắn interconnect lớn nhất nhận đủ | 16 KB (32 KB không tới) | tin dẫn đường hiện ~0.5 KB; 16 KB ≈ 2000 điểm, nên giới hạn đoạn là do vẽ chứ không do tin nhắn |
| Mẫu bố cục đã chọn (A / B / C) | A | A |

Góc bo cắt mất mỗi bên, ở hàng cách mép trên (mép dưới đối xứng), đọc từ ảnh trang thước chụp thẳng:

| hàng (px) | 0 | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 |
|---|---|---|---|---|---|---|---|---|---|---|
| bị cắt (px) | 91 | 59 | 41 | 29 | 20 | 13 | 8 | 4 | 2 | 0 |

Hệ quả: hàng mũi tên + khoảng cách (rộng tới ~172 px) bắt đầu từ y = 40; khung chỉ dẫn cao 170 px (`MAP_TOP`);
nhãn tên đường giữ cách mép dưới ≥ 28 px và lùi vào theo `inset` khi xuống gần đáy.

## Cách đo

Cài bản quick app mới (`cd band && npx aiot build`, Run app iOS, **Cài app lên vòng**), mở *Dẫn đường* trên vòng.

- **Mẫu bố cục**: đã chọn A (mũi tên + khoảng cách một hàng, chỉ dẫn 2 dòng, quãng còn lại); B (mũi tên to riêng
  một hàng, bỏ quãng còn lại) và C (khung thấp, chỉ dẫn 1 dòng) đã bỏ.
- **Thước**: giữ lâu trên màn hình dẫn đường để mở trang đo. Chú thích màu ở giữa ghi "hàng · cạnh".
  - Vạch ngang toàn chiều rộng mỗi 10 px từ mép trên và mép dưới: góc bo làm các vạch đầu ngắn đi; mỗi vạch mất
    bao nhiêu ở hai đầu cho ra `SAFE.radius`.
  - Vạch dọc mỗi 4 px từ hai cạnh dài, ở giữa màn hình: vạch đầu tiên hiện đủ = `SAFE.side`.
- **Thử tải**: chạm trang thước để chuyển sang 50 → 100 → 200 đoạn xám, vẽ lại mỗi giây. Xem có giật không,
  "chu kỳ chậm nhất" (gần 1000 ms là ổn), để 10 phút ghi pin tụt. Vuốt phải để quay lại.
- **Kích thước tin nhắn**: trong app iOS bấm **Thử tin nhắn N KB** nhiều lần (1, 2, 4 … 32 KB). Vòng hiện
  "Nhận đủ N KB" khi nhận trọn; "Tin nhắn hỏng" hoặc không đổi gì là quá cỡ. Dừng ở 32 KB vì một khung
  BandLink chỉ chứa dưới 64 KB; vòng nhận đủ 32 KB thì ghi "≥ 32 KB".

## Sau khi đo

Khi đã có số thử tải: xoá trang `pages/proto`
(cùng `onlongpress` trong `index.ux`), nút thử tin nhắn trong app iOS (tìm `shortcut:`).
