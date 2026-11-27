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

/// The map fills the screen. Idle: search, results and the route preview in a sheet pulled up from the bottom.
/// Navigating: the map follows the rider heading-up, under a card showing what the band shows, with Dừng below.
struct ContentView: View {
    @State private var band: BandConnection
    @State private var nav: Navigation
    @State private var saved = Keychain.load(Keychain.authKey) != nil
    @State private var vietmapSaved = Keychain.load(Keychain.vietmapKey) != nil
    @State private var settingsOpen = Keychain.load(Keychain.authKey) == nil || Keychain.load(Keychain.vietmapKey) == nil
    @State private var camera = MapCameraPosition.userLocation(fallback: .automatic)
    @State private var detent = peek
    @FocusState private var typing: Bool
    @State private var query = ""
    @State private var places: [Vietmap.Place] = []
    @State private var searchError: String?
    /// The result last chosen, now in the search box; not searched again.
    @State private var picked = ""
    @State private var choosing: Task<Void, Never>?

    /// The sheet pulled down: search box and, with a route, its length and Bắt đầu.
    // shortcut: fixed height, large Dynamic Type pushes Bắt đầu below it; measure the sheet content if riders hit that.
    private static let peekHeight: CGFloat = 170
    private static let peek = PresentationDetent.height(peekHeight)

    init() {
        let band = BandConnection()
        _band = State(initialValue: band)
        _nav = State(initialValue: Navigation(band: band))
    }

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
        .overlay(alignment: .bottomTrailing) {
            Text("© OpenStreetMap contributors")
                .font(.caption2)
                .padding(.horizontal, 4)
                .background(.thinMaterial, in: .rect(cornerRadius: 4))
                .padding(8)
        }
        // Keeps the route, the controls and the credit above the pulled-down sheet.
        .safeAreaPadding(.bottom, nav.running ? 0 : Self.peekHeight)
        .safeAreaInset(edge: .top) {
            if nav.running, let shown = nav.shown { card(shown) }
        }
        .safeAreaInset(edge: .bottom) {
            if nav.running {
                Button(role: .destructive) { nav.stop() } label: {
                    Text("Dừng").font(.title3.bold()).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .sheet(isPresented: .constant(!nav.running)) { sheet }
        .onChange(of: nav.running) {
            camera = nav.running ? .userLocation(followsHeading: true, fallback: .automatic) : nav.preview.map(fit) ?? camera
        }
        .onChange(of: nav.preview?.points) {
            if !nav.running, let route = nav.preview { camera = fit(route) }
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

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Tìm điểm đến, hoặc vĩ độ,kinh độ", text: $query)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .padding(10)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                    .disabled(!vietmapSaved)
                    .task(id: query) { await search() }
                Button { settingsOpen = true } label: {
                    Image(systemName: "gearshape").font(.title2)
                }
                .accessibilityLabel("Cài đặt")
            }
            if let route = nav.preview {
                HStack {
                    Text("Xe máy: \(formatDistance(route.length))").font(.headline)
                    Spacer()
                    Button("Bắt đầu") { nav.start(authKey: Keychain.load(Keychain.authKey) ?? "") }
                        .buttonStyle(.borderedProminent)
                        .disabled(band.busy || !saved || nav.planning)
                }
            }
            if !nav.status.isEmpty { Text(nav.status).font(.subheadline) }
            List {
                if let to = Point(parsing: query) {
                    Button("Đến toạ độ \(query)") {
                        picked = query.trimmingCharacters(in: .whitespaces)
                        typing = false
                        detent = Self.peek
                        nav.plan(to: to, vietmapKey: Keychain.load(Keychain.vietmapKey) ?? "")
                    }
                }
                ForEach(places) { place in
                    Button { choose(place) } label: {
                        VStack(alignment: .leading) {
                            Text(place.name)
                            Text(place.address).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let searchError { Text(searchError).foregroundStyle(.red) }
                if !vietmapSaved { Text("Lưu Vietmap API key trong Cài đặt để tìm điểm đến.").foregroundStyle(.secondary) }
                if !saved { Text("Lưu AuthKey trong Cài đặt để bắt đầu dẫn đường.").foregroundStyle(.secondary) }
                Text("Đóng hẳn Mi Fitness trước. Giữ app mở trên màn hình trong lúc đi.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listStyle(.plain)
        }
        .padding([.horizontal, .top])
        .presentationDetents([Self.peek, .medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
        .onChange(of: typing) { if typing { detent = .large } }
        .sheet(isPresented: $settingsOpen) { SettingsView(band: band, saved: $saved, vietmapSaved: $vietmapSaved) }
    }

    /// The whole route with a margin, above the pulled-down sheet.
    private func fit(_ route: Route) -> MapCameraPosition {
        let r = MKPolyline(coordinates: route.points.map(\.coordinate), count: route.points.count).boundingMapRect
        return .rect(r.insetBy(dx: -r.width / 5, dy: -r.height / 5))
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
        detent = Self.peek
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
