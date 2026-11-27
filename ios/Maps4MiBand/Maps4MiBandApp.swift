import BandLink
import MapKit
import Navigator
import SwiftUI

@main
struct Maps4MiBandApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// The quick app build bundled by the "Bundle band .rpk" build phase (newest band/dist/*.rpk), if there was one.
let bundledRpk = Bundle.main.url(forResource: "band", withExtension: "rpk").flatMap { try? Data(contentsOf: $0) }

/// One screen in the quick app's message format (BandMessage): rider at 106,460 heading up, a left turn 160 m ahead.
let sampleFrame = Data(#"{"p":[106,510,106,460,106,380,40,380],"t":[106,380],"n":"Phố Tôn Đức Thắng","a":-90,"d":"160 m","i":"Rẽ trái vào Phố Tôn Đức Thắng","r":"Còn 1.6 km","v":1}"#.utf8)

/// shortcut: probe for the largest interconnect message the band takes (#13); drop once docs/band-screen.md has it.
/// The band shows `i` only if the whole message arrived and parsed. Stops at 32 KB: a BandLink frame holds < 64 KB.
func probeMessage(kb: Int) -> Data {
    let head = #"{"i":"Nhận đủ \#(kb) KB","z":""#
    return Data((head + String(repeating: "x", count: max(kb * 1024 - head.utf8.count - 2, 0)) + #""}"#).utf8)
}

struct ContentView: View {
    @State private var band: BandConnection
    @State private var nav: Navigation
    @State private var authKey = Keychain.load(Keychain.authKey) ?? ""
    @State private var saved = Keychain.load(Keychain.authKey) != nil
    @State private var invalid = false
    @State private var vietmapKey = Keychain.load(Keychain.vietmapKey) ?? ""
    @State private var vietmapSaved = Keychain.load(Keychain.vietmapKey) != nil
    @State private var query = ""
    @State private var places: [Vietmap.Place] = []
    @State private var searchError: String?
    /// The result last chosen, now in the search box; not searched again.
    @State private var picked = ""
    @State private var choosing: Task<Void, Never>?
    @State private var probeKB = 1

    init() {
        let band = BandConnection()
        _band = State(initialValue: band)
        _nav = State(initialValue: Navigation(band: band))
    }

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
                    Text("Cài đặt")
                } footer: {
                    if invalid { Text("AuthKey phải gồm đúng 32 ký tự hex.").foregroundStyle(.red) }
                }

                Section {
                    TextField("Tìm điểm đến, hoặc vĩ độ,kinh độ", text: $query)
                        .autocorrectionDisabled()
                        .disabled(nav.running || !vietmapSaved)
                        .task(id: query) { await search() }
                    if let to = Point(parsing: query), !nav.running {
                        Button("Đến toạ độ \(query)") {
                            picked = query.trimmingCharacters(in: .whitespaces)
                            nav.plan(to: to, vietmapKey: Keychain.load(Keychain.vietmapKey) ?? "")
                        }
                    }
                    ForEach(nav.running ? [] : places) { place in
                        Button { choose(place) } label: {
                            VStack(alignment: .leading) {
                                Text(place.name)
                                Text(place.address).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let searchError { Text(searchError).foregroundStyle(.red) }
                    if !vietmapSaved { Text("Lưu Vietmap API key ở trên để tìm điểm đến.").foregroundStyle(.secondary) }
                    if let route = nav.preview {
                        // A new preview replaces this view (preview goes nil in between), so the camera refits.
                        Map {
                            MapPolyline(coordinates: route.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                                .stroke(.blue, lineWidth: 5)
                            if let end = route.points.last {
                                Marker("Điểm đến", coordinate: CLLocationCoordinate2D(latitude: end.lat, longitude: end.lon))
                            }
                            UserAnnotation()
                        }
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                        Text("Quãng đường xe máy: \(formatDistance(route.length))")
                    }
                    if nav.running {
                        Button("Dừng", role: .destructive) { nav.stop() }
                    } else {
                        Button("Bắt đầu") { nav.start(authKey: Keychain.load(Keychain.authKey) ?? "") }
                            .disabled(band.busy || !saved || nav.planning || nav.preview == nil)
                    }
                    if !nav.status.isEmpty { Text(nav.status) }
                } header: {
                    Text("Dẫn đường xe máy")
                } footer: {
                    Text("Đóng hẳn Mi Fitness trước. Giữ app mở trên màn hình trong lúc đi.")
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
                    Button("Thử tin nhắn \(probeKB) KB") {
                        band.sendOnce(authKey: Keychain.load(Keychain.authKey) ?? "", payload: probeMessage(kb: probeKB))
                        probeKB = probeKB >= 32 ? 1 : probeKB * 2
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

    /// Autocomplete as the user types; a typed coordinate or the result just chosen is not searched.
    private func search() async {
        places = []
        searchError = nil
        let text = query.trimmingCharacters(in: .whitespaces)
        if text != picked, !nav.running {
            // Another destination: the old route must not be the one Bắt đầu starts.
            picked = ""
            choosing?.cancel()
            nav.cancelPlan()
        }
        guard text.count >= 2, text != picked, Point(parsing: text) == nil, vietmapSaved else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            places = try await Vietmap.search(text, near: nav.here, apiKey: Keychain.load(Keychain.vietmapKey) ?? "")
            if places.isEmpty { searchError = "Không tìm thấy \"\(text)\"." }
        } catch where !Task.isCancelled {
            searchError = Vietmap.Failure.message(for: error)
        } catch {}
    }

    private func choose(_ place: Vietmap.Place) {
        (picked, query, places) = (place.name, place.name, [])
        nav.cancelPlan()
        choosing?.cancel()
        let key = Keychain.load(Keychain.vietmapKey) ?? ""
        choosing = Task {
            do {
                let to = try await Vietmap.point(of: place, apiKey: key)
                // A later pick wins even if its Place answer came first.
                guard !Task.isCancelled else { return }
                nav.plan(to: to, vietmapKey: key)
            } catch where !Task.isCancelled {
                searchError = Vietmap.Failure.message(for: error)
            } catch {}
        }
    }
}
