import Foundation

/// A folder node with its child folders and direct files. Pure value type.
public struct FolderNode: Equatable {
    public let folder: ClassFolder
    public let folders: [FolderNode]
    public let files: [ClassFile]
}

/// The root of a class's file tree: top-level folders + loose files.
public struct ClassFileTree: Equatable {
    public let folders: [FolderNode]
    public let files: [ClassFile]
}

/// Builds a nested tree from flat rows. Folders whose parent is missing are
/// promoted to the root (no rows are silently dropped). Ordering: folders by
/// (sortOrder, name); files by name.
public enum FolderTreeAssembler {
    public static func build(folders: [ClassFolder], files: [ClassFile]) -> ClassFileTree {
        let validIds = Set(folders.map(\.id))
        var childFolders: [String: [ClassFolder]] = [:]
        var rootFolders: [ClassFolder] = []
        for f in folders {
            if let p = f.parentFolderId, validIds.contains(p) {
                childFolders[p, default: []].append(f)
            } else {
                rootFolders.append(f)   // nil OR dangling parent → root
            }
        }
        var filesByFolder: [String: [ClassFile]] = [:]
        var rootFiles: [ClassFile] = []
        for file in files {
            if let fid = file.folderId, validIds.contains(fid) {
                filesByFolder[fid, default: []].append(file)
            } else {
                rootFiles.append(file)
            }
        }
        func sortFolders(_ a: ClassFolder, _ b: ClassFolder) -> Bool {
            a.sortOrder != b.sortOrder ? a.sortOrder < b.sortOrder : a.name < b.name
        }
        func node(_ folder: ClassFolder) -> FolderNode {
            FolderNode(
                folder: folder,
                folders: (childFolders[folder.id] ?? []).sorted(by: sortFolders).map(node),
                files: (filesByFolder[folder.id] ?? []).sorted { $0.name < $1.name })
        }
        return ClassFileTree(
            folders: rootFolders.sorted(by: sortFolders).map(node),
            files: rootFiles.sorted { $0.name < $1.name })
    }
}
