import Foundation

/// Total projection between the wire tree (identity-bearing) and the on-disk
/// document bundle (identity-free). References are dot-path codes in BOTH
/// representations — uuid↔code resolution happens against the db in
/// Store+Dope hydration/ingest, not here — so this projection is pure
/// structure: drop identity going out, and there is deliberately no inverse
/// that fabricates identity (ingest mints fresh rows; every child uuid
/// changes on every ingest, the locked no-smart-diff consequence).
public enum DopeProjection {

    public static func documents(from tree: DopeScopeTree) -> DopeDocumentBundle {
        // scope_type is deliberately absent: only a SESSION_INSTANCE tree is
        // writable, so persisting it would store a constant.
        let main = DopeScopeDocument(
            version: tree.revision,
            scope: tree.body,
            persistence: Dictionary(uniqueKeysWithValues: tree.domains.map {
                ($0.body.code, DopeScopeDocument.expectedFile(forPersistenceCode: $0.body.code))
            })
        )
        let files = tree.domains.map { domain in
            DopePersistenceFileDocument(
                version: tree.revision,
                body: domain.body,
                entities: domain.entities.map { entity in
                    DopeEntityDocument(
                        body: entity.body,
                        properties: entity.properties.map { DopePropertyDocument(body: $0.body) }
                    )
                },
                enums: domain.enums.map { en in
                    DopeEnumDocument(
                        body: en.body,
                        options: en.options.map { DopeOptionDocument(body: $0.body) }
                    )
                }
            )
        }
        return DopeDocumentBundle(main: main, domainFiles: files)
    }
}
