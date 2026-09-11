// GENERATED-then-maintained: read-side Record structs mirroring the live db
// schema (sqlite_master truth). Deliberately FetchableRecord ONLY — never
// PersistableRecord: all writes route through Store.insertBase/updateBase/
// deleteBase so the version-gate and BaseEntity defaults stay single-sourced.
// Timestamps are TEXT ISO-8601 Z strings (lexicographic ordering contract) —
// never Date.

import Foundation
import GRDB

/// Read-side mirror of the `diagram` table. Columns map via convertFromSnakeCase.
struct DiagramRecord: BaseRecordFields {
    static let databaseTableName = "diagram"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var projectUuid: String
    var sessionUuid: String?
    var promptUuid: String?
    var tier: String
    var code: String
    var name: String
    var description: String
    var gmccDiagramPath: String?
    var dopeScopeCode: String?
    var kbiteCode: String?
    var revision: Int64
    var visibility: String
}

/// Read-side mirror of the `diagram_element` table. Columns map via convertFromSnakeCase.
struct DiagramElementRecord: BaseRecordFields {
    static let databaseTableName = "diagram_element"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var diagramUuid: String
    var parentElementUuid: String?
    var elementType: String
    var code: String
    var name: String
    var description: String
    var sortOrder: Int64
    var centerX: Double
    var centerY: Double
    var elementZ: Double
    var scale: Double
}

/// Read-side mirror of the `diagram_connector` table. Columns map via convertFromSnakeCase.
struct DiagramConnectorRecord: BaseRecordFields {
    static let databaseTableName = "diagram_connector"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var targetElementUuid: String?
    var strokeColor: String
    var strokeWidth: Double
    var lineStyle: String
    var headKind: String
    var label: String
    var routingKind: String
    var tailKind: String
}

/// Read-side mirror of the `diagram_uml_node` table. Columns map via convertFromSnakeCase.
struct DiagramUmlNodeRecord: BaseRecordFields {
    static let databaseTableName = "diagram_uml_node"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var elementUuid: String
    var nodeKind: String
    var width: Double
    var height: Double
    var markdown: String
    var fontSize: Double?
    var textColor: String?
    var strokeColor: String?
    var strokeWidth: Double?
    var fillColor: String?
}

/// Read-side mirror of the `diagram_shape_vertex` table. Columns map via convertFromSnakeCase.
struct DiagramShapeVertexRecord: BaseRecordFields {
    static let databaseTableName = "diagram_shape_vertex"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var shapeElementUuid: String
    var seq: Int64
    var x: Double
    var y: Double
}

/// Read-side mirror of the `diagram_stroke_vertex` table. Columns map via convertFromSnakeCase.
struct DiagramStrokeVertexRecord: BaseRecordFields {
    static let databaseTableName = "diagram_stroke_vertex"
    var id: Int64
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var strokeElementUuid: String
    var seq: Int64
    var x: Double
    var y: Double
    var pressure: Double?
}
