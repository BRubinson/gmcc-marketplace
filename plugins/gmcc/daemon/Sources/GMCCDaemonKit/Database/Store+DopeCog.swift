import Foundation
import GRDB

// COGS CRUD. A cog is a named grouping inside a dope scope; its elements are
// typed nodes whose per-type metadata lives in a subtype table chosen by the
// DopeCogElementSpec registry.
//
// Deliberately a peer family (`gm cog`) rather than more `gm dope *-` verbs,
// matching the in-repo precedent that `gm diagram` is a peer family over dope
// rather than `gm dope diagram-*`.

extension Store {

    // MARK: - Cog

    public func dopeCogAdd(_ req: DopeCogAddRequest) throws -> DopeCogResponse {
        try DopeCode.validateCode(req.code, field: "cog code")
        return try dbQueue.write { db in
            guard let scope = try self.fetchDopeScope(db, uuid: req.scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
            }
            let uuid = try self.insertBase(db, table: "dope_cog", extra: [
                "dope_scope_uuid": req.scopeUuid,
                "code": req.code, "name": req.name,
                "description": req.description ?? "",
                "sort_order": req.sortOrder ?? 0,
            ])
            let revision = try self.bumpScopeRevision(
                db, scopeUuid: req.scopeUuid, area: .cogs, ownerUuid: uuid)
            try self.recordDopeChange(db, scope: scope, action: "cog_add", level: nil,
                                      nodeUuid: uuid, revision: revision)
            return try self.fetchCogResponse(db, uuid: uuid, revision: revision)
        }
    }

    public func dopeCogUpdate(_ req: DopeCogUpdateRequest) throws -> DopeCogResponse {
        try dbQueue.write { db in
            var set: [String: (any DatabaseValueConvertible)?] = [:]
            if let code = req.code {
                try DopeCode.validateCode(code, field: "cog code")
                set["code"] = code
            }
            if let name = req.name { set["name"] = name }
            if let description = req.description { set["description"] = description }
            if let sortOrder = req.sortOrder { set["sort_order"] = sortOrder }
            guard !set.isEmpty else { throw StoreError.emptyUpdate(entity: "dope_cog") }

            let scope = try self.cogOwningScope(db, cogUuid: req.uuid)
            try self.updateBase(db, table: "dope_cog", uuid: req.uuid,
                                expectedVersion: req.expectedVersion, set: set)
            let revision = try self.bumpScopeRevision(
                db, scopeUuid: scope.uuid, area: .cogs, ownerUuid: req.uuid)
            try self.recordDopeChange(db, scope: scope, action: "cog_update", level: nil,
                                      nodeUuid: req.uuid, revision: revision)
            return try self.fetchCogResponse(db, uuid: req.uuid, revision: revision)
        }
    }

