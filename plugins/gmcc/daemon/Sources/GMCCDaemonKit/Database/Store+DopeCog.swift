import Foundation
import GRDB

// COGS CRUD. A cog is a named grouping inside a dope scope; its elements are
// typed nodes whose per-type metadata lives in a subtype table chosen by the
// DopeCogElementSpec registry.
//
// Deliberately a peer family (`gm cog`) rather than more `gm dope *-` verbs,
// matching the in-repo precedent that `gm diagram` is a peer family over dope
// rather than `gm dope diagram-*`.
// Bodies live in DopeCogRepository; these wrappers own the transaction.

extension Store {
    public func dopeCogAdd(_ req: DopeCogAddRequest) throws -> DopeCogResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, store: self).dopeCogAdd(req) }
    }

    public func dopeCogUpdate(_ req: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, store: self).dopeCogUpdate(req) }
    }

    public func dopeCogDelete(_ req: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, store: self).dopeCogDelete(req) }
    }

    public func dopeCogElementAdd(
        _ req: DopeCogElementAddRequest
    ) throws -> DopeCogElementResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, store: self).dopeCogElementAdd(req) }
    }

    public func dopeCogElementUpdate(
        _ req: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, store: self).dopeCogElementUpdate(req) }
    }

    public func dopeCogElementDelete(
        _ req: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try dbQueue.write { db in try DopeCogRepository(db: db, store: self).dopeCogElementDelete(req) }
    }

    public func dopeCogGet(_ req: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try dbQueue.read { db in try DopeCogRepository(db: db, store: self).dopeCogGet(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Every cog of a scope, hydrated, for callers already inside a
    /// transaction — the repo write path needs cogs alongside the
    /// persistence tree.
    func fetchDopeCogs(_ db: Database, scopeUuid: String) throws -> [DopeCogNode] {
        try DopeCogRepository(db: db, store: self).fetchDopeCogs(scopeUuid: scopeUuid)
    }
}
