import ArgumentParser
import Foundation
import GMCCDaemonKit

// gm — the single GMCC CLI. A socket client of gmcc_daemon; never touches
// the db file directly (single-writer invariant). One subcommand per wire
// message (wire version: GMCCWireProtocol.version), grouped by family.
//
// Exit codes: 0 ok · 1 generic/db error · 2 daemon unreachable after
// autostart · 3 unrecoverable protocol mismatch.

struct GM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gm",
        abstract: "GMCC daemon client — context, sessions, prompts, artifacts, file changes, events.",
        subcommands: [
            Setup.self, Cheatsheet.self, Doctor.self, Status.self, Ping.self, Daemon.self, Backup.self, Events.self,
            Context.self, Project.self, Instance.self, Session.self, Catalog.self, Search.self,
            Prompt.self,
            Clarify.self, Arch.self, Explore.self, Review.self, Briefing.self, Dope.self, Cog.self, Diagram.self,
            Render.self,
            Artifact.self, PromptDiagram.self, FileChange.self,
            Kbite.self,
            PathsCmd.self, Config.self, Sandbox.self,
        ]
    )
}

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit the raw JSON response instead of human-readable output.")
    var json = false
}

/// Print a DaemonClientError and return the documented gm exit code
/// (2 unreachable · 3 protocol mismatch · 1 everything else). Shared by
/// withClient, `gm daemon stop`, and the events --follow stream teardown.
func gmExitCode(for error: DaemonClientError) -> ExitCode {
    switch error {
    case .unreachable(let message):
        FileHandle.standardError.write(Data("[gm] daemon unreachable: \(message)\n".utf8))
        return ExitCode(2)
    case .protocolMismatch(let message, _):
        FileHandle.standardError.write(Data("[gm] protocol mismatch: \(message)\n".utf8))
        return ExitCode(3)
    case .server(let payload):
        FileHandle.standardError.write(Data("[gm] daemon error \(payload.codeRaw): \(payload.message)\n".utf8))
        return ExitCode(1)
    case .wire(let message):
        FileHandle.standardError.write(Data("[gm] wire error: \(message)\n".utf8))
        return ExitCode(1)
    }
}

/// Run a client operation, mapping DaemonClientError onto the gm exit codes.
func withClient<T>(_ body: (DaemonClient) throws -> T) throws -> T {
    let client = DaemonClient()
    defer { client.close() }
    do {
        return try body(client)
    } catch let error as DaemonClientError {
        throw gmExitCode(for: error)
    }
}

func printJSON<T: Encodable>(_ value: T) {
    // WireCodec, not a bare JSONEncoder: DTOs carry no CodingKeys, so only the
    // shared snake_case strategy keeps --json output matching the wire keys
    // that skills and bot docs grep for.
    if let data = try? WireCodec.prettyEncoder.encode(value),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

GM.main()
