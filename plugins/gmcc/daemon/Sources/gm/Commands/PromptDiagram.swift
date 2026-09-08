import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm prompt-diagram qualify|get|list — a prompt's standing reading of a
/// rendered diagram.
///
/// The picture is not the understanding. A rendered canvas tells a later
/// reader what the shapes ARE; it cannot tell them what this prompt concluded
/// from looking at it. That sentence is the whole surface — which is why
/// there is no status machine, no findings and no reopen edge here. One row
/// per (prompt, diagram), re-qualifying replaces it.
///
/// The three render fields make staleness answerable: the fingerprint is the
/// sidecar written beside the PNG, so a reader can tell whether this reading
/// was written about the picture that exists today.
struct PromptDiagram: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record and read a prompt's qualification of a rendered diagram.",
        subcommands: [Qualify.self, Get.self, List.self]
    )

    /// Exactly one of the inline / file form, mirroring the report verbs'
    /// overview pair: a qualification written from a real reading runs long
    /// enough to meet the argv budget well before the daemon's own cap.
    private static func resolveText(
        label: String, inline: String?, file: String?
    ) throws -> String {
        switch (inline, file) {
        case (let inline?, nil):
            return inline
        case (nil, let file?):
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                throw ValidationError("cannot read --\(label)-file: \(file)")
            }
            return content
        case (nil, nil):
            throw ValidationError("pass --\(label) or --\(label)-file")
        default:
            throw ValidationError("--\(label) and --\(label)-file are mutually exclusive")
        }
    }

    struct Qualify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record (or replace) what this prompt makes of a rendered diagram.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String
        @Option(name: .long) var diagramUuid: String
        @Option(name: .long, help: "Path of the image that was read.")
        var renderedPath: String
        @Option(name: .long, help: "The diagram revision that image was made from.")
        var renderedRevision: Int64
        @Option(name: .long, help: "The fingerprint sidecar's JSON, verbatim.")
        var renderFingerprint: String?
        @Option(name: .long, help: "Read the fingerprint JSON from the sidecar file instead.")
        var renderFingerprintFile: String?
        @Option(name: .long, help: "What this prompt concludes the diagram means.")
        var qualification: String?
        @Option(name: .long, help: "Read the qualification from a file instead.")
        var qualificationFile: String?

        func run() throws {
            let fingerprint = try PromptDiagram.resolveText(
                label: "render-fingerprint",
                inline: renderFingerprint, file: renderFingerprintFile)
            let body = try PromptDiagram.resolveText(
                label: "qualification", inline: qualification, file: qualificationFile)
            let response = try withClient {
                try $0.promptDiagramQualify(PromptDiagramQualifyRequest(
                    promptUuid: promptUuid, diagramUuid: diagramUuid,
                    renderedPath: renderedPath, renderedRevision: renderedRevision,
                    renderFingerprint: fingerprint, qualification: body))
            }
            if output.json { printJSON(response) } else {
                print("[gm] qualified \(response.diagramUuid) at r\(response.renderedRevision) "
                    + "(v\(response.version))")
                print("  uuid: \(response.uuid)")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "One qualification: name the diagram, or omit it when the prompt has exactly one.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String
        @Option(name: .long) var diagramUuid: String?

        func run() throws {
            let response = try withClient {
                try $0.promptDiagramGet(PromptDiagramGetRequest(
                    promptUuid: promptUuid, diagramUuid: diagramUuid))
            }
            if output.json { printJSON(response) } else {
                print("[gm] \(response.diagramUuid) — r\(response.renderedRevision)")
                print("  \(response.renderedPath)")
                print(response.qualification)
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Every diagram this prompt has qualified.")

        @OptionGroup var output: OutputOptions

        @Option(name: .long) var promptUuid: String

        func run() throws {
            let response = try withClient {
                try $0.promptDiagramList(PromptDiagramListRequest(promptUuid: promptUuid))
            }
            if output.json { printJSON(response) } else {
                print("[gm] \(response.qualifications.count) qualified diagram(s)")
                for row in response.qualifications {
                    print("  \(row.diagramUuid) r\(row.renderedRevision) — \(row.renderedPath)")
                }
            }
        }
    }
}
