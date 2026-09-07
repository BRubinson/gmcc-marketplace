import Foundation
import GRDB

// PROJECT_UPDATE — the first project-level mutation in the CLI. Until m0011
// the project table carried nothing a user could configure, so `gm project`
// had only `list`.
//
// Today the single settable field is primary_project_branch (the prompt's
// BASE_DOPED_BRANCH): the branch whose SESSION_INSTANCE dope scope is
// allowed to promote into the project's BASE_PROJECT scope. It is a project
// setting rather than an instance one on purpose — it "applies across
// instances a consistent behavior".
//
// Standard optimistic-lock shape, identical to updateSession: updateBase
// enforces --expected-version and bumps version + updated_at, one durable
// event carries the changed field names, and a fresh row is returned so the
// caller never has to re-read to learn the new version.

extension Store {
    public func updateProject(_ req: ProjectUpdateRequest) throws -> ProjectRow {
        try dbQueue.write { db in
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
            try self.updateBase(
                db, table: "project", uuid: req.projectUuid,
                expectedVersion: req.expectedVersion, set: set)
            try self.appendEvent(
                db, kind: .updateProject, subjectUuid: req.projectUuid,
                payload: Store.jsonPayload(["fields": set.keys.sorted()]))
            guard let row = try self.fetchProjectRow(db, uuid: req.projectUuid) else {
                throw StoreError.notFound(entity: "project", key: req.projectUuid)
            }
            return row
        }
    }

    func fetchProjectRow(_ db: Database, uuid: String) throws -> ProjectRow? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT uuid, version, git_repo_name, code, name,
                       ckfs_relative_storage_path, primary_project_branch,
                       created_at, updated_at
                FROM project WHERE uuid = ?
                """,
            arguments: [uuid]
        ) else { return nil }
        return ProjectRow(
            uuid: row["uuid"],
            version: row["version"],
            gitRepoName: row["git_repo_name"],
            code: row["code"],
            name: row["name"],
            ckfsRelativeStoragePath: row["ckfs_relative_storage_path"],
            primaryProjectBranch: row["primary_project_branch"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
