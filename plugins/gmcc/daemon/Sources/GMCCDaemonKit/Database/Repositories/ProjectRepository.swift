import Foundation
import GRDB

/// Data access for the project table. Runs INSIDE a Store-owned transaction;
/// holds no dbQueue and never self-transacts. `store` grants the shared write
/// primitives only.
struct ProjectRepository {
    let db: Database
    let store: Store

    func update(_ req: ProjectUpdateRequest) throws -> ProjectRow {
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let branch = req.primaryProjectBranch {
            // A branch name is an identity, not prose: reject blank/
            // whitespace outright rather than storing a value the
            // promotion predicate could never match.
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.badRequest(
                    detail: "primary_project_branch must not be blank")
            }
            set["primary_project_branch"] = trimmed
        }
        guard !set.isEmpty else {
            throw StoreError.emptyUpdate(entity: "project")
        }
        try store.updateBase(
            db, table: "project", uuid: req.projectUuid,
            expectedVersion: req.expectedVersion, set: set)
        try store.appendEvent(
            db, kind: .updateProject, subjectUuid: req.projectUuid,
            payload: Store.jsonPayload(["fields": set.keys.sorted()]))
        guard let row = try fetchRow(uuid: req.projectUuid) else {
            throw StoreError.notFound(entity: "project", key: req.projectUuid)
        }
        return row
    }

    func fetchRow(uuid: String) throws -> ProjectRow? {
        try ProjectRecord.fetch(db, uuid: uuid)?.wireRow()
    }
}
