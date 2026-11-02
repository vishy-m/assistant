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
        try db.queue.write { db in
            try Self.validateParent(db, folderId: folder.id, courseId: folder.courseId,
                                    parentId: folder.parentFolderId)
            try folder.insert(db)
        }
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
            try Self.validateParent(db, folderId: id, courseId: f.courseId, parentId: parentId)
            f.parentFolderId = parentId; f.updatedAt = Date(); try f.update(db)
        }
    }

    /// Every file row in the folder and its descendants, without deleting
    /// anything. The daemon unlinks these bytes before dropping the rows.
    public func filesInSubtree(id: String) throws -> [ClassFile] {
        try db.queue.read { db in
            let folderIds = try Self.subtreeIds(db, root: id)
            return try ClassFile.filter(folderIds.contains(Column("folder_id"))).fetchAll(db)
        }
    }

    /// Deletes a folder and all descendant folders, their files, and those
    /// files' pins. Returns every removed file row so the daemon can delete the
    /// bytes from each file's own course directory. Terminates on a legacy
    /// parent cycle.
    @discardableResult
    public func deleteRecursively(id: String) throws -> [ClassFile] {
        try db.queue.write { db in
            let folderIds = try Self.subtreeIds(db, root: id)
            let files = try ClassFile.filter(folderIds.contains(Column("folder_id"))).fetchAll(db)
            let fileIds = files.map(\.id)
            if !fileIds.isEmpty {
                try ClassPin.filter(fileIds.contains(Column("file_id"))).deleteAll(db)
                try ClassFile.filter(fileIds.contains(Column("id"))).deleteAll(db)
            }
            try ClassFolder.filter(folderIds.contains(Column("id"))).deleteAll(db)
            return files
        }
    }

    /// `root` plus all descendants, visiting each id once.
    private static func subtreeIds(_ db: Database, root: String) throws -> [String] {
        var folderIds: [String] = [root]
        var visited: Set<String> = [root]
        var frontier: [String] = [root]
        while !frontier.isEmpty {
            let children = try String.fetchAll(db, sql:
                "SELECT id FROM class_folder WHERE parent_folder_id IN (\(placeholders(frontier.count)))",
                arguments: StatementArguments(frontier))
            frontier = children.filter { visited.insert($0).inserted }
            folderIds.append(contentsOf: frontier)
        }
        return folderIds
    }

    /// A parent must exist, belong to the same course, and not be the folder
    /// itself or one of its descendants. nil (root) is always allowed.
    private static func validateParent(_ db: Database, folderId: String, courseId: String,
                                       parentId: String?) throws {
        guard let parentId else { return }
        guard parentId != folderId else { throw ClassFilesIntegrityError.folderCycle }
        guard let parent = try ClassFolder.fetchOne(db, key: parentId) else {
            throw ClassFilesIntegrityError.missingFolder(parentId)
        }
        guard parent.courseId == courseId else { throw ClassFilesIntegrityError.crossCourse }
        // Walk up from the new parent; reaching `folderId` means a cycle.
        var visited: Set<String> = [parentId]
        var cursor = parent.parentFolderId
        while let next = cursor {
            if next == folderId { throw ClassFilesIntegrityError.folderCycle }
            guard visited.insert(next).inserted else { break }   // legacy cycle above
            cursor = try String.fetchOne(db, sql:
                "SELECT parent_folder_id FROM class_folder WHERE id = ?", arguments: [next])
        }
    }

    private static func placeholders(_ n: Int) -> String {
        Array(repeating: "?", count: n).joined(separator: ",")
    }
}

public enum ClassFilesIntegrityError: Error, Equatable {
    case folderCycle
    case missingFolder(String)
    case crossCourse
}
