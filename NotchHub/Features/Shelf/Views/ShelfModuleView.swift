import SwiftUI

/// Main shelf module: a horizontal row of items that is also a drop destination.
struct ShelfModuleView: View {
    private static let cornerRadius: CGFloat = 14
    private static let tileSpacing: CGFloat = 6
    private static let headerFontSize: CGFloat = 12
    private static let dropBorderWidth: CGFloat = 1.5
    private static let dropDash: [CGFloat] = [6, 4]

    let store: ShelfStore

    @State private var selection = ShelfSelection()
    @State private var isDropTargeted = false

    init(store: ShelfStore) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if store.items.isEmpty {
                emptyState
            } else {
                itemRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .background(dropHighlight)
        .contentShape(.rect)
        .onDrop(of: ShelfStore.acceptedDropTypes, isTargeted: $isDropTargeted) { providers in
            store.handleDrop(providers: providers)
        }
        .onChange(of: store.items) { _, items in
            selection.prune(keeping: Set(items.map(\.id)))
        }
        .animation(.snappy(duration: 0.2), value: isDropTargeted)
        .animation(.snappy(duration: 0.25), value: store.items)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Label("Raf", systemImage: "tray.full")
                .font(.system(size: Self.headerFontSize, weight: .semibold))
                .foregroundStyle(.primary)
            if store.hasItems {
                Text("\(store.count)")
                    .font(.system(size: Self.headerFontSize - 1, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(.quaternary, in: .capsule)
            }
            Spacer(minLength: 0)
            ShelfHeaderButton(title: "Yapıştır", systemImage: "doc.on.clipboard") {
                store.pasteFromClipboard()
            }
            .help("Pano içeriğini rafa ekle")
            ShelfHeaderButton(title: "Temizle", systemImage: "trash") {
                selection.clear()
                store.removeAll()
            }
            .disabled(!store.hasItems)
            .help("Raftaki tüm öğeleri kaldır")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: isDropTargeted)
            Text("Dosyaları buraya bırak")
                .font(.system(size: 12, weight: .semibold))
            Text("Dosyalar, metinler ve görseller sürükleyip çıkarana kadar burada kalır.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemRow: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.tileSpacing) {
                ForEach(store.items) { item in
                    ShelfItemTile(
                        item: item,
                        isSelected: selection.contains(item.id),
                        handlers: handlers(for: item),
                        quickActions: quickActions(for: item)
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .scrollIndicators(.never)
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(isDropTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear))
            .strokeBorder(
                isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                style: StrokeStyle(lineWidth: Self.dropBorderWidth, dash: store.hasItems && !isDropTargeted ? [] : Self.dropDash)
            )
            .opacity(isDropTargeted || !store.hasItems ? 1 : 0)
    }

    // MARK: - Interaction

    private func targets(for item: ShelfItem) -> [ShelfItem] {
        store.items(with: selection.targetIDs(for: item.id, orderedBy: store.items.map(\.id)))
    }

    private func handlers(for item: ShelfItem) -> ShelfMouseHandlers {
        ShelfMouseHandlers(
            onPress: { toggling in selection.press(item.id, toggling: toggling) },
            onRelease: { toggling, didDrag in selection.release(item.id, toggling: toggling, didDrag: didDrag) },
            onDoubleClick: { ShelfActions.open(targets(for: item), store: store) },
            dragItems: { targets(for: item) },
            onDragActive: { store.isDraggingOut = $0 },
            onHover: { _ in },
            onKey: { command in handle(command, on: item) },
            menu: { contextMenu(for: item) }
        )
    }

    private func handle(_ command: ShelfKeyCommand, on item: ShelfItem) {
        switch command {
        case .quickLook:
            quickLook(item)
        case .delete:
            store.remove(ids: Set(targets(for: item).map(\.id)))
        }
    }

    private func quickLook(_ item: ShelfItem) {
        ShelfQuickLook.shared.toggle(targets(for: item).compactMap(store.previewURL(for:)))
    }

    private func contextMenu(for item: ShelfItem) -> NSMenu {
        if !selection.contains(item.id) { selection.select(item.id) }
        let preview = [
            ShelfTileAction(id: "quickLook", title: "Hızlı Bakış", systemImage: "eye") { quickLook(item) },
            ShelfTileAction(id: "open", title: "Aç", systemImage: "arrow.up.forward.app") {
                ShelfActions.open(targets(for: item), store: store)
            },
        ]
        return ShelfTileAction.menu(primary: preview, secondary: quickActions(for: item))
    }

    private func quickActions(for item: ShelfItem) -> [ShelfTileAction] {
        var actions = [
            ShelfTileAction(id: "airDrop", title: "AirDrop", systemImage: "paperplane") {
                ShelfActions.airDrop(targets(for: item), store: store)
            },
        ]
        if item.isFile {
            actions.append(ShelfTileAction(id: "reveal", title: "Finder'da Göster", systemImage: "folder") {
                ShelfActions.revealInFinder(targets(for: item))
            })
        }
        actions.append(ShelfTileAction(id: "copy", title: "Kopyala", systemImage: "doc.on.doc") {
            store.copyToPasteboard(targets(for: item).map(\.id))
        })
        actions.append(ShelfTileAction(id: "remove", title: "Raftan Kaldır", systemImage: "xmark", isDestructive: true) {
            store.remove(ids: Set(targets(for: item).map(\.id)))
        })
        return actions
    }
}

private struct ShelfHeaderButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(isHovered ? 1 : 0.5), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .scaleEffect(isHovered && isEnabled ? 1.04 : 1)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.12), value: isHovered)
    }
}
