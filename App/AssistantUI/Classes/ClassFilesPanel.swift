import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AssistantShared

/// The left Files panel: a folder/file tree with create / rename / delete /
/// move and import (NSOpenPanel + Finder drop). Files are draggable (Phase 3
/// drops them on the canvas; here, dragging a file onto a folder moves it).
struct ClassFilesPanel: View {
    @ObservedObject var store: ClassStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EyebrowLabel("Files")
                Spacer()
                Button { importViaPanel(into: nil) } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("Import a file")
                Button { store.createFolder(name: "New Folder", parentId: nil) } label: {
                    Image(systemName: "folder.badge.plus")
                }.buttonStyle(.plain).help("New folder")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(store.fileTree.folders) { folderRow($0, depth: 0) }
                    ForEach(store.fileTree.files) { fileRow($0, depth: 0) }
                    if store.fileTree.folders.isEmpty && store.fileTree.files.isEmpty {
                        Text("No files yet. ＋ to import.")
                            .font(.caption).foregroundStyle(.tertiary).padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers, into: nil); return true
        }
    }

    private func folderRow(_ node: FileTreeFolder, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    Text(node.folder.name).font(GradeTheme.mono(11)).lineLimit(1)
                }
                .padding(.leading, CGFloat(depth) * 12)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Import file here") { importViaPanel(into: node.folder.id) }
                    Button("New subfolder") { store.createFolder(name: "New Folder", parentId: node.folder.id) }
                    Button("Rename") { renameFolder(node.folder) }
                    Button("Delete", role: .destructive) { store.deleteFolder(id: node.folder.id) }
                }
                .onDrop(of: [.fileURL, .text], isTargeted: nil) { providers in
                    handleDrop(providers, into: node.folder.id); return true
                }
                ForEach(node.folders) { folderRow($0, depth: depth + 1) }
                ForEach(node.files) { fileRow($0, depth: depth + 1) }
            }
        )
    }

    private func fileRow(_ file: ClassFileDTO, depth: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc").foregroundStyle(.secondary)
            Text(file.name).font(GradeTheme.mono(11)).lineLimit(1)
        }
        .padding(.leading, CGFloat(depth) * 12 + 14)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { store.openFileTab(id: file.id) }
        .onDrag { NSItemProvider(object: file.id as NSString) }
        .contextMenu {
            Button("Rename") { renameFile(file) }
            Button("Delete", role: .destructive) { store.deleteFile(id: file.id) }
        }
    }

    private func importViaPanel(into folderId: String?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls { store.importFile(at: url, folderId: folderId) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], into folderId: String?) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { store.importFile(at: url, folderId: folderId) } }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    if let id = value as? String {
                        DispatchQueue.main.async { store.moveFile(id: id, toFolder: folderId) }
                    }
                }
            }
        }
    }

    private func renameFolder(_ folder: ClassFolderDTO) {
        promptRename(folder.name) { store.renameFolder(id: folder.id, name: $0) }
    }
    private func renameFile(_ file: ClassFileDTO) {
        promptRename(file.name) { store.renameFile(id: file.id, name: $0) }
    }

    private func promptRename(_ current: String, _ commit: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { commit(name) }
        }
    }
}
