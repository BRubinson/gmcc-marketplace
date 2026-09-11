import Foundation
import GRDB

// FILE_CHANGE_ADD / FILE_CHANGE_LIST — the original add_file_change
// capability plus the query side that replaces grepping changed_files: lists.
// Bodies live in FileChangeRepository; these wrappers own the transaction.

extension Store {
    public func addFileChange(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        try dbQueue.write { db in try FileChangeRepository(db: db, store: self).add(req) }
    }

    public func listFileChanges(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        try dbQueue.read { db in try FileChangeRepository(db: db, store: self).list(req) }
    }

    // MARK: - Cross-domain helper forward

    func ensureSessionFile(
        _ db: Database,
        sessionUuid: String,
        relativePath: String,
        changeKind: ChangeKind
    ) throws -> String {
        try FileChangeRepository(db: db, store: self).ensureSessionFile(
            sessionUuid: sessionUuid, relativePath: relativePath, changeKind: changeKind)
    }
}
