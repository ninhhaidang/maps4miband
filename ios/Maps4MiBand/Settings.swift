import BandLink
import SwiftUI

/// One-time setup: keys, installing the quick app, a test frame, the diagnostic log.
struct SettingsView: View {
    let band: BandConnection
    @Binding var saved: Bool
    @Binding var vietmapSaved: Bool
    @State private var authKey = Keychain.load(Keychain.authKey) ?? ""
    @State private var vietmapKey = Keychain.load(Keychain.vietmapKey) ?? ""
    @State private var invalid = false
    @Environment(\.dismiss) private var dismiss

    private var missing: [String] {
        (saved ? [] : ["AuthKey của vòng (để gửi chỉ dẫn lên vòng)"])
            + (vietmapSaved ? [] : ["Vietmap API key (để tìm điểm đến và tìm đường)"])
    }

    var body: some View {
        NavigationStack {
            Form {
                if !missing.isEmpty {
                    Section {
                        Text("Còn thiếu: " + missing.joined(separator: ", ") + ". Nhập ở dưới rồi lưu.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    SecureField("AuthKey (32 ký tự hex)", text: $authKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onChange(of: authKey) { saved = false }
                    Button(saved ? "Đã lưu trong Keychain" : "Lưu vào Keychain") {
                        let key = authKey.trimmingCharacters(in: .whitespaces)
                        invalid = BandLink(authKey: key, appPackage: BandConnection.appPackage) == nil
                        saved = !invalid && Keychain.save(key, as: Keychain.authKey)
                    }
                    .disabled(saved || authKey.isEmpty)
                    SecureField("Vietmap API key", text: $vietmapKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onChange(of: vietmapKey) { vietmapSaved = false }
                    Button(vietmapSaved ? "Đã lưu trong Keychain" : "Lưu vào Keychain") {
                        vietmapSaved = Keychain.save(vietmapKey.trimmingCharacters(in: .whitespaces), as: Keychain.vietmapKey)
                    }
                    .disabled(vietmapSaved || vietmapKey.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Khoá")
                } footer: {
                    if invalid { Text("AuthKey phải gồm đúng 32 ký tự hex.").foregroundStyle(.red) }
                }

                Section {
                    Button(band.progress != nil ? "Đang cài…" : "Cài app lên vòng") {
                        if let rpk = bundledRpk { band.install(authKey: Keychain.load(Keychain.authKey) ?? "", rpk: rpk) }
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
                        band.sendOnce(authKey: Keychain.load(Keychain.authKey) ?? "", payload: sampleFrame)
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

                Section {
                    Text("Dữ liệu đường: © OpenStreetMap contributors").font(.footnote)
                }
            }
            .navigationTitle("Cài đặt")
            .toolbar { Button("Xong") { dismiss() } }
        }
    }
}
