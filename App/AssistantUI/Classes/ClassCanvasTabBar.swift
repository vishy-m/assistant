import SwiftUI
import AppKit
import AssistantShared

/// Tab bar atop the class canvas: a permanent Board tab + one tab per open file.
struct ClassCanvasTabBar: View {
    @ObservedObject var store: ClassStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                tab(title: "Board", systemImage: "square.grid.2x2",
                    active: store.tabs.isBoardActive,
                    onSelect: { store.selectBoardTab() },
                    onClose: nil)
                ForEach(store.tabs.openFileIds, id: \.self) { id in
                    tab(title: store.file(id: id)?.name ?? "File", systemImage: "doc",
                        active: store.tabs.activeFileId == id,
                        onSelect: { store.selectFileTab(id: id) },
                        onClose: { store.closeFileTab(id: id) })
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func tab(title: String, systemImage: String, active: Bool,
                     onSelect: @escaping () -> Void,
                     onClose: (() -> Void)?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 10))
            Text(title).font(GradeTheme.mono(11)).lineLimit(1)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help("Close tab")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
