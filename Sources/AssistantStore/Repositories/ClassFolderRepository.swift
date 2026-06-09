import Foundation
import GRDB

public struct ClassFolderRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func all(courseId: String) throws -> [ClassFolder] {
        try db.queue.read { db in
            try ClassFolder.filter(Column("course_id") == courseId)
                .order(Column("sort_order"), Column("name")).fetchAll(db)
        }
    }

    public func find(id: String) throws -> ClassFolder? {
        try db.queue.read { db in try ClassFolder.fetchOne(db, key: id) }
    }

    public func create(_ folder: ClassFolder) throws {
        try db.queue.write { db in try folder.insert(db) }
    }

    public func rename(id: String, name: String) throws {
        try db.queue.write { db in
            guard var f = try ClassFolder.fetchOne(db, key: id) else { return }
            f.name = name; f.updatedAt = Date(); try f.update(db)
        }
    }

    public func move(id: String, toParent parentId: String?) throws {
        try db.queue.write { db in
            guard var f = try ClassFolder.fetchOne(db, key: id) else { return }
            f.parentFolderId = parentId; f.updatedAt = Date(); try f.update(db)
        }
    }

    /// Deletes a folder and all descendant folders, their files, and those
    /// files' pins. Returns every removed file's `stored_name` so the daemon can
    /// delete the bytes.
    @discardableResult
    public func deleteRecursively(id: String) throws -> [String] {
        try db.queue.write { db in
            var folderIds: [String] = [id]
            var frontier: [String] = [id]
            while !frontier.isEmpty {
                let children = try String.fetchAll(db, sql:
                    "SELECT id FROM class_folder WHERE parent_folder_id IN (\(placeholders(frontier.count)))",
                    arguments: StatementArguments(frontier))
                folderIds.append(contentsOf: children)
                frontier = children
            }
            let files = try ClassFile.filter(folderIds.contains(Column("folder_id"))).fetchAll(db)
            let fileIds = files.map(\.id)
            if !fileIds.isEmpty {
                try ClassPin.filter(fileIds.contains(Column("file_id"))).deleteAll(db)
                try ClassFile.filter(fileIds.contains(Column("id"))).deleteAll(db)
            }
            try ClassFolder.filter(folderIds.contains(Column("id"))).deleteAll(db)
            return files.map(\.storedName)
        }
    }

    private func placeholders(_ n: Int) -> String {
        Array(repeating: "?", count: n).joined(separator: ",")
    }
}
