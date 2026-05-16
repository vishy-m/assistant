import Foundation

/// Bundles a course's categories and items for the `listGradeData` RPC.
/// The category/item element shape matches AssistantStore's GradeCategory/GradeItem
/// Codable representation, but this DTO stays dependency-free so AssistantShared
/// does not need to import AssistantStore.
public struct GradeDataDTO: Codable, Equatable {
    public let categoriesJSON: Data
    public let itemsJSON: Data

    public init(categoriesJSON: Data, itemsJSON: Data) {
        self.categoriesJSON = categoriesJSON
        self.itemsJSON = itemsJSON
    }
}
