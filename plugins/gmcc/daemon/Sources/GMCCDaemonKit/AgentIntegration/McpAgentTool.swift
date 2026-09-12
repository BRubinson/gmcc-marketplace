import Foundation
import FoundationModels

/// The MCP / Messages-API wire shape of a tool the OS already models.
///
/// `FoundationModels.Tool` IS the base tool definition — `name`, `description`,
/// and a `parameters` schema synthesized from the `@Generable` Arguments — and
/// `Transcript.ToolDefinition(tool:)` erases any conformer down to exactly
/// those three fields. Nothing here redeclares them; a tool is written once
/// against `Tool` and reaches an on-device model, a server model, and this
/// wire encoding unchanged.
///
/// `GenerationSchema` is `Codable` and encodes as JSON Schema, so `parameters`
/// drops straight into `input_schema`:
///
///     {"type": "object", "title": "Arguments", "additionalProperties": false,
///      "properties": {...}, "required": [...], "x-order": [...]}
///
/// `title` and `x-order` ride along — both are legal (`x-` is the extension
/// prefix) and neither affects validation. `additionalProperties: false` plus
/// `required` is already the shape `strict: true` demands.
@available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
public enum McpAgentTool {
    /// The one spelling difference between the two destinations: MCP's
    /// `tools/list` says `inputSchema`, `/v1/messages` says `input_schema`.
    public enum SchemaKey: String, Sendable {
        case mcp = "inputSchema"
        case messages = "input_schema"
    }

    public static func definition(
        _ tool: some Tool, schemaKey: SchemaKey = .mcp
    ) throws -> [String: Any] {
        try definition(Transcript.ToolDefinition(tool: tool), schemaKey: schemaKey)
    }

    public static func definition(
        _ tool: Transcript.ToolDefinition, schemaKey: SchemaKey = .mcp
    ) throws -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            schemaKey.rawValue: try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(tool.parameters)),
        ]
    }
}
