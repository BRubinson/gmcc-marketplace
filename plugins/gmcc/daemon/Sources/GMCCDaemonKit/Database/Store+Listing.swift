import Foundation
import GRDB

// PROJECT_LIST / INSTANCE_LIST / SESSION_LIST — read-only enumeration, the
// Landing browse surface. Parent uuids are optional filters: nil lists the
// whole level; a supplied-but-unknown parent is a typed NOT_FOUND, never a
// silent empty list. No daemon_event rows (reads only).
// Bodies live in ListingRepository; these wrappers own the transaction.

extension Store {
    public func listProjects() throws -> ProjectListResponse {
        try dbQueue.read { db in try ListingRepository(db: db, core: core).listProjects() }
    }

    public func listInstances(_ req: InstanceListRequest) throws -> InstanceListResponse {
        try dbQueue.read { db in try ListingRepository(db: db, core: core).listInstances(req) }
    }

    public func listSessions(_ req: SessionListRequest) throws -> SessionListResponse {
        try dbQueue.read { db in try ListingRepository(db: db, core: core).listSessions(req) }
    }

    /// Shared SessionStub materializer for listSessions and
    /// INSTANCE_CURRENT_SESSION (both select the same column list).
    ///
    /// `static` because repositories call it and can no longer name a Store
    /// VALUE. A static is a namespace, not coupling: it cannot return a Store,
    /// cannot reach dbQueue, and cannot re-enter a transaction. It reads no
    /// instance state, so this is a keyword change and nothing more.
    ///
    /// It stays a hand mapper deliberately: last_activity_at is a computed
    /// MAX() across session/prompt/file_change, not a column on any table, so
    /// SessionRecord.wireRow() cannot synthesize it. Half 1 replaces the body
    /// with SessionStubRecord.
    static func sessionStub(from row: Row) -> SessionStub {
        SessionStub(
            uuid: row["uuid"],
            version: row["version"],
            instanceUuid: row["instance_uuid"],
            code: row["code"],
            name: row["name"],
            ckfsRelativeStoragePath: row["ckfs_relative_storage_path"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            lastActivityAt: row["last_activity_at"]
        )
    }
}
