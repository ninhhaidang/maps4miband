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

/// One screen in the quick app's message format (BandMessage): rider at 106,345 north up, a left turn 160 m north.
let sampleFrame = Data(#"{"p":[106,395,106,345,106,265,40,265],"t":[106,265],"n":"Phố Tôn Đức Thắng","a":-90,"d":"160 m","i":"Rẽ trái vào Phố Tôn Đức Thắng","r":"Còn 1.6 km","v":1}"#.utf8)

/// Bản đồ · Nhật ký · Cài đặt; opens on Cài đặt while a key is missing.
struct ContentView: View {
    private enum Screen { case map, log, settings }

    @State private var band: BandConnection
    @State private var nav: Navigation
    @State private var saved = Keychain.load(Keychain.authKey) != nil
    @State private var vietmapSaved = Keychain.load(Keychain.vietmapKey) != nil
    @State private var screen: Screen

    init() {
        let band = BandConnection()
        _band = State(initialValue: band)
        _nav = State(initialValue: Navigation(band: band))
        _screen = State(initialValue: Keychain.load(Keychain.authKey) == nil || Keychain.load(Keychain.vietmapKey) == nil
                        ? .settings : .map)
    }

    var body: some View {
        TabView(selection: $screen) {
            MapTab(band: band, nav: nav, saved: saved, vietmapSaved: vietmapSaved)
                .tabItem { Label("Bản đồ", systemImage: "map") }
                .tag(Screen.map)
            LogView(log: band.log)
                .tabItem { Label("Nhật ký", systemImage: "list.bullet.rectangle") }
                .badge(band.log.unseenErrors)
                .tag(Screen.log)
            SettingsView(band: band, saved: $saved, vietmapSaved: $vietmapSaved)
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
                .tag(Screen.settings)
        }
        // Here rather than in init: SwiftUI may build this view again, and only the band kept in @State has the log on screen.
        .task {
            Vietmap.onRequest = { [log = band.log] url, status, seconds in
                let what = status == 200 ? "HTTP 200" : status == 0 ? "Lỗi: không có phản hồi" : "Lỗi: HTTP \(status)"
                let line = "\(what), \(String(format: "%.2f", seconds)) s  \(url)"
                DispatchQueue.main.async { log.add(.vietmap, line) }
            }
        }
        // Errors that come in while the log is on screen are seen already.
        .onChange(of: screen == .log && band.log.unseenErrors > 0) { _, unseen in
            if unseen { band.log.seen() }
        }
    }
}

/// The map fills the tab. Idle: search box on top with results dropping down from it, the route's length and
/// Bắt đầu in a card at the bottom. Navigating: the map follows the rider north-up like the band, under a card showing what
/// the band shows, with Dừng below.
struct MapTab: View {
    let band: BandConnection
    let nav: Navigation
    let saved: Bool
    let vietmapSaved: Bool
    @State private var camera = MapCameraPosition.userLocation(fallback: .automatic)
    @FocusState private var typing: Bool
    @State private var query = ""
    @State private var places: [Vietmap.Place] = []
    @State private var searchError: String?
    /// The result last chosen, now in the search box; not searched again.
    @State private var picked = ""
    @State private var choosing: Task<Void, Never>?

    var body: some View {
        Map(position: $camera) {
            if let route = nav.preview {
                MapPolyline(coordinates: route.points.map(\.coordinate)).stroke(.blue, lineWidth: 6)
                if let end = route.points.last { Marker("Điểm đến", coordinate: end.coordinate) }
            }
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .onTapGesture { typing = false }
        .overlay(alignment: .bottomTrailing) {
            Text("© OpenStreetMap contributors")
                .font(.caption2)
                .padding(.horizontal, 4)
                .background(.thinMaterial, in: .rect(cornerRadius: 4))
                .padding(8)
        }
        .safeAreaInset(edge: .top) {
            if !nav.running {
                searchBox
            } else if let shown = nav.shown {
                card(shown)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if nav.running {
                Button(role: .destructive) { nav.stop() } label: {
                    Text("Dừng").font(.title3.bold()).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            } else if !typing {
                bottomCard
            }
        }
        .onChange(of: nav.running) {
            camera = nav.running ? .userLocation(fallback: .automatic) : nav.preview.map(fit) ?? camera
        }
        .onChange(of: nav.preview?.points) {
            if !nav.running, let route = nav.preview { camera = fit(route) }
        }
    }

    private var searchBox: some View {
        VStack(spacing: 6) {
            field
            if typing { results }
        }
        .padding(.horizontal)
    }

    private var field: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(vietmapSaved ? "Tìm điểm đến, hoặc vĩ độ,kinh độ" : "Lưu Vietmap key trong tab Cài đặt để tìm",
                      text: $query)
                .autocorrectionDisabled()
                .focused($typing)
                .disabled(!vietmapSaved)
                .task(id: query) { await search() }
            if !query.isEmpty {
                Button { (query, typing) = ("", false) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Xoá")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder private var results: some View {
        let coordinate = Point(parsing: query)
        if coordinate != nil || !places.isEmpty || searchError != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                if let to = coordinate {
                    row { go(to) } label: { Text("Đến toạ độ \(query)") }
                }
                ForEach(places) { place in
                    row { choose(place) } label: {
                        Text(place.name)
                        Text(place.address).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let searchError { Text(searchError).foregroundStyle(.red).padding(12) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // As tall as the rows, up to 340 pt, then it scrolls.
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
    }

    private func row(_ action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2, content: label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var bottomCard: some View {
        let notes = [searchError, nav.status.isEmpty ? nil : nav.status].compactMap { $0 }
        if nav.preview != nil || !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let route = nav.preview {
                    HStack {
                        Text("Xe máy: \(formatDistance(route.length))").font(.headline)
                        Spacer()
                        Button("Bắt đầu") { nav.start(authKey: Keychain.load(Keychain.authKey) ?? "") }
                            .buttonStyle(.borderedProminent)
                            .disabled(band.busy || !saved || nav.planning)
                    }
                    Text(saved ? "Đóng hẳn Mi Fitness trước. Giữ app mở trên màn hình trong lúc đi."
                               : "Lưu AuthKey trong tab Cài đặt để bắt đầu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(notes, id: \.self) { Text($0).font(.subheadline) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// The band's screen as text: arrow and distance on one row, then the instruction and what remains.
    private func card(_ m: BandMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if let a = m.a {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 36, weight: .bold))
                        .rotationEffect(.degrees(Double(a)))
                }
                if let d = m.d, !d.isEmpty { Text(d).font(.largeTitle.bold()) }
            }
            Text(m.i).font(.title3.weight(.semibold))
            if let r = m.r { Text(r).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// The whole route with a margin, between the search box and the bottom card.
    private func fit(_ route: Route) -> MapCameraPosition {
        let r = MKPolyline(coordinates: route.points.map(\.coordinate), count: route.points.count).boundingMapRect
        return .rect(r.insetBy(dx: -r.width / 5, dy: -r.height / 5))
    }

    private func go(_ to: Point) {
        picked = query.trimmingCharacters(in: .whitespaces)
        typing = false
        nav.plan(to: to, vietmapKey: Keychain.load(Keychain.vietmapKey) ?? "")
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
        typing = false
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

extension Point {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
