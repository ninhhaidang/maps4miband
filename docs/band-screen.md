# Màn hình vòng (Smart Band 11, 212×520)

Số đo trên vòng thật cho bố cục dẫn đường (#13).

| Đo gì | Kết quả | Trong code |
|---|---|---|
| Cạnh dài bị che (px) | 0 | `SAFE.side = 0` (band/src/common/render.js) |
| Góc bo | bán kính ~100 px: hai đầu gần như nửa hình tròn (bảng dưới) | `SAFE.radius = 100`, `inset(y)` |
| Số đoạn vẽ mượt, cập nhật mỗi giây | 100 (chu kỳ chậm nhất: 50 → 1011 ms, 100 → 1070 ms, 200 → 3340 ms) | `Tuning.maxSegments = 100`, bỏ phần xa nhất |
| Đường xám vẽ một lần thành lớp `div`, mỗi giây chỉ dời lớp (#15, kèm 20 đoạn tuyến vẽ lại) | 300 (chậm nhất: 100 → 1019 ms, 300 → 1265 ms, 500 → dựng 4095 ms rồi 2393 ms, 800 → đơ) | đã thay bằng ảnh (hàng dưới) |
| Đường xám thành một ảnh PNG bảng màu từ điện thoại, ghi ra `internal://files`, mỗi giây chỉ dời ảnh (#15, kèm 20 đoạn tuyến vẽ lại) | vòng hiện được PNG 1 và 2 bit; dời chậm nhất ~1010 ms với mọi cỡ (tin 6.3 KB 312×450 1 bit, 10.5 KB 312×450 2 bit, 11 KB 412×550 1 bit); ghi file 48–74 ms; giải base64 từng ký tự 337–617 ms (nay 4 ký tự một lượt); 1 bit và 2 bit trông như nhau | `mapImage`, 1 bit, 312×450 (`Tuning.layerMarginPx`), mọi đường trong lớp |
| Pin tụt sau 10 phút ở 50 / 100 / 200 đoạn | không đo (bỏ qua) | |
| Tin nhắn interconnect lớn nhất nhận đủ | 16 KB (32 KB không tới) | tin dẫn đường hiện ~0.5 KB; 16 KB ≈ 2000 điểm, nên giới hạn đoạn là do vẽ chứ không do tin nhắn |
| Mẫu bố cục đã chọn (A / B / C) | A | A |

Góc bo cắt mất mỗi bên, ở hàng cách mép trên (mép dưới đối xứng), đọc từ ảnh trang thước chụp thẳng:

| hàng (px) | 0 | 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 |
|---|---|---|---|---|---|---|---|---|---|---|
| bị cắt (px) | 91 | 59 | 41 | 29 | 20 | 13 | 8 | 4 | 2 | 0 |

Hệ quả: hàng mũi tên + khoảng cách (rộng tới ~172 px) bắt đầu từ y = 40; khung chỉ dẫn cao 170 px (`MAP_TOP`);
nhãn tên đường giữ cách mép dưới ≥ 28 px và lùi vào theo `inset` khi xuống gần đáy.

## Cách đo

Đo bằng trang đo trong quick app (giữ lâu màn hình dẫn đường để mở) và nút **Thử tin nhắn N KB** trong app iOS;
cả hai đã xoá sau khi đo, lấy lại từ commit `58dca7f` (`band/src/pages/proto/proto.ux`, `probeMessage` trong
`ios/Maps4MiBand/Maps4MiBandApp.swift`) nếu cần đo lại, ví dụ trên vòng khác.

- **Mẫu bố cục**: ba mẫu, chạm khung chỉ dẫn để đổi, đeo thử rồi chọn A (mũi tên + khoảng cách một hàng, chỉ dẫn
  2 dòng, quãng còn lại). B (mũi tên to riêng một hàng, bỏ quãng còn lại) và C (khung thấp, chỉ dẫn 1 dòng) đã bỏ.
- **Thước**: vạch ngang toàn chiều rộng mỗi 10 px từ mép trên và mép dưới (góc bo làm các vạch đầu ngắn đi; mỗi
  vạch mất bao nhiêu ở hai đầu cho ra `SAFE.radius`), vạch dọc mỗi 4 px từ hai cạnh dài (vạch đầu tiên hiện đủ =
  `SAFE.side`). Đọc từ ảnh chụp thẳng.
- **Ảnh đường xám**: nút tạm trong Cài đặt gửi ảnh quanh Hồ Gươm ở 3 cỡ; vòng hiện ảnh, dời nó mỗi giây và ghi
  thời gian giải base64, ghi file và chu kỳ chậm nhất lên khung chỉ dẫn.
- **Thử tải**: 50 / 100 / 200 đoạn xám ngẫu nhiên vẽ lại mỗi giây, ghi chu kỳ chậm nhất của `setInterval`.
- **Kích thước tin nhắn**: tin 1, 2, 4 … 32 KB; vòng hiện "Nhận đủ N KB" khi nhận trọn. Dừng ở 32 KB vì một khung
  BandLink chỉ chứa dưới 64 KB.
- **Tên đường trên bản đồ**: chữ đậm 14 px cần ~9 px mỗi ký tự ("Phan Huy Chú" bị "…" trong ô 98 px, đủ trong
  ô 116 px).

## Chạy thử khi iPhone khoá màn hình (#10)

1. Ghi pin iPhone và vòng trước khi đi. Cấp quyền vị trí **Luôn luôn** và bật thông báo màn hình khoá cho **Dẫn đường**. Bắt đầu dẫn đường, khoá iPhone ít nhất 30 phút. Ghi lại thời điểm vòng ngừng cập nhật, mất kết nối hoặc rung sai mốc nếu có.
2. Nhờ người khác gọi và nhắn thử trong chuyến, ghi lại vòng có nhận được cả hai và còn tiếp tục dẫn đường sau đó không. Ghi trạng thái Mi Fitness khi thử vì vòng chỉ giữ một phiên xác thực.
3. Khi đã dừng xe và iPhone còn khoá, nhấn giữ thông báo **Đang dẫn đường** rồi chọn **Dừng dẫn đường**. Vuốt lên để mở Trung tâm thông báo nếu thông báo đã vào danh sách cũ. Kiểm tra vòng hiện **Đã dừng dẫn đường**.
4. Sao chép **Nhật ký** để lấy dòng **Chuyến đi** (thời lượng, pin iPhone theo giờ và nhịp gửi) và **Khung BLE lớn nhất chuyến đi**. Dòng **Khung** ghi kích thước JSON, số gói và tổng byte khung đã xếp hàng ghi BLE.
5. Khi dừng xe, quay chậm màn hình vòng lúc bản đồ cập nhật, gồm cả khung đổi ảnh đường xám. Đếm số khung video từ lúc màn hình bắt đầu đổi đến khi bản đồ và chỉ dẫn hiện đủ, rồi chia cho tốc độ khung hình. Số đo này tính thời gian vẽ thấy được trên màn hình. Ghi riêng các lần cập nhật có ảnh mới vì vòng phải giải mã và ghi ảnh.
6. Ghi kết quả vào #10, gồm pin vòng trước/sau và độ mượt. Thử nhịp 2–3 giây nếu vòng cập nhật không kịp hoặc tốn pin. Dùng kết quả để chốt nhịp gửi, mốc rung và tỉ lệ bản đồ.
