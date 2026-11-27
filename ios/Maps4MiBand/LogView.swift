import SwiftUI

/// Nhật ký tab: the whole log, newest at the bottom, filtered by source; copying always takes everything.
struct LogView: View {
    let log: Log
    @State private var filter: Log.Source?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            let shown = log.lines.filter { filter == nil || $0.source == filter }
            ScrollViewReader { proxy in
                List(shown) { line in
                    Text(line.formatted)
                        .font(.caption.monospaced())
                        .foregroundStyle(line.error ? .red : .primary)
                        .textSelection(.enabled)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .overlay {
                    if log.lines.isEmpty { ContentUnavailableView("Chưa có nhật ký", systemImage: "list.bullet.rectangle") }
                }
                // New lines and a new filter both land on the newest line.
                .onChange(of: shown.last?.id) { _, last in last.map { proxy.scrollTo($0, anchor: .bottom) } }
                .onAppear { shown.last.map { proxy.scrollTo($0.id, anchor: .bottom) } }
            }
            .safeAreaInset(edge: .top) {
                // Chips rather than a segmented control: "Dẫn đường" gets cut off in five segments.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("Tất cả", nil)
                        ForEach(Log.Source.allCases) { chip($0.rawValue, $0) }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("Nhật ký")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Xoá", role: .destructive) { log.clear() }.disabled(log.lines.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "Đã sao chép" : "Sao chép tất cả", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = log.report()
                        copied = true
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(log.lines.isEmpty)
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
            }
        }
    }

    private func chip(_ title: String, _ source: Log.Source?) -> some View {
        Button(title) { filter = source }
            .buttonStyle(.bordered)
            .tint(filter == source ? .accentColor : .secondary)
            .accessibilityAddTraits(filter == source ? .isSelected : [])
    }
}
