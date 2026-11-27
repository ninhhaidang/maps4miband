# maps4miband

Dẫn đường trên **Xiaomi Smart Band 11**: bản đồ đơn giản xoay theo hướng đi, mũi tên rẽ, khoảng cách tới chỗ rẽ, rung khi sắp rẽ.

```
iPhone app (ios/) ──CoreBluetooth, tự xác thực bằng AuthKey (BandLink)──▶ quick app trên vòng (band/)
                                                                        vẽ đường bằng các div xoay
```

Đang ở giai đoạn spike (#4): app iOS kết nối, xác thực và gửi một khung hình mẫu. Bản Android cũ (qua Gadgetbridge)
nằm trong `legacy/android/`, giữ để tham khảo.

## Build

```sh
# App trên vòng → band/dist/com.maps4miband.band.debug.0.1.0.rpk
cd band && npm install && npm test && npx aiot build

# Giao thức Xiaomi (BandLink): unit test chạy trên Mac
cd ios/BandLink && swift test

# App iOS: mở ios/Maps4MiBand.xcodeproj trong Xcode, Signing & Capabilities → chọn Team (Apple ID miễn phí;
# đổi Bundle Identifier nếu bị trùng), cắm iPhone, Run. App ký miễn phí hết hạn sau 7 ngày.

# App Android cũ → legacy/android/app/build/outputs/apk/debug/app-debug.apk (cần JDK 17–21)
cd legacy/android && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew testDebugUnitTest assembleDebug
```

Cài `.rpk` lên vòng: build `band/` trước rồi Run app iOS (bước build tự đóng gói `.rpk` mới nhất), đóng hẳn
Mi Fitness, bấm **Cài app lên vòng**. Lần đầu, hoặc khi cài từ iPhone lỗi, dùng AstroBox trên Mac (xem #2).

## Thử trên vòng thật

1. Vòng đang kết nối Bluetooth với iPhone (như khi dùng Mi Fitness). **Đóng hẳn Mi Fitness** (vuốt tắt app): vòng chỉ giữ một phiên xác thực.
2. Trong app *Dẫn đường* trên iPhone: dán AuthKey, **Lưu vào Keychain**, bấm **Gửi thử lên vòng**.
3. Vòng tự mở quick app và vẽ khung hình mẫu. Nhật ký chẩn đoán trên màn hình ghi từng bước hoặc lỗi.
4. Xong app nhả kết nối; mở lại Mi Fitness là kết nối lại vòng.

## Lấy AuthKey

Đăng nhập tài khoản Xiaomi trong AstroBox (macOS), rồi:

```sh
python3 -I tools/fetch_authkey.py          # hỏi mọi máy chủ Mi Fitness, lưu AuthKey vào Keychain, không in key
security find-generic-password -s maps4miband-authkey -a <MAC> -w | pbcopy   # chép key để dán
```

## Giấy phép

AGPL-3.0 (port code từ Gadgetbridge và AstroBox, đều AGPL-3.0).
