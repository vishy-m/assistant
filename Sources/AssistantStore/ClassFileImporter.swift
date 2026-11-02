import Foundation
import GRDB

/// Imports class-file bytes for the daemon's `addClassFile` RPC.
///
/// Order matters: validate, check the database, then write with an exclusive
/// create under a server-generated name, then insert the row. A failed insert
/// removes the bytes it just wrote. Nothing here can overwrite an existing file.
public struct ClassFileImporter {
    private let db: AssistantDB
    private let storage: ClassFileStorage

    public init(db: AssistantDB, storage: ClassFileStorage) {
        self.db = db
        self.storage = storage
    }

    /// Returns true when the file is stored (or an identical id was already
    /// imported for this course; its bytes are left untouched). Returns false
    /// for a rejected request, which writes nothing. Throws on I/O or database
    /// failure, after removing any bytes written by this call.
    public func importFile(id: String, courseId: String, folderId: String?,
                           name: String, contentType: String, bytes: Data) throws -> Bool {
        guard !id.isEmpty, id.utf8.count <= 128,
              ClassFileStorage.isSafeComponent(courseId) else { return false }

        let precheck: Bool = try db.queue.read { db in
            guard try Course.fetchOne(db, key: courseId) != nil else { return false }
            if let folderId {
                guard let folder = try ClassFolder.fetchOne(db, key: folderId),
                      folder.courseId == courseId else { return false }
            }
            return true
        }
        guard precheck else { return false }
        if let existing = try ClassFileRepository(db: db).find(id: id) {
            return existing.courseId == courseId
        }

        let ext = Self.sanitizedExtension(of: name)
        let storedName = UUID().uuidString + (ext.map { ".\($0)" } ?? "")
        try storage.writeNew(bytes, courseId: courseId, storedName: storedName)
        do {
            try ClassFileRepository(db: db).create(ClassFile(
                id: id, courseId: courseId, folderId: folderId, name: name,
                storedName: storedName, contentType: contentType, byteSize: bytes.count))
        } catch {
            try? storage.remove(courseId: courseId, storedName: storedName)
            throw error
        }
        return true
    }

    /// The display name's extension if it is 1–8 ASCII letters/digits, else nil.
    public static func sanitizedExtension(of name: String) -> String? {
        let ext = (name as NSString).pathExtension
        guard (1...8).contains(ext.count),
              ext.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return ext
    }
}
