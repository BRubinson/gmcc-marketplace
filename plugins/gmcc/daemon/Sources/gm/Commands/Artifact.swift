import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm artifact add|list — file pointers for prompt-scoped files. Content
/// stays in the files; the daemon only stores pointers.
struct Artifact: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Register and list prompt artifact pointers.",
        subcommands: [Add.self, List.self]
    )

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Register (or update) a file pointer for a prompt.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String
        @Option(name: .long, help: "Path of the artifact file (content stays in the file).")
        var filePath: String
        @Option(name: .long, help: "One-sentence note.")
        var note: String?

        func run() throws {
            let response = try withClient { client in
                try client.addArtifact(ArtifactAddRequest(
                    promptUuid: promptUuid,
                    filePath: filePath,
                    note: note
                ))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] artifact registered: \(response.filePath)")
                print("  uuid: \(response.uuid)")
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List artifact pointers for a prompt.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient { client in
                try client.listArtifacts(ArtifactListRequest(promptUuid: promptUuid))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.artifacts.count) artifact(s)")
                for artifact in response.artifacts {
                    let note = artifact.note.map { " — \($0)" } ?? ""
                    print("  \(artifact.filePath)\(note)")
                }
            }
        }
    }
}
