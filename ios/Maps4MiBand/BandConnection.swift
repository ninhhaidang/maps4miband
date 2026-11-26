import BandLink
import CoreBluetooth
import Observation

/// Thin CoreBluetooth layer: takes the band from the peripherals iOS already has connected (no scanning or
/// pairing), pipes its bytes through BandLink, and lets go of it when done so Mi Fitness can have it back.
@Observable
final class BandConnection: NSObject {
    // Must match "package" in band/src/manifest.json.
    static let appPackage = "com.maps4miband.band"
    private static let service = CBUUID(string: "FE95")
    private static let rxUUID = CBUUID(string: "005E")
    private static let txUUID = CBUUID(string: "005F")

    private(set) var log: [String] = []
    private(set) var busy = false

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var tx: CBCharacteristic?
    @ObservationIgnored private var writeType = CBCharacteristicWriteType.withResponse
    @ObservationIgnored private var link: BandLink?
    @ObservationIgnored private var payload = Data()
    @ObservationIgnored private var timeout: DispatchWorkItem?
    /// What the 30 s timeout tells the user, depending on how far we got.
    @ObservationIgnored private var stuck = ""

    /// Connects, authenticates, opens the quick app, sends `payload` once, then releases the band.
    func sendOnce(authKey: String, payload: Data) {
        guard !busy else { return }
        guard let link = BandLink(authKey: authKey, appPackage: Self.appPackage) else {
            return note("Lỗi: AuthKey phải gồm đúng 32 ký tự hex. Vào Cài đặt nhập lại.")
        }
        busy = true
        self.link = link
        self.payload = payload
        note("Đang tìm vòng…")
        stuck = "Vòng không phản hồi sau 30 giây. Hãy đóng hẳn Mi Fitness rồi thử lại."
        let timeout = DispatchWorkItem { [weak self] in self.map { $0.fail($0.stuck) } }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        if let central { centralManagerDidUpdateState(central) } else { central = CBCentralManager(delegate: self, queue: nil) }
    }

    private func findBand() {
        // shortcut: takes the first connected fe95 device; pick by name once a second Xiaomi wearable is around.
        guard let p = central?.retrieveConnectedPeripherals(withServices: [Self.service]).first else {
            return fail("Không tìm thấy vòng. Hãy kiểm tra vòng đang kết nối Bluetooth với iPhone (Cài đặt → Bluetooth) và ở gần.")
        }
        note("Thấy vòng \(p.name ?? p.identifier.uuidString), đang kết nối…")
        peripheral = p
        p.delegate = self
        central?.connect(p)
    }

    private func run(_ effects: [Effect]) {
        guard let p = peripheral, let tx else { return }
        for effect in effects {
            switch effect {
            // shortcut: no flow control on write-without-response; fine for a few short frames, check
            // canSendWriteWithoutResponse once frames go out every second.
            case .write(let bytes): p.writeValue(bytes, for: tx, type: writeType)
            case .event(let event): handle(event)
            }
        }
    }

    private func handle(_ event: Event) {
        switch event {
        case .authenticated:
            note("Đã xác thực với vòng. Đang mở quick app “Dẫn đường”…")
            stuck = "Quick app “Dẫn đường” không mở trên vòng sau 30 giây. Kiểm tra app đã cài và thử lại."
        case .authKeyRejected: fail("AuthKey sai: vòng từ chối xác thực. Lấy lại AuthKey bằng tools/fetch_authkey.py trên Mac.")
        case .appNotInstalled(let installed):
            note("App trên vòng: \(installed.joined(separator: ", "))")
            fail("Quick app “Dẫn đường” chưa được cài trên vòng. Cài file .rpk bằng AstroBox trên Mac.")
        case .sessionTakenOver: fail("Mi Fitness đang giành kết nối — hãy đóng hẳn Mi Fitness rồi thử lại.")
        case .messageSent:
            note("Đã gửi khung hình.")
            // shortcut: fixed 1 s for queued writes to leave; wait for the band's ack once frames stream every second.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.release("Xong, đã nhả kết nối cho Mi Fitness.") }
        }
    }

    private func fail(_ message: String) {
        release("Lỗi: " + message)
    }

    private func release(_ message: String) {
        guard busy else { return }
        timeout?.cancel()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        tx = nil
        link = nil
        busy = false
        note(message)
    }

    private func note(_ line: String) {
        log.append("\(Date().formatted(date: .omitted, time: .standard))  \(line)")
    }
}

extension BandConnection: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard busy else { return }
        switch central.state {
        case .poweredOn: findBand()
        case .unknown, .resetting: break
        case .unauthorized: fail("App chưa được cấp quyền Bluetooth. Bật trong Cài đặt → Dẫn đường.")
        default: fail("Bluetooth của iPhone đang tắt.")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        note("Đã kết nối.")
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail("Không kết nối được vòng: \(error?.localizedDescription ?? "không rõ lý do").")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        fail("Mất kết nối với vòng.")
    }
}

extension BandConnection: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            return fail("Vòng không có dịch vụ Bluetooth fe95 của Xiaomi.")
        }
        peripheral.discoverCharacteristics([Self.rxUUID, Self.txUUID], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let chars = service.characteristics ?? []
        guard let rx = chars.first(where: { $0.uuid == Self.rxUUID }),
              let tx = chars.first(where: { $0.uuid == Self.txUUID }) else {
            return fail("Vòng không có kênh dữ liệu 005e/005f (giao thức BLE V2).")
        }
        self.tx = tx
        writeType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.setNotifyValue(true, for: rx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying, let link else {
            return fail("Không bật được thông báo từ vòng: \(error?.localizedDescription ?? "không rõ lý do").")
        }
        note("Đang xác thực…")
        link.maxWriteLength = peripheral.maximumWriteValueLength(for: writeType)
        run(link.start())
        run(link.send(payload))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, let link else { return }
        run(link.receive(value))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("Ghi xuống vòng thất bại: \(error.localizedDescription)") }
    }
}
