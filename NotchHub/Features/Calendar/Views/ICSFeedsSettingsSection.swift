import SwiftUI

/// Add / rename / test / remove published ICS feeds.
struct ICSFeedsSettingsSection: View {
    private let source: ICSFeedSource
    @State private var newName = ""
    @State private var newURL = ""
    @State private var addMessage: String?
    @State private var isTestingNew = false
    @State private var testResults: [ICSFeed.ID: String] = [:]

    init(source: ICSFeedSource) {
        self.source = source
    }

    var body: some View {
        Section {
            Text("Web'de Outlook › Ayarlar › Takvim › Paylaşılan takvimler › Takvim yayınla, ardından ICS bağlantısını kopyalayın. Herhangi bir https:// veya webcal:// akışı çalışır. Bağlantı okuma erişimi verdiği için Anahtar Zinciri'nde saklanır.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(source.feeds) { feed in
                ICSFeedRow(
                    feed: feed,
                    status: source.feedStatus[feed.id],
                    testResult: testResults[feed.id],
                    onRename: { source.renameFeed(id: feed.id, to: $0) },
                    onTest: { test(feed) },
                    onRemove: { source.removeFeed(id: feed.id) }
                )
            }

            TextField("Ad", text: $newName, prompt: Text("İş takvimi"))
            SecureField("ICS bağlantısı", text: $newURL, prompt: Text("https://outlook.office365.com/owa/calendar/…/calendar.ics"))
            HStack {
                if let addMessage {
                    Text(addMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if isTestingNew { ProgressView().controlSize(.small) }
                Button("Test Et") { testNew() }
                    .disabled(trimmedURL.isEmpty || isTestingNew)
                Button("Akış Ekle") { add() }
                    .disabled(trimmedURL.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        } header: {
            Text("ICS Takvim Akışları")
        }
    }

    private var trimmedURL: String {
        newURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        do {
            try source.addFeed(name: newName, urlString: trimmedURL)
            newName = ""
            newURL = ""
            addMessage = "Akış eklendi. Eşitleniyor…"
        } catch {
            addMessage = error.localizedDescription
        }
    }

    private func testNew() {
        isTestingNew = true
        addMessage = "Test ediliyor…"
        let url = trimmedURL
        Task {
            let result = await source.testFeed(urlString: url)
            addMessage = result.message
            isTestingNew = false
        }
    }

    private func test(_ feed: ICSFeed) {
        testResults[feed.id] = "Test ediliyor…"
        Task {
            testResults[feed.id] = await source.testFeed(id: feed.id).message
        }
    }
}

private struct ICSFeedRow: View {
    let feed: ICSFeed
    let status: ICSFeedStatus?
    let testResult: String?
    let onRename: (String) -> Void
    let onTest: () -> Void
    let onRemove: () -> Void
    @State private var name: String

    init(
        feed: ICSFeed,
        status: ICSFeedStatus?,
        testResult: String?,
        onRename: @escaping (String) -> Void,
        onTest: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.feed = feed
        self.status = status
        self.testResult = testResult
        self.onRename = onRename
        self.onTest = onTest
        self.onRemove = onRemove
        _name = State(initialValue: feed.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(feed.color.color)
                    .frame(width: 8, height: 8)
                Image(systemName: feed.kind.systemImage)
                    .foregroundStyle(.secondary)
                    .help(feed.kind.displayName)
                TextField("Ad", text: $name)
                    .labelsHidden()
                    .onSubmit { onRename(name) }
                    .onChange(of: name) { _, newValue in onRename(newValue) }
                Button("Test Et", action: onTest)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .help("Akışı kaldır ve bağlantısını Anahtar Zinciri'nden sil")
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(status?.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .lineLimit(2)
        }
    }

    private var statusText: String {
        if let testResult { return testResult }
        if let error = status?.errorMessage { return error }
        guard let status, let lastSync = status.lastSync else { return "Henüz eşitlenmedi" }
        let count = status.eventCount.map { $0 == 1 ? "1 etkinlik" : "\($0) etkinlik" } ?? "Eşitlendi"
        return "\(count) · eşitlendi \(lastSync.formatted(.relative(presentation: .named)))"
    }
}
