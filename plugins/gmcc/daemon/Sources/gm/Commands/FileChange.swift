import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm file-change add|list — record file edits in the db and query them back.
struct FileChange: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-change",
        abstract: "Record and query file changes.",
        subcommands: [Add.self, List.self]
    )

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record a file change (session_file, file_change, ranges + FILE_CHANGE event).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Repo-relative path of the changed file.")
        var path: String

        @Option(name: .long, help: "Change kind: edit, create, delete, or rename.")
        var kind: ChangeKind = .edit

        @Option(name: .long, help: #"Line range "start:end" (or a single line "start"). Repeatable."#)
        var range: [String] = []

        @Option(name: .long, help: "Changed text content (applies when exactly one --range is given).")
        var content: String?

        @Option(name: .long, help: "Prompt uuid this change belongs to (optional).")
        var promptUuid: String?

        @Flag(name: .long, help: "Without --prompt-uuid, attribute to the session's active prompt (the PostToolUse hook's flag). Opt-in: omitting it keeps the plain session-scoped semantic.")
        var autoAttribute = false

        func run() throws {
            if content != nil && range.count != 1 {
                throw ValidationError("--content requires exactly one --range")
            }
            let context = try ContextBuilder.ensureRequest()
            let ranges = try parsedRanges()
            let payload = FileChangeAdd(
                project: context.project,
                instance: context.instance,
                session: context.session,
                promptUuid: promptUuid,
                relativePath: path,
                changeKind: kind,
                ranges: ranges,
                autoAttribute: autoAttribute ? true : nil,
                clientKey: autoAttribute ? ClientKey.resolve() : nil
            )
            let response = try withClient { client in
                try client.addFileChange(payload)
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] file change recorded")
                print("  session_file uuid: \(response.sessionFileUuid)")
                print("  file_change uuid:  \(response.fileChangeUuid)")
                print("  ranges:            \(response.rangeUuids.count)")
            }
        }

        private func parsedRanges() throws -> [ChangeRange] {
            try range.map { spec in
                let parts = spec.split(separator: ":", maxSplits: 1)
                guard let first = parts.first, let start = Int(first) else {
                    throw ValidationError(#"bad --range "\#(spec)" — expected "start:end" or "start""#)
                }
                let end: Int
                if parts.count == 2 {
                    guard let parsed = Int(parts[1]) else {
                        throw ValidationError(#"bad --range "\#(spec)" — expected "start:end" or "start""#)
                    }
                    end = parsed
                } else {
                    end = start
                }
                let rangeContent = range.count == 1 ? content : nil
                return ChangeRange(lineStart: start, lineEnd: end, changedContent: rangeContent)
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List file changes for the current session (--all for the whole db).")

        @OptionGroup var output: OutputOptions

        @Option(name: .long, help: "Session uuid (defaults to the current repo/branch session — NOT the whole db; see --all).")
        var sessionUuid: String?

        @Option(name: .long, help: "Filter by prompt uuid.")
        var promptUuid: String?

        @Option(name: .long, help: "Filter by repo-relative path.")
        var path: String?

        @Option(name: .long, help: "Max rows (default 200).")
        var limit: Int?

        @Flag(name: .long, help: "Drop the current-session default and query the whole db (--prompt-uuid/--path still narrow).")
        var all = false

        func validate() throws {
            if all, sessionUuid != nil {
                throw ValidationError("--all cannot be combined with --session-uuid")
            }
        }

        func run() throws {
            let response = try withClient { client in
                let session = all
                    ? nil
                    : try sessionUuid ?? ContextBuilder.resolveSessionUuid(client)
                return try client.listFileChanges(FileChangeListRequest(
                    sessionUuid: session,
                    promptUuid: promptUuid,
                    relativePath: path,
                    limit: limit
                ))
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.changes.count) file change(s)")
                for change in response.changes {
                    let ranges = change.ranges.map { "\($0.lineStart):\($0.lineEnd)" }.joined(separator: ",")
                    let prompt = change.promptUuid.map { " prompt=\($0.prefix(8))" } ?? ""
                    print("  \(change.createdAt)  \(change.changeKind)  \(change.relativePath)  [\(ranges)]\(prompt)")
                }
            }
        }
    }
}
