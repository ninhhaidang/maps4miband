# Màn hình vòng (Smart Band 11, 212×520)

Số đo cho bố cục dẫn đường (#13). Ô **?** là chưa đo trên vòng thật; code đang dùng số tạm ghi bên cạnh.

| Đo gì | Kết quả | Số tạm trong code |
|---|---|---|
| Cạnh dài bị che (px) | ? | `SAFE.side = 8` (band/src/common/render.js) |
| Góc bo cắt vào bao nhiêu hàng trên/dưới (px) | ? | `SAFE.corner = 40` |
| Số đoạn vẽ mượt, cập nhật mỗi giây | ? | tuyến 700 m thường ~30–80 đoạn |
| Pin tụt sau 10 phút ở 50 / 100 / 200 đoạn | ? / ? / ? | |
| Tin nhắn interconnect lớn nhất nhận đủ | 16 KB (32 KB không tới) | tin dẫn đường hiện ~0.5 KB; 16 KB ≈ 2000 điểm, nên giới hạn đoạn là do vẽ chứ không do tin nhắn |
| Mẫu bố cục đã chọn (A / B / C) | ? | A |

## Cách đo

Cài bản quick app mới (`cd band && npx aiot build`, Run app iOS, **Cài app lên vòng**), mở *Dẫn đường* trên vòng.

- **Mẫu bố cục**: chạm vào khung chỉ dẫn phía trên để đổi A → B → C. Chưa có tin từ điện thoại thì vòng hiện
  một khung mẫu (rẽ phải, câu chỉ dẫn 2 dòng, 2 điểm rẽ). Đeo thử, hoặc chạy thật rồi chạm để so.
  - A: mũi tên + khoảng cách một hàng, chỉ dẫn 2 dòng, quãng còn lại.
  - B: mũi tên to riêng một hàng, khoảng cách dưới, chỉ dẫn 2 dòng, bỏ quãng còn lại.
  - C: khung thấp hơn (bản đồ to hơn), khoảng cách chữ to, chỉ dẫn 1 dòng (tên đường đã hiện trên bản đồ).
- **Thước**: giữ lâu trên màn hình dẫn đường để mở trang đo. Chú thích màu ở giữa ghi "hàng · cạnh".
  - Vạch ngang toàn chiều rộng mỗi 10 px từ mép trên và mép dưới: góc bo làm các vạch đầu ngắn đi. Vạch đầu tiên
    chạm cả hai mép = `SAFE.corner`.
  - Vạch dọc mỗi 4 px từ hai cạnh dài, ở giữa màn hình: vạch đầu tiên hiện đủ = `SAFE.side`.
  - Ghi thêm: ở hàng trên cùng của khung chỉ dẫn (y ≈ 14–66), góc bo cắt mất bao nhiêu px mỗi bên. Hàng mũi tên và
    khoảng cách rộng ~155 px (A) đến ~180 px (C) phải nằm gọn trong đó.
- **Thử tải**: chạm trang thước để chuyển sang 50 → 100 → 200 đoạn xám, vẽ lại mỗi giây. Xem có giật không,
  "chu kỳ chậm nhất" (gần 1000 ms là ổn), để 10 phút ghi pin tụt. Vuốt phải để quay lại.
- **Kích thước tin nhắn**: trong app iOS bấm **Thử tin nhắn N KB** nhiều lần (1, 2, 4 … 32 KB). Vòng hiện
  "Nhận đủ N KB" khi nhận trọn; "Tin nhắn hỏng" hoặc không đổi gì là quá cỡ. Dừng ở 32 KB vì một khung
  BandLink chỉ chứa dưới 64 KB; vòng nhận đủ 32 KB thì ghi "≥ 32 KB".

## Sau khi đo

Sửa số tạm ở `render.js` (và `.panel`/`.label` trong `index.ux` nếu cần), giữ mẫu đã chọn trong `index.ux`,
xoá mẫu còn lại, `DEMO`, trang `pages/proto`, nút thử tin nhắn trong app iOS (tìm `shortcut:`).
