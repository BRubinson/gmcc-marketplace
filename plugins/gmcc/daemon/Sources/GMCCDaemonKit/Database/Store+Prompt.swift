import Foundation
import GRDB

// PROMPT_CREATE / PROMPT_LIST / PROMPT_GET / PROMPT_UPDATE_CONTENT /
// PROMPT_SET_STATUS — the prompt lifecycle, with the STAY TRUE convention
// (Draft-only content edits) and the forward-only transition table enforced
// here rather than by convention.
// Bodies live in PromptRepository; these wrappers own the transaction.

extension Store {
    public func createPrompt(_ req: PromptCreateRequest) throws -> PromptRow {
        try dbQueue.write { db in try PromptRepository(db: db, store: self).create(req) }
    }

    public func listPrompts(_ req: PromptListRequest) throws -> PromptListResponse {
        try dbQueue.read { db in try PromptRepository(db: db, store: self).list(req) }
    }

    public func getPrompt(_ req: PromptGetRequest) throws -> PromptGetResponse {
        try dbQueue.read { db in try PromptRepository(db: db, store: self).get(req) }
    }

    public func updatePromptContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        try dbQueue.write { db in try PromptRepository(db: db, store: self).updateContent(req) }
    }

    public func setPromptStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        try dbQueue.write { db in try PromptRepository(db: db, store: self).setStatus(req) }
    }

    // MARK: - Cross-domain helper forward

    func fetchPromptRow(_ db: Database, uuid: String) throws -> PromptRow? {
        try PromptRepository(db: db, store: self).fetchRow(uuid: uuid)
    }
}
