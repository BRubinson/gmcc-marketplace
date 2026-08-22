import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm prompt create|list|get|update-content|set-status — the prompt
/// lifecycle over the daemon. Content edits are Draft-only (CONTENT_LOCKED
/// after), transitions are forward-only (INVALID_TRANSITION otherwise), and
/// both are guarded by --expected-version (VERSION_CONFLICT when stale).
struct Prompt: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create and manage prompts.",
        subcommands: [Create.self, List.self, Get.self, UpdateContent.self, SetStatus.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a prompt (daemon allocates the next per-session seq).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Session uuid (defaults to the current repo/branch session).")
        var sessionUuid: String?

        @Option(name: .long) var name: String
        @Option(name: .long, help: "Defaults to p{seq}.") var code: String?
        @Option(name: .long) var backstory: String?
        @Option(name: .long) var goal: String?
        @Option(name: .long) var detail: String?
        @Option(name: .long, help: "Bot command that will run this prompt (e.g. /gm_bot).")
        var command: String?
        @Option(name: .long, help: "Reuse a ckfs uuid for the db row.")
        var uuid: String?

        func run() throws {
            let response = try withClient { client in
                let session = try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
                return try client.createPrompt(PromptCreateRequest(
                    sessionUuid: session,
                    uuid: uuid,
                    code: code,
                    name: name,
                    backstory: backstory ?? "",
                    goal: goal ?? "",
                    detail: detail ?? "",
                    command: command
                ))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] prompt created: seq \(response.seq) (\(response.name))")
                print("  uuid: \(response.uuid)")
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List prompt stubs for a session.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Session uuid (defaults to the current repo/branch session).")
        var sessionUuid: String?

        func run() throws {
            let response = try withClient { client in
                let session = try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
                return try client.listPrompts(PromptListRequest(sessionUuid: session))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.prompts.count) prompt(s)")
                for stub in response.prompts {
                    print("  \(stub.seq). \(stub.name) [\(stub.status)] v\(stub.version) \(stub.uuid)")
                }
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Full prompt: content, artifacts, kbites, change summary.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { client in
                try client.getPrompt(PromptGetRequest(promptUuid: promptUuid))
            }
            if output.json {
                printJSON(response)
            } else {
                let p = response.prompt
                print("[gm] prompt \(p.seq): \(p.name) [\(p.status)] v\(p.version)")
                print("  uuid:    \(p.uuid)")
                print("  command: \(p.command.isEmpty ? "—" : p.command)")
                print("  kbites:  \(response.kbiteCodes.isEmpty ? "—" : response.kbiteCodes.joined(separator: ", "))")
                print("  artifacts:")
                for artifact in response.artifacts {
                    print("    [\(artifact.kind)] \(artifact.filePath)")
                }
                let c = response.changeSummary
                print("  changes: \(c.changeCount) across \(c.distinctFiles) file(s)")
            }
        }
    }

    struct UpdateContent: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update-content",
            abstract: "Edit backstory/goal/detail while Draft (CONTENT_LOCKED after).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String
        @Option(name: .long, help: "The prompt version this edit was based on.")
        var expectedVersion: Int64
        @Option(name: .long) var backstory: String?
        @Option(name: .long) var goal: String?
        @Option(name: .long) var detail: String?

        func run() throws {
            let response = try withClient { client in
                try client.updatePromptContent(PromptUpdateContentRequest(
                    promptUuid: promptUuid,
                    expectedVersion: expectedVersion,
                    backstory: backstory,
                    goal: goal,
                    detail: detail
                ))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] prompt content updated: seq \(response.seq) v\(response.version)")
            }
        }
    }

    struct SetStatus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-status",
            abstract: "Forward-only transition: draft → clarifying → clarified.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String
        @Option(name: .long, help: "The prompt version this transition was based on.")
        var expectedVersion: Int64
        @Option(name: .long, help: "draft, clarifying, or clarified")
        var status: PromptStatus

        func run() throws {
            let response = try withClient { client in
                try client.setPromptStatus(PromptSetStatusRequest(
                    promptUuid: promptUuid,
                    expectedVersion: expectedVersion,
                    status: status
                ))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] prompt \(response.seq) → \(response.status) (v\(response.version))")
            }
        }
    }
}
