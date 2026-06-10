import Foundation

public struct ClassFolderDTO: Codable, Identifiable, Equatable {
    public let id: String
    public let courseId: String
    public let parentFolderId: String?
    public let name: String
    public let sortOrder: Int
    public init(id: String, courseId: String, parentFolderId: String?,
                name: String, sortOrder: Int) {
        self.id = id
        self.courseId = courseId
        self.parentFolderId = parentFolderId
        self.name = name
        self.sortOrder = sortOrder
    }
}

public struct ClassFileDTO: Codable, Identifiable, Equatable {
    public let id: String
    public let courseId: String
    public let folderId: String?
    public let name: String
    public let storedName: String
    public let contentType: String
    public let byteSize: Int
    public init(id: String, courseId: String, folderId: String?, name: String,
                storedName: String, contentType: String, byteSize: Int) {
        self.id = id
        self.courseId = courseId
        self.folderId = folderId
        self.name = name
        self.storedName = storedName
        self.contentType = contentType
        self.byteSize = byteSize
    }
}

public struct ClassPinDTO: Codable, Identifiable, Equatable {
    public let id: String
    public let courseId: String
    public let fileId: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let rotation: Double
    public let zOrder: Int
    public init(id: String, courseId: String, fileId: String, x: Double, y: Double,
                width: Double, height: Double, rotation: Double, zOrder: Int) {
        self.id = id
        self.courseId = courseId
        self.fileId = fileId
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zOrder = zOrder
    }
}
