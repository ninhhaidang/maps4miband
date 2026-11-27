import BandLink
import SwiftUI

@main
struct Maps4MiBandApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// The quick app build bundled by the "Bundle band .rpk" build phase (newest band/dist/*.rpk), if there was one.
let bundledRpk = Bundle.main.url(forResource: "band", withExtension: "rpk").flatMap { try? Data(contentsOf: $0) }

/// One screen in the quick app's message format: p = polyline in band px (rider at 106,280 heading up),
/// a = turn angle (+ right, null = no arrow), d = distance to the turn, i = instruction, r = remaining, v = 1 buzz.
let sampleFrame = Data(#"{"p":[106,330,106,280,106,150,40,150],"a":-90,"d":"260 m","i":"Rẽ trái vào Phố Tôn Đức Thắng","r":"Còn 1.6 km","v":1}"#.utf8)

struct ContentView: View {
    @State private var band = BandConnection()
    @State private var authKey = Keychain.load() ?? ""
    @State private var saved = Keychain.load() != nil
    @State private var invalid = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("AuthKey (32 ký tự hex)", text: $authKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onChange(of: authKey) { saved = false }
                    Button(saved ? "Đã lưu trong Keychain" : "Lưu vào Keychain") {
                        let key = authKey.trimmingCharacters(in: .whitespaces)
                        invalid = BandLink(authKey: key, appPackage: BandConnection.appPackage) == nil
                        saved = !invalid && Keychain.save(key)
                    }
                    .disabled(saved || authKey.isEmpty)
                } header: {
                    Text("Cài đặt")
                } footer: {
                    if invalid { Text("AuthKey phải gồm đúng 32 ký tự hex.").foregroundStyle(.red) }
                }

                Section {
                    Button(band.progress != nil ? "Đang cài…" : "Cài app lên vòng") {
                        if let rpk = bundledRpk { band.install(authKey: Keychain.load() ?? "", rpk: rpk) }
                    }
                    .disabled(band.busy || !saved || bundledRpk == nil)
                    if let progress = band.progress {
                        ProgressView(value: progress)
                        Button("Huỷ", role: .destructive) { band.cancel() }
                    }
                } footer: {
                    Text(bundledRpk.map { "Cài bản quick app đóng gói trong app (\($0.count / 1024) KB). Đóng hẳn Mi Fitness trước." }
                         ?? "Chưa có .rpk trong app: chạy npx aiot build trong band/ rồi Run lại từ Xcode.")
                }

                Section {
                    Button(band.busy && band.progress == nil ? "Đang gửi…" : "Gửi thử lên vòng") {
                        band.sendOnce(authKey: Keychain.load() ?? "", payload: sampleFrame)
                    }
                    .disabled(band.busy || !saved)
                } footer: {
                    Text("Đóng hẳn Mi Fitness trước khi thử: vòng chỉ giữ một phiên xác thực.")
                }

                Section("Nhật ký chẩn đoán") {
                    ForEach(Array(band.log.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced())
                    }
                }
            }
            .navigationTitle("Dẫn đường")
        }
    }
}