    public func dopeCogDelete(_ req: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        try dbQueue.write { db in
            let scope = try self.cogOwningScope(db, cogUuid: req.uuid)
            let elements = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_cog_element WHERE dope_cog_uuid = ?
                """, arguments: [req.uuid]) ?? 0

            if req.soft == true {
                guard scope.tier?.isOverlay == true else {
                    throw StoreError.badRequest(
                        detail: "--soft is only valid inside a masking scope; scope "
                              + "\(scope.uuid) is \(scope.scopeType)")
                }
                try self.updateBase(db, table: "dope_cog", uuid: req.uuid,
                                    expectedVersion: req.expectedVersion,
                                    set: ["deleted_on": Store.isoNow()])
            } else {
                try self.deleteBase(db, table: "dope_cog", uuid: req.uuid,
                                    expectedVersion: req.expectedVersion)
            }
            let revision = try self.bumpScopeRevision(db, scopeUuid: scope.uuid)
            try self.recordDopeChange(db, scope: scope, action: "cog_delete", level: nil,
                                      nodeUuid: req.uuid, revision: revision)
            return DopeCogDeleteResponse(deletedUuid: req.uuid, cascadedElements: elements,
                                         scopeUuid: scope.uuid, revision: revision)
        }
    }

    // MARK: - Elements

    public func dopeCogElementAdd(
        _ req: DopeCogElementAddRequest
    ) throws -> DopeCogElementResponse {
        try DopeCode.validateCode(req.code, field: "cog element code")
        let spec = try DopeCogElementSpec.spec(for: req.elementType)
        return try dbQueue.write { db in
            guard try Row.fetchOne(db, sql: "SELECT uuid FROM dope_cog WHERE uuid = ?",
                                   arguments: [req.cogUuid]) != nil else {
                throw StoreError.notFound(entity: "dope_cog", key: req.cogUuid)
            }
            let scope = try self.cogOwningScope(db, cogUuid: req.cogUuid)

            if let parent = req.parentElementUuid {
                guard let parentType = try String.fetchOne(db, sql: """
                    SELECT element_type FROM dope_cog_element WHERE uuid = ?
                    """, arguments: [parent]) else {
                    throw StoreError.notFound(entity: "dope_cog_element", key: parent)
                }
                guard let allowed = spec.allowedParentTypes,
                      allowed.contains(where: { $0.rawValue == parentType }) else {
                    throw StoreError.badRequest(
                        detail: "element type '\(spec.type.rawValue)' is top-level only "
                              + "and cannot be parented under '\(parentType)'")
                }
            }

            // primary_path is the subtype table's only required field, so a
            // missing one is a precise BAD_REQUEST rather than an FK error.
            guard spec.ownedFields.contains(.primaryPath), let primaryPath = req.primaryPath,
                  !primaryPath.isEmpty else {
                throw StoreError.badRequest(
                    detail: "element type '\(spec.type.rawValue)' requires --primary-path")
            }

            let uuid = try self.insertBase(db, table: "dope_cog_element", extra: [
                "dope_cog_uuid": req.cogUuid,
                "parent_element_uuid": req.parentElementUuid,
                "element_type": spec.type.rawValue,
                "code": req.code, "name": req.name,
                "description": req.description ?? "",
                "sort_order": req.sortOrder ?? 0,
                "dope_scope_code": req.dopeScopeCode,
            ])
            _ = try self.insertBase(db, table: spec.subtypeTable, extra: [
                "element_uuid": uuid,
                "primary_path": primaryPath,
            ])
            let revision = try self.bumpScopeRevision(
                db, scopeUuid: scope.uuid, area: .cogs, ownerUuid: req.cogUuid)
            try self.recordDopeChange(db, scope: scope, action: "cog_element_add", level: nil,
                                      nodeUuid: uuid, revision: revision)
            return try self.fetchCogElementResponse(db, uuid: uuid, revision: revision)
        }
    }

    public func dopeCogElementUpdate(
        _ req: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        try dbQueue.write { db in
            guard let typeRaw = try String.fetchOne(db, sql: """
                SELECT element_type FROM dope_cog_element WHERE uuid = ?
                """, arguments: [req.uuid]) else {
                throw StoreError.notFound(entity: "dope_cog_element", key: req.uuid)
            }
            let spec = try DopeCogElementSpec.spec(for: typeRaw)
            let scope = try self.elementOwningScope(db, elementUuid: req.uuid)

            var set: [String: (any DatabaseValueConvertible)?] = [:]
            if let code = req.code {
                try DopeCode.validateCode(code, field: "cog element code")
                set["code"] = code
            }
            if let name = req.name { set["name"] = name }
            if let description = req.description { set["description"] = description }
            if let sortOrder = req.sortOrder { set["sort_order"] = sortOrder }
            if req.clearDopeScopeCode == true {
                set["dope_scope_code"] = nil
            } else if let binding = req.dopeScopeCode {
                set["dope_scope_code"] = binding
            }

            if let primaryPath = req.primaryPath {
                guard spec.ownedFields.contains(.primaryPath) else {
                    throw StoreError.badRequest(
                        detail: "element type '\(typeRaw)' does not own --primary-path")
                }
                try db.execute(sql: """
                    UPDATE \(spec.subtypeTable) SET primary_path = ?, updated_at = ?
                     WHERE element_uuid = ?
                    """, arguments: [primaryPath, Store.isoNow(), req.uuid])
            } else if set.isEmpty {
                throw StoreError.emptyUpdate(entity: "dope_cog_element")
            }

            if !set.isEmpty {
                try self.updateBase(db, table: "dope_cog_element", uuid: req.uuid,
                                    expectedVersion: req.expectedVersion, set: set)
            }
            let revision = try self.bumpScopeRevision(
                db, scopeUuid: scope.uuid, area: .cogs,
                ownerUuid: try self.owningCogUuid(db, elementUuid: req.uuid))
            try self.recordDopeChange(db, scope: scope, action: "cog_element_update", level: nil,
                                      nodeUuid: req.uuid, revision: revision)
            return try self.fetchCogElementResponse(db, uuid: req.uuid, revision: revision)
        }
    }

    public func dopeCogElementDelete(
        _ req: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        try dbQueue.write { db in
            let scope = try self.elementOwningScope(db, elementUuid: req.uuid)
            // Captured BEFORE the delete — a hard delete removes the row this
            // lookup reads, and the area counter still has to be advanced.
            let cogUuid = try self.owningCogUuid(db, elementUuid: req.uuid)
            let children = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM dope_cog_element WHERE parent_element_uuid = ?
                """, arguments: [req.uuid]) ?? 0
            if req.soft == true {
                guard scope.tier?.isOverlay == true else {
                    throw StoreError.badRequest(
                        detail: "--soft is only valid inside a masking scope; scope "
                              + "\(scope.uuid) is \(scope.scopeType)")
                }
                try self.updateBase(db, table: "dope_cog_element", uuid: req.uuid,
                                    expectedVersion: req.expectedVersion,
                                    set: ["deleted_on": Store.isoNow()])
            } else {
                try self.deleteBase(db, table: "dope_cog_element", uuid: req.uuid,
                                    expectedVersion: req.expectedVersion)
            }
            let revision = try self.bumpScopeRevision(
                db, scopeUuid: scope.uuid, area: .cogs,
                ownerUuid: cogUuid)
            try self.recordDopeChange(db, scope: scope, action: "cog_element_delete", level: nil,
                                      nodeUuid: req.uuid, revision: revision)
            return DopeCogDeleteResponse(deletedUuid: req.uuid, cascadedElements: children,
                                         scopeUuid: scope.uuid, revision: revision)
        }
    }

    // MARK: - Read

    public func dopeCogGet(_ req: DopeCogGetRequest) throws -> DopeCogGetResponse {
        try dbQueue.read { db in
            guard try self.fetchDopeScope(db, uuid: req.scopeUuid) != nil else {
                throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
            }
            var sql = "SELECT * FROM dope_cog WHERE dope_scope_uuid = ?"
            var args: [(any DatabaseValueConvertible)?] = [req.scopeUuid]
            if let code = req.code {
                sql += " AND code = ?"
                args.append(code)
            }
            sql += " ORDER BY sort_order, code"
            let cogs = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return DopeCogGetResponse(cogs: try cogs.map { row in
                try self.hydrateCog(db, row: row)
            })
        }
    }

    // MARK: - Helpers

    private func cogOwningScope(_ db: Database, cogUuid: String) throws -> DopeScopeRow {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT s.* FROM dope_scope s
            JOIN dope_cog c ON c.dope_scope_uuid = s.uuid
            WHERE c.uuid = ?
            """, arguments: [cogUuid]) else {
            throw StoreError.notFound(entity: "dope_cog", key: cogUuid)
        }
        return Self.dopeScopeRow(row)
    }

    private func owningCogUuid(_ db: Database, elementUuid: String) throws -> String {
        guard let uuid = try String.fetchOne(db, sql: """
            SELECT dope_cog_uuid FROM dope_cog_element WHERE uuid = ?
            """, arguments: [elementUuid]) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: elementUuid)
        }
        return uuid
    }

    private func elementOwningScope(_ db: Database, elementUuid: String) throws -> DopeScopeRow {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT s.* FROM dope_scope s
            JOIN dope_cog c ON c.dope_scope_uuid = s.uuid
            JOIN dope_cog_element e ON e.dope_cog_uuid = c.uuid
            WHERE e.uuid = ?
            """, arguments: [elementUuid]) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: elementUuid)
        }
        return Self.dopeScopeRow(row)
    }

    private func hydrateCog(_ db: Database, row: Row) throws -> DopeCogNode {
        let elements = try Row.fetchAll(db, sql: """
            SELECT * FROM dope_cog_element WHERE dope_cog_uuid = ?
            ORDER BY sort_order, code
            """, arguments: [row["uuid"] as String])
        return DopeCogNode(
            uuid: row["uuid"], version: row["version"], code: row["code"], name: row["name"],
            description: row["description"], sortOrder: row["sort_order"],
            deletedOn: row["deleted_on"],
            elements: try elements.map { try self.hydrateElement(db, row: $0) })
    }

    private func hydrateElement(_ db: Database, row: Row) throws -> DopeCogElementNode {
        let spec = try DopeCogElementSpec.spec(for: row["element_type"] as String)
        let primaryPath = try String.fetchOne(db, sql: """
            SELECT primary_path FROM \(spec.subtypeTable) WHERE element_uuid = ?
            """, arguments: [row["uuid"] as String])
        return DopeCogElementNode(
            uuid: row["uuid"], version: row["version"], elementType: row["element_type"],
            code: row["code"], name: row["name"], description: row["description"],
            sortOrder: row["sort_order"], parentElementUuid: row["parent_element_uuid"],
            dopeScopeCode: row["dope_scope_code"], primaryPath: primaryPath,
            deletedOn: row["deleted_on"])
    }

    private func fetchCogResponse(
        _ db: Database, uuid: String, revision: Int64
    ) throws -> DopeCogResponse {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM dope_cog WHERE uuid = ?",
                                         arguments: [uuid]) else {
            throw StoreError.notFound(entity: "dope_cog", key: uuid)
        }
        return DopeCogResponse(cog: try hydrateCog(db, row: row), revision: revision)
    }

    private func fetchCogElementResponse(
        _ db: Database, uuid: String, revision: Int64
    ) throws -> DopeCogElementResponse {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT * FROM dope_cog_element WHERE uuid = ?
            """, arguments: [uuid]) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: uuid)
        }
        return DopeCogElementResponse(element: try hydrateElement(db, row: row),
                                      revision: revision)
    }
}
