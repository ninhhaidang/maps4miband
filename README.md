# maps4miband

Dẫn đường trên **Xiaomi Smart Band 11**: bản đồ đơn giản xoay theo hướng đi, mũi tên rẽ, khoảng cách tới chỗ rẽ, rung khi sắp rẽ.

```
Android app ──GPS + tuyến OSRM──▶ tính khung hình (polyline px, rẽ, khoảng cách)
     │ broadcast SEND_WATCH_APP_MESSAGE
     ▼
Gadgetbridge ──BLE──▶ quick app trên vòng (band/) vẽ đường bằng các div xoay
```

Chỉ Android. iOS không có cách gửi dữ liệu tới app trên vòng nếu không được Xiaomi duyệt.

## Cần có

- Vòng đã ghép với **Gadgetbridge** (thay cho Mi Fitness; cần auth key). Lệnh gửi tin tới app trên vòng có thể chỉ có ở bản *Nightly*.
- Trong Gadgetbridge:
  - Cài đặt → Developer options → Intent API: bật.
  - Cài đặt của vòng → Developer settings → Intent API → **Allow messages to watch apps**: bật.
- MAC của vòng (Gadgetbridge → chi tiết thiết bị).

## Build

```sh
# App trên vòng → band/dist/com.maps4miband.band.debug.0.1.0.rpk
cd band && npm install && npm test && npx aiot build

# App Android → android/app/build/outputs/apk/debug/app-debug.apk (cần JDK 17–21, Gradle 8.14 không chạy với JDK 27)
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew testDebugUnitTest assembleDebug
```

Cài `.rpk` lên vòng bằng Gadgetbridge (Cài đặt ứng dụng / mở file .rpk bằng Gadgetbridge) hoặc AstroBox.

## Dùng

1. Mở app *Dẫn đường* trên vòng.
2. Trên điện thoại: nhập điểm đến (địa chỉ hoặc `vĩ độ,kinh độ`), hoặc chia sẻ một địa điểm dạng `geo:` từ app bản đồ khác, nhập MAC, bấm **Bắt đầu**.
3. Đi lệch tuyến hơn 40 m trong 3 lần định vị → tự tìm đường lại.

## Giới hạn

- Tuyến lấy từ server demo công khai của OSRM: chỉ profile ô tô, có giới hạn sử dụng.
- Bản đồ chỉ vẽ tuyến đường, chưa có các phố xung quanh.
- Chưa đo giới hạn kích thước tin nhắn qua BLE. Một khung hình tối đa khoảng 130 điểm (~1,5 KB JSON).
