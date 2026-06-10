import Foundation

/// A folder DTO node with its child folders and direct files. UI value type.
public struct FileTreeFolder: Equatable, Identifiable {
    public let folder: ClassFolderDTO
    public let folders: [FileTreeFolder]
    public let files: [ClassFileDTO]
    public var id: String { folder.id }
    public init(folder: ClassFolderDTO, folders: [FileTreeFolder], files: [ClassFileDTO]) {
        self.folder = folder; self.folders = folders; self.files = files
    }
}

/// Root of the file tree for the UI: top-level folders + loose files.
public struct FileTree: Equatable {
    public let folders: [FileTreeFolder]
    public let files: [ClassFileDTO]
    public init(folders: [FileTreeFolder], files: [ClassFileDTO]) {
        self.folders = folders; self.files = files
    }
}

/// Pure flat → nested builder over the boundary DTOs. Folders whose parent is
/// missing are promoted to the root (nothing dropped). Folders sort by
/// (sortOrder, name); files by name.
public enum FileTreeBuilder {
    public static func build(folders: [ClassFolderDTO], files: [ClassFileDTO]) -> FileTree {
        let validIds = Set(folders.map(\.id))
        var children: [String: [ClassFolderDTO]] = [:]
        var rootFolders: [ClassFolderDTO] = []
        for f in folders {
            if let p = f.parentFolderId, validIds.contains(p) {
                children[p, default: []].append(f)
            } else { rootFolders.append(f) }
        }
        var filesByFolder: [String: [ClassFileDTO]] = [:]
        var rootFiles: [ClassFileDTO] = []
        for file in files {
            if let fid = file.folderId, validIds.contains(fid) {
                filesByFolder[fid, default: []].append(file)
            } else { rootFiles.append(file) }
        }
        func less(_ a: ClassFolderDTO, _ b: ClassFolderDTO) -> Bool {
            a.sortOrder != b.sortOrder ? a.sortOrder < b.sortOrder : a.name < b.name
        }
        func node(_ folder: ClassFolderDTO) -> FileTreeFolder {
            FileTreeFolder(
                folder: folder,
                folders: (children[folder.id] ?? []).sorted(by: less).map(node),
                files: (filesByFolder[folder.id] ?? []).sorted { $0.name < $1.name })
        }
        return FileTree(
            folders: rootFolders.sorted(by: less).map(node),
            files: rootFiles.sorted { $0.name < $1.name })
    }
}
