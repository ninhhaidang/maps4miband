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

    let log = Log()
    private(set) var busy = false
    /// Install progress 0...1 while an install runs, nil otherwise.
    private(set) var progress: Double?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var tx: CBCharacteristic?
    @ObservationIgnored private var writeType = CBCharacteristicWriteType.withResponse
    /// BLE writes waiting for CoreBluetooth: write-without-response drops what it has no room for.
    @ObservationIgnored private var outbox: [Data] = []
    @ObservationIgnored private var link: BandLink?
    @ObservationIgnored private var job: ((BandLink) -> [Effect])?
    @ObservationIgnored private var timeout: DispatchWorkItem?
    /// What the timeout tells the user, depending on how far we got.
    @ObservationIgnored private var stuck = ""
    /// Navigating: keep the band after each message instead of releasing it.
    @ObservationIgnored private var streaming = false

    /// Connects, authenticates, opens the quick app, sends `payload` once, then releases the band.
    func sendOnce(authKey: String, payload: Data) {
        begin(authKey: authKey, installing: false) { $0.send(payload) }
    }

    /// Connects, authenticates, opens the quick app with `first` and keeps the band for `send` until `finish`.
    func stream(authKey: String, first: Data) {
        guard !busy else { return }
        begin(authKey: authKey, installing: false) { _ in [] }
        streaming = busy
        // Waits in the link from now, so any screen sent before the band answers replaces it, not the other way round.
        send(first)
    }

    /// Replaces the band's screen while streaming. Before the quick app is open only the newest one waits.
    func send(_ payload: Data) {
        guard streaming, let link else { return }
        run(noteSize(payload, link.send(payload)))
    }

    /// Streaming, and the quick app has not taken a screen yet: the next `send` replaces the one waiting.
    var opening: Bool { streaming && timeout != nil }

    /// Shows `payload` as the last screen, then releases the band.
    func finish(_ payload: Data) {
        guard busy, let link else { return }
        streaming = false
        armTimeout()
        run(noteSize(payload, link.send(payload)))
    }

    /// Notes how big a screen is on the way to the band, then passes its writes on.
    private func noteSize(_ payload: Data, _ effects: [Effect]) -> [Effect] {
        let writes = effects.compactMap { if case .write(let bytes) = $0 { bytes.count } else { nil } }
        note(writes.isEmpty ? "Khung \(payload.count) B, chờ app trên vòng mở"
                            : "Khung \(payload.count) B → \(writes.count) gói BLE, \(writes.reduce(0, +)) B")
        return effects
    }

    /// Connects, authenticates, installs `rpk` as the quick app, then releases the band.
    func install(authKey: String, rpk: Data) {
        begin(authKey: authKey, installing: true) { $0.install(rpk) }
    }

    /// Drops the connection; the band abandons a half-sent package.
    func cancel() {
        fail("Đã huỷ.")
    }

    private func begin(authKey: String, installing: Bool, job: @escaping (BandLink) -> [Effect]) {
        guard !busy else { return }
        guard let link = BandLink(authKey: authKey, appPackage: Self.appPackage) else {
            return note("Lỗi: AuthKey phải gồm đúng 32 ký tự hex. Vào Cài đặt nhập lại.")
        }
        busy = true
        progress = installing ? 0 : nil
        self.link = link
        self.job = job
        note("Đang tìm vòng…")
        stuck = "Vòng không phản hồi sau 30 giây. Hãy đóng hẳn Mi Fitness rồi thử lại."
        armTimeout()
        if let central { centralManagerDidUpdateState(central) } else { central = CBCentralManager(delegate: self, queue: nil) }
    }

    /// Fails if the band goes 30 s without moving forward; rearmed at each step.
    private func armTimeout() {
        timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self.map { $0.fail($0.stuck) } }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
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
        for effect in effects {
            switch effect {
            case .write(let bytes): outbox.append(bytes)
            case .event(let event): handle(event)
            }
        }
        flush()
    }

    private func flush() {
        guard let p = peripheral, let tx else { return }
        while !outbox.isEmpty, writeType == .withResponse || p.canSendWriteWithoutResponse {
            p.writeValue(outbox.removeFirst(), for: tx, type: writeType)
        }
    }

    private func handle(_ event: Event) {
        switch event {
        case .authenticated:
            note("Đã xác thực với vòng.")
            stuck = progress == nil
                ? "Quick app “Dẫn đường” không mở trên vòng. Kiểm tra app đã cài và thử lại."
                : "Vòng ngừng phản hồi khi đang cài. Thử lại; nếu vẫn lỗi, cài bằng AstroBox trên Mac."
            // A quick app left open by the last trip never says it opened; a cold start took ~1 s on the band.
            if progress == nil, let link {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.link === link else { return }
                    run(link.assumeAppOpen())
                }
            }
        case .authKeyRejected: fail("AuthKey sai: vòng từ chối xác thực. Lấy lại AuthKey bằng tools/fetch_authkey.py trên Mac.")
        case .appNotInstalled(let installed):
            note("App trên vòng: \(installed.joined(separator: ", "))")
            fail("Quick app “Dẫn đường” chưa được cài trên vòng. Bấm “Cài app lên vòng”.")
        case .sessionTakenOver: fail("Mi Fitness đang giành kết nối — hãy đóng hẳn Mi Fitness rồi thử lại.")
        case .messageSent where streaming:
            // The first frame got through: the quick app is open, nothing left to time out on.
            if timeout != nil { note("Vòng đã mở app dẫn đường.") }
            timeout?.cancel()
            timeout = nil
        case .messageSent:
            note("Đã gửi khung hình.")
            // shortcut: fixed 1 s for queued writes to leave; wait for the band's ack if the last screen gets cut off.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.release("Xong, đã nhả kết nối cho Mi Fitness.") }
        case .installProgress(let sent, let total):
            progress = Double(sent) / Double(total)
            armTimeout()
            if sent == total { note("Đã gửi xong file, chờ vòng cài…") }
        case .installed: release("Đã cài app lên vòng. Xong, đã nhả kết nối cho Mi Fitness.")
        case .installRefused(let status): fail(Self.refusal(status))
        case .installFailed(2): fail("Vòng báo file .rpk hỏng. Build lại app trên vòng (npx aiot build), Run lại app iOS rồi thử lại.")
        case .installFailed(let code): fail("Vòng cài không thành công (mã \(code)). Thử lại; nếu vẫn lỗi, cài bằng AstroBox trên Mac.")
        }
    }

    private static func refusal(_ status: Int) -> String {
        switch status {
        case 1: "Vòng đang bận, thử lại sau ít phút."
        case 2: "Vòng báo app này đã có. Gỡ app “Dẫn đường” trên vòng rồi cài lại."
        case 3: "Vòng hết dung lượng. Gỡ bớt app hoặc mặt đồng hồ rồi thử lại."
        case 4: "Pin vòng yếu. Sạc rồi thử lại."
        case 5: "Vòng không cho cài bản cũ hơn bản đang có."
        default: "Vòng từ chối cài (mã \(status))."
        }
    }

    private func fail(_ message: String) {
        release("Lỗi: " + message)
    }

    private func release(_ message: String) {
        guard busy else { return }
        timeout?.cancel()
        flush() // the ack of the band's last reply
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        tx = nil
        outbox = []
        link = nil
        job = nil
        progress = nil
        streaming = false
        busy = false
        note(message)
    }

    private func note(_ line: String) {
        log.add(.band, line)
    }
}

extension BandConnection: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard busy else { return }
        switch central.state {
        case .poweredOn: findBand()
        case .unknown, .resetting: break
        case .unauthorized: fail("App chưa được cấp quyền Bluetooth. Bật trong ứng dụng Cài đặt của iPhone → Dẫn đường.")
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
        fail(progress == nil ? "Mất kết nối với vòng." : "Mất kết nối với vòng khi đang cài. Đưa vòng lại gần rồi cài lại.")
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
        guard error == nil, characteristic.isNotifying, let link, let job else {
            return fail("Không bật được thông báo từ vòng: \(error?.localizedDescription ?? "không rõ lý do").")
        }
        note("Đang xác thực…")
        link.maxWriteLength = peripheral.maximumWriteValueLength(for: writeType)
        note("Gói BLE tối đa \(link.maxWriteLength) B, ghi \(writeType == .withoutResponse ? "không chờ" : "chờ") phản hồi.")
        run(link.start())
        run(job(link))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, let link else { return }
        run(link.receive(value))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        flush()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("Ghi xuống vòng thất bại: \(error.localizedDescription)") }
    }
}
