import Foundation
import GRDB

// KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE — the portable-kbite family
// over the frozen m0001 tables. Zero migrations: the document is a FILE
// contract (KbiteArchive), not schema. All file I/O happens OUTSIDE the
// write lock (the digestKbite discipline); the daemon touches exactly one
// JSON file at a client-passed absolute path.

extension Store {
    /// Assemble the scrubbed export document and write it at
    /// `req.dbExportPath`. Read-only against the db — no event.
    public func exportKbite(_ req: KbiteExportRequest) throws -> KbiteExportResponse {
        let (document, fileKeywordCount) = try dbQueue.read { db -> (KbiteExportDocument, Int) in
            guard let kbiteRow = try Row.fetchOne(
                db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [req.code]
            ) else {
                throw StoreError.notFound(entity: "kbite", key: req.code)
            }
            let kbiteUuid: String = kbiteRow["uuid"]

            let kbiteKeywords = try String.fetchAll(db, sql: """
                SELECT kw.keyword FROM keyword kw
                JOIN kbite_keyword_junction j ON j.keyword_uuid = kw.uuid
                WHERE j.kbite_uuid = ? ORDER BY kw.keyword
                """, arguments: [kbiteUuid])

            var fileKeywordCount = 0
            var resources: [KbiteExportDocument.Resource] = []
            for resourceRow in try Row.fetchAll(db, sql: """
                SELECT uuid, resource_name, resource_summary, resource_type, resource_trust
                FROM kbite_resource WHERE kbite_uuid = ? ORDER BY resource_name
                """, arguments: [kbiteUuid]) {
                let resourceUuid: String = resourceRow["uuid"]
                var files: [KbiteExportDocument.File] = []
                for fileRow in try Row.fetchAll(db, sql: """
                    SELECT uuid, resource_file_name, resource_file_summary, resource_file_content
                    FROM kbite_resource_file WHERE kbite_resource_uuid = ?
                    ORDER BY resource_file_name
                    """, arguments: [resourceUuid]) {
                    let fileUuid: String = fileRow["uuid"]
                    let keywords = try String.fetchAll(db, sql: """
                        SELECT kw.keyword FROM keyword kw
                        JOIN resource_file_keyword_junction j ON j.keyword_uuid = kw.uuid
                        WHERE j.file_uuid = ? ORDER BY kw.keyword
                        """, arguments: [fileUuid])
                    fileKeywordCount += keywords.count
                    let content: String? = fileRow["resource_file_content"]
                    files.append(KbiteExportDocument.File(
                        resourceFileName: fileRow["resource_file_name"],
                        resourceFileSummary: KbiteArchive.scrub(
                            fileRow["resource_file_summary"], rules: req.anonymize),
                        resourceFileContent: content.map {
                            KbiteArchive.scrub($0, rules: req.anonymize)
                        },
                        keywords: keywords
                    ))
                }
                resources.append(KbiteExportDocument.Resource(
                    resourceName: resourceRow["resource_name"],
                    resourceSummary: KbiteArchive.scrub(
                        resourceRow["resource_summary"], rules: req.anonymize),
                    resourceType: resourceRow["resource_type"],
                    resourceTrust: resourceRow["resource_trust"],
                    files: files
                ))
            }
            let document = KbiteExportDocument(
                code: req.code,
                exportedAt: Store.isoNow(),
                sourceKbiteUuid: kbiteUuid,
                kbiteKeywords: kbiteKeywords,
                resources: resources
            )
            return (document, fileKeywordCount)
        }

        // File write outside the read/write locks; a failed write must not
        // leave a partial document behind (the Backup.swift discipline).
        let destination = URL(fileURLWithPath: req.dbExportPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try KbiteArchive.encode(document).write(to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        return KbiteExportResponse(
            kbiteUuid: document.sourceKbiteUuid,
            code: req.code,
            resourceCount: document.resources.count,
            fileCount: document.resources.reduce(0) { $0 + $1.files.count },
            kbiteKeywordCount: document.kbiteKeywords.count,
            fileKeywordCount: fileKeywordCount,
            dbExportPath: destination.path
        )
    }

    /// One-transaction import of a db_export.json. Collision `skip` leaves
    /// the existing kbite untouched; `overwrite` replaces content under the
    /// EXISTING kbite uuid (ensureKbite — never delete+reinsert the kbite
    /// row, whose CASCADE would silently drop every scope registration).
    /// Resource/file uuids are re-minted; keywords remap by TEXT through the
    /// shared vocabulary. Never touches registration tables.
    public func importKbite(_ req: KbiteImportRequest) throws -> KbiteImportResponse {
        // Decode + rehydrate outside the write lock.
        let data = try Data(contentsOf: URL(fileURLWithPath: req.dbExportPath))
        let document = try KbiteArchive.decode(data)
        guard document.formatVersion == KbiteArchive.formatVersion else {
            throw StoreError.badRequest(
                detail: "db_export.json format_version \(document.formatVersion) unsupported "
                + "(this daemon reads \(KbiteArchive.formatVersion))")
        }
        let rehydrated = document.rehydrated(rules: req.rehydrate)

        return try dbQueue.write { db in
            let existing = try String.fetchOne(
                db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [rehydrated.code])
            if let existing, req.onCollision == .skip {
                return KbiteImportResponse(
                    kbiteUuid: existing, code: rehydrated.code,
                    imported: false, skippedExisting: true,
                    resourceCount: 0, fileCount: 0, keywordCount: 0)
            }

            let kbiteUuid = try self.ensureKbite(db, code: rehydrated.code)
            // Clean-slate content replace under the stable kbite uuid:
            // resources cascade to files + file junctions; the kbite-level
            // keyword junction is cleared explicitly. Registrations survive.
            try db.execute(
                sql: "DELETE FROM kbite_resource WHERE kbite_uuid = ?", arguments: [kbiteUuid])
            try db.execute(
                sql: "DELETE FROM kbite_keyword_junction WHERE kbite_uuid = ?", arguments: [kbiteUuid])

            var fileCount = 0
            var attachedKeywords: Set<String> = []
            for resource in rehydrated.resources {
                let resourceUuid = try self.insertBase(db, table: "kbite_resource", extra: [
                    "kbite_uuid": kbiteUuid,
                    "resource_name": resource.resourceName,
                    "resource_summary": resource.resourceSummary,
                    "resource_type": resource.resourceType,
                    "resource_trust": resource.resourceTrust,
                ])
                for file in resource.files {
                    let fileUuid = try self.insertBase(db, table: "kbite_resource_file", extra: [
                        "kbite_resource_uuid": resourceUuid,
                        "resource_file_name": file.resourceFileName,
                        "resource_file_summary": file.resourceFileSummary,
                        "resource_file_content": file.resourceFileContent,
                    ])
                    fileCount += 1
                    for keyword in file.keywords {
                        let keywordUuid = try self.ensureKeyword(db, keyword)
                        try self.attachKeyword(
                            db, table: "resource_file_keyword_junction",
                            ownerColumn: "file_uuid", ownerUuid: fileUuid, keywordUuid: keywordUuid)
                        attachedKeywords.insert(keyword)
                    }
                }
            }
            for keyword in rehydrated.kbiteKeywords {
                let keywordUuid = try self.ensureKeyword(db, keyword)
                try self.attachKeyword(
                    db, table: "kbite_keyword_junction",
                    ownerColumn: "kbite_uuid", ownerUuid: kbiteUuid, keywordUuid: keywordUuid)
                attachedKeywords.insert(keyword)
            }

            try self.appendEvent(
                db, kind: .kbiteImport, subjectUuid: kbiteUuid,
                payload: Store.jsonPayload([
                    "code": rehydrated.code,
                    "overwrote_existing": existing != nil,
                    "resources": rehydrated.resources.count,
                    "files": fileCount,
                    "keywords": attachedKeywords.count,
                ]))
            return KbiteImportResponse(
                kbiteUuid: kbiteUuid, code: rehydrated.code,
                imported: true, skippedExisting: false,
                resourceCount: rehydrated.resources.count,
                fileCount: fileCount,
                keywordCount: attachedKeywords.count)
        }
    }

    /// One cascading delete plus shared-vocabulary GC. Registrations going
    /// with the row is the DESIRED behavior here; daemon_event history rows
    /// survive (subject_uuid is not FK'd — append-only ethos holds).
    public func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        try dbQueue.write { db in
            guard let kbiteUuid = try String.fetchOne(
                db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [req.code]
            ) else {
                throw StoreError.notFound(entity: "kbite", key: req.code)
            }
            let resources = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM kbite_resource WHERE kbite_uuid = ?",
                arguments: [kbiteUuid]) ?? 0
            let files = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM kbite_resource_file f
                JOIN kbite_resource r ON r.uuid = f.kbite_resource_uuid
                WHERE r.kbite_uuid = ?
                """, arguments: [kbiteUuid]) ?? 0
            var registrations = 0
            for scope in KbiteScope.allCases {
                registrations += try Int.fetchOne(db, sql:
                    "SELECT COUNT(*) FROM \(scope.rawValue)_active_kbite WHERE kbite_uuid = ?",
                    arguments: [kbiteUuid]) ?? 0
            }

            // CASCADE clears resources/files/junctions/registrations; the
            // FTS AD triggers keep the mirror consistent (recursive ON).
            try db.execute(sql: "DELETE FROM kbite WHERE uuid = ?", arguments: [kbiteUuid])

            // GC keywords no junction references any more (import/delete
            // cycles would otherwise bloat the shared vocabulary forever).
            try db.execute(sql: """
                DELETE FROM keyword WHERE uuid NOT IN (
                    SELECT keyword_uuid FROM kbite_keyword_junction
                    UNION SELECT keyword_uuid FROM resource_file_keyword_junction
                )
                """)
            let gcCount = db.changesCount

            try self.appendEvent(
                db, kind: .kbiteDelete, subjectUuid: kbiteUuid,
                payload: Store.jsonPayload([
                    "code": req.code,
                    "resources": resources,
                    "files": files,
                    "registrations": registrations,
                    "gc_keywords": gcCount,
                ]))
            return KbiteDeleteResponse(
                kbiteUuid: kbiteUuid, code: req.code,
                deletedResources: resources, deletedFiles: files,
                deletedRegistrations: registrations, gcKeywordCount: gcCount)
        }
    }
}

extension KbiteExportDocument {
    /// The whole document with placeholder paths mapped back to this
    /// machine's roots across the four text surfaces.
    func rehydrated(rules: [KbitePrefixRule]) -> KbiteExportDocument {
        KbiteExportDocument(
            formatVersion: formatVersion,
            code: code,
            exportedAt: exportedAt,
            sourceKbiteUuid: sourceKbiteUuid,
            kbiteKeywords: kbiteKeywords,
            resources: resources.map { resource in
                Resource(
                    resourceName: resource.resourceName,
                    resourceSummary: KbiteArchive.rehydrate(resource.resourceSummary, rules: rules),
                    resourceType: resource.resourceType,
                    resourceTrust: resource.resourceTrust,
                    files: resource.files.map { file in
                        File(
                            resourceFileName: file.resourceFileName,
                            resourceFileSummary: KbiteArchive.rehydrate(
                                file.resourceFileSummary, rules: rules),
                            resourceFileContent: file.resourceFileContent.map {
                                KbiteArchive.rehydrate($0, rules: rules)
                            },
                            keywords: file.keywords
                        )
                    }
                )
            }
        )
    }
}
