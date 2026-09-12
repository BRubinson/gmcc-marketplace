import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm agent register — the SPAWNER's authority write for one agent it just
/// spawned.
///
/// Called by the thing that holds the agent_id and the intent: a workflow
/// script, or the primary driving a tier. It is the one named exception to
/// "workflow scripts never touch gm", and it is identity only — never prompt
/// content, never a report.
///
/// NOT on the pen surface, deliberately: an agent registering itself is the
/// self-reported identity this registry replaces.
struct Agent: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Agent registry: register.",
        subcommands: [Register.self]
    )

    struct Register: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record who a spawned agent IS: role, methodology and the phase it was spawned for. Merges onto the identity the SubagentStart hook records — fields you omit keep their current value, and registering LATE still explains rows the agent already wrote.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "The agent id the spawn handed back. Opaque — never parsed.")
        var agentId: String

        @Option(name: .long, help: "What this agent was spawned to do (explorer, architect, reviewer, implementer…).")
        var role: String?

        @Option(name: .long, help: "The persona/methodology this agent runs — what tells four same-typed agents apart.")
        var methodology: String?

        @Option(name: .long, help: "The workflow phase it was spawned for (the spawner's claim; file_change rows carry the phase the daemon derives).")
        var phase: String?

        func run() throws {
            let response = try withClient { client -> AgentRegisterResponse in
                try client.agentRegister(AgentRegisterRequest(
                    agentId: agentId, role: role, methodology: methodology,
                    workflowPhase: phase))
            }
            if output.json { printJSON(response) } else {
                let r = response.registration
                let identity = r.agentType.map { " [\($0)]" } ?? ""
                print("[gm] agent \(response.created ? "registered" : "updated")\(identity): \(r.agentId)")
                if let role = r.role { print("  role:        \(role)") }
                if let methodology = r.methodology { print("  methodology: \(methodology)") }
                if let phase = r.workflowPhase { print("  phase:       \(phase)") }
            }
        }
    }
}
