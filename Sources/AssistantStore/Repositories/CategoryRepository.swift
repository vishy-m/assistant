import Foundation
import GRDB

public struct CategoryRepository {
    private let db: AssistantDB
    public init(db: AssistantDB) { self.db = db }

    public func all() throws -> [Category] {
        try db.queue.read { db in
            try Category.order(Column("name")).fetchAll(db)
        }
    }

    public func find(name: String) throws -> Category? {
        try db.queue.read { db in try Category.fetchOne(db, key: name) }
    }

    /// Case-insensitively resolves a name to a stored category, falling back to
    /// the default category (and finally a hardcoded Misc if the table is empty).
    public func resolve(_ name: String?) throws -> Category {
        let categories = try all()
        if let name,
           let match = categories.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return match
        }
        if let def = categories.first(where: { $0.isDefault }) { return def }
        return Category(name: "Misc", colorHex: "8A8F98", isDefault: true)
    }

    public func create(_ category: Category) throws {
        try db.queue.write { db in try category.insert(db) }
    }

    /// Updates a category. If the name changed, cascades the rename to every
    /// event and task carrying the old name.
    public func update(originalName: String, to category: Category) throws {
        try db.queue.write { db in
            if originalName != category.name {
                try db.execute(
                    sql: "UPDATE gcal_event_cache SET category = ? WHERE category = ?",
                    arguments: [category.name, originalName])
                try db.execute(
                    sql: "UPDATE task SET category = ? WHERE category = ?",
                    arguments: [category.name, originalName])
                try db.execute(sql: "DELETE FROM category WHERE name = ?",
                               arguments: [originalName])
                try category.insert(db)
            } else {
                try category.update(db)
            }
        }
    }

    /// Deletes a category and reassigns its events/tasks to the default
    /// category. The default category itself cannot be deleted.
    public func delete(name: String) throws {
        try db.queue.write { db in
            guard let cat = try Category.fetchOne(db, key: name), !cat.isDefault else { return }
            let fallback = try Category.filter(Column("is_default") == true)
                .fetchOne(db)?.name ?? "Misc"
            try db.execute(sql: "UPDATE gcal_event_cache SET category = ? WHERE category = ?",
                           arguments: [fallback, name])
            try db.execute(sql: "UPDATE task SET category = ? WHERE category = ?",
                           arguments: [fallback, name])
            try db.execute(sql: "DELETE FROM category WHERE name = ?", arguments: [name])
        }
    }

    /// Cached events currently tagged with a category — used by the recolor
    /// cascade.
    public func events(category: String) throws -> [GCalEventCache] {
        try db.queue.read { db in
            try GCalEventCache.filter(Column("category") == category).fetchAll(db)
        }
    }
}
