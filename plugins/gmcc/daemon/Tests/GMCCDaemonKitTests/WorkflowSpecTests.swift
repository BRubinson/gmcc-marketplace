import XCTest
@testable import GMCCDaemonKit

/// The bot workflow registry's drift guards (the CheatsheetTests precedent
/// scaled to the state machine): every (variant, phase) pair must carry
/// instruction text, every phase graph must be well-formed, and the MCP pen
/// roster must stay in lockstep with the agent defs that name its tools —
/// a naming mistake here bricks every agent pen under the all-or-nothing
/// MCP migration.
final class WorkflowSpecTests: XCTestCase {

    // MARK: - Phase graphs

    func testEveryVariantPhaseHasInstructions() {
        for variant in BotVariant.allCases {
            let phases = WorkflowSpec.phases(for: variant)
            XCTAssertGreaterThan(phases.count, 5, "\(variant) graph looks broken")
            XCTAssertEqual(phases.first, .briefing, "\(variant) must start at briefing")
            XCTAssertEqual(phases.last, .done, "\(variant) must end at done")
            XCTAssertEqual(
                phases.count, Set(phases).count, "\(variant) graph repeats a phase")
            for phase in phases {
                let text = WorkflowSpec.instructions(variant: variant, phase: phase)
                XCTAssertFalse(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "(\(variant), \(phase)) has no instruction text")
            }
        }
    }

    func testExpectedExplorationAgentsAreWellFormed() {
        for variant in BotVariant.allCases {
            let agents = WorkflowSpec.expectedExplorationAgents(for: variant)
            XCTAssertFalse(agents.isEmpty, "\(variant) expects no exploration agents")
            // The synthesis row is the SEAL — never an expected worker.
            XCTAssertFalse(
                agents.contains(.synthesis),
                "\(variant) lists synthesis as an expected agent")
        }
        XCTAssertEqual(WorkflowSpec.expectedExplorationAgents(for: .team).count, 4)
        XCTAssertEqual(WorkflowSpec.expectedExplorationAgents(for: .bot), [.general])
        XCTAssertEqual(WorkflowSpec.expectedExplorationAgents(for: .rpi), [.general])
    }

    func testVariantGraphShapes() {
        // Only team runs the options flow; bot skips the care package.
        XCTAssertFalse(WorkflowSpec.phases(for: .bot).contains(.carePackage))
        XCTAssertFalse(WorkflowSpec.phases(for: .bot).contains(.archOptions))
        XCTAssertTrue(WorkflowSpec.phases(for: .rpi).contains(.carePackage))
        XCTAssertFalse(WorkflowSpec.phases(for: .rpi).contains(.archOptions))
        XCTAssertTrue(WorkflowSpec.phases(for: .team).contains(.archOptions))
    }

    // MARK: - MCP pen roster parity

    /// plugins/gmcc/, located from this file (the DocsContractTests trick).
    private var pluginRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The pen tools gmcc_mcp serves, read from its SOURCE (the executable
    /// target cannot be imported here; the literal names are what the agent
    /// defs and allowlists must match anyway).
    private func mcpToolNames() throws -> [String] {
        let source = pluginRoot.appendingPathComponent("daemon/Sources/gmcc_mcp/main.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        var names: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name: \"") {
                names.append(String(trimmed.dropFirst(7).dropLast(2)))
            }
        }
        return names
    }

    func testMcpPenRosterIsComplete() throws {
        let names = try mcpToolNames()
        XCTAssertGreaterThan(names.count, 12, "tool roster parse looks broken")
        XCTAssertEqual(names.count, Set(names).count, "duplicate MCP tool names")
        // The pen surface: every agent-facing write + the search reads.
        for expected in [
            "bot_next", "bot_get", "bot_current_prompt", "bot_summary",
            "briefing_get", "briefing_complete",
            "explore_key_file_add", "explore_finding_add", "explore_complete",
            "review_finding_add",
            "clarify_question_add", "clarify_note_add",
            "care_package_get", "care_ref_add",
            "arch_option_add",
            "file_change_add",
            "dope_search", "kbite_search", "kbite_file_get",
        ] {
            XCTAssertTrue(names.contains(expected), "MCP pen roster is missing \(expected)")
        }
        // Primary-only verbs must NEVER appear — the MCP surface IS the pen
        // contract, physically enforced.
        for forbidden in ["rank", "decide", "set_status", "finalize", "approve"] {
            XCTAssertFalse(
                names.contains(where: { $0.contains(forbidden) }),
                "primary-only verb '\(forbidden)' leaked into the MCP pen surface")
        }
    }

    /// Every agent def that names MCP tools must use the plugin-scoped
    /// prefix (a bare mcp__gmcc__ matcher never fires) and only roster names.
    func testAgentDefsUseScopedRosterNames() throws {
        let fm = FileManager.default
        let agentsDir = pluginRoot.appendingPathComponent("agents", isDirectory: true)
        guard fm.fileExists(atPath: agentsDir.path) else { return }
        let roster = Set(try mcpToolNames())
        let enumerator = fm.enumerator(at: agentsDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                text.contains("mcp__gmcc__"),
                "\(url.lastPathComponent) uses the bare mcp__gmcc__ prefix — plugin tools are mcp__plugin_gmcc_pen__*")
            for match in text.split(whereSeparator: { " \n,()[]`'\"".contains($0) })
            where match.hasPrefix("mcp__plugin_gmcc_pen__") {
                let tool = String(match.dropFirst("mcp__plugin_gmcc_pen__".count))
                XCTAssertTrue(
                    roster.contains(tool),
                    "\(url.lastPathComponent) names unknown MCP tool '\(tool)'")
            }
        }
    }
}
