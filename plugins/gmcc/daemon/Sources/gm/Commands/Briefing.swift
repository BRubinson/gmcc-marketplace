import ArgumentParser
import Foundation
import GMCCDaemonKit

/// Resolve a text source from exactly one of an inline flag and a file flag —
/// the resolveOverview contract generalized (the file form exists because a
/// real body exceeds the OS argv budget long before the daemon's cap).
func resolveText(inline: String?, file: String?, flag: String) throws -> String {
    switch (inline, file) {
    case (let inline?, nil):
        return inline
    case (nil, let file?):
        guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
            throw ValidationError("cannot read --\(flag)-file: \(file)")
        }
        return content
    case (nil, nil):
        throw ValidationError("pass --\(flag) or --\(flag)-file")
    default:
        throw ValidationError("--\(flag) and --\(flag)-file are mutually exclusive")
    }
}

/// gm briefing — the agent-briefing machine (v21): a doper agent composes a
/// context package per (owner, step); spawned agents pull it at start via the
/// stub the SubagentStart hook injects. building → ready only; open on an
/// existing pair RESETS (current briefing, never a pile of drafts). Staleness
/// is computed at every read and only ever warns.
struct Briefing: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Agent briefings: open, complete, get, list, stub.",
        subcommands: [Open.self, Complete.self, Get.self, List.self, Stub.self]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reserve (or reset to building) the briefing for one owner + step. Exactly one owner: --prompt-uuid, or --session-uuid for /gm_task-owned briefings.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String?
        @Option(name: .long) var sessionUuid: String?
        @Option(name: .long, help: "Which phase consumes this briefing (initial | pre_architecture).")
        var step: String

        func run() throws {
            let response = try withClient {
                try $0.briefingOpen(BriefingOpenRequest(
                    promptUuid: promptUuid, sessionUuid: sessionUuid, briefingForStep: step,
                    clientKey: ClientKey.resolve()))
            }
            if output.json { printJSON(response) } else {
                let b = response.briefing
                print("[gm] briefing \(response.created ? "created" : "reset"): \(b.uuid) (step \(b.briefingForStep), \(b.status), v\(b.version))")
            }
        }
    }

    struct Complete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "building → ready. The daemon stamps the dope revision itself and denormalizes kbite briefs from --kbite-ref uuids.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var briefingUuid: String
        @Option(name: .long) var expectedVersion: Int64
        @Option(name: .long, help: "Briefing body (inline).")
        var body: String?
        @Option(name: .long, help: "Briefing body from a file (the argv-budget escape hatch).")
        var bodyFile: String?
        @Option(name: .long, help: "Repeatable dope DOT-PATH the briefing drew on (never a uuid).")
        var dopeRef: [String] = []
        @Option(name: .long, help: "Repeatable kbite file uuid; the daemon attaches each brief.")
        var kbiteRef: [String] = []

        func run() throws {
            let bodyText = try resolveText(inline: body, file: bodyFile, flag: "body")
            let response = try withClient {
                try $0.briefingComplete(BriefingCompleteRequest(
                    briefingUuid: briefingUuid,
                    expectedVersion: expectedVersion,
                    body: bodyText,
                    dopeRefs: dopeRef.isEmpty ? nil : dopeRef,
                    kbiteRefs: kbiteRef.isEmpty ? nil : kbiteRef))
            }
            if output.json { printJSON(response) } else {
                let b = response.briefing
                print("[gm] briefing ready: \(b.uuid) (step \(b.briefingForStep), scope rev \(b.dopeScopeRevision.map(String.init) ?? "-"), v\(b.version))")
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch one briefing + live staleness (dope revision drift, ghost dot-paths). Selectors: --briefing-uuid | --prompt-uuid [--step] | just --step — the DETERMINISTIC form: gm resolves the session from cwd and this Claude instance from process ancestry, so spawned agents need no uuid at all.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var briefingUuid: String?
        @Option(name: .long) var promptUuid: String?
        @Option(name: .long) var sessionUuid: String?
        @Option(name: .long) var step: String?
        @Flag(name: .long, help: "Poll until status == ready — the output IS the briefing; exit 1 on timeout. The primary's post-doper-spawn gate.")
        var wait = false
        @Option(name: .long, help: "With --wait: give up after N seconds (default 90 — inside the Bash tool's 120s default).")
        var timeoutSeconds: Int?

        func run() throws {
            if timeoutSeconds != nil, !wait {
                throw ValidationError("--timeout-seconds requires --wait")
            }
            let timeout = timeoutSeconds ?? 90
            if wait, timeout <= 0 {
                throw ValidationError("--timeout-seconds must be positive")
            }
            let response = try withClient { client -> BriefingGetResponse in
                // The zero-uuid path: nothing but --step means "MY briefing"
                // — session from cwd, instance from process ancestry.
                var session = sessionUuid
                if briefingUuid == nil, promptUuid == nil, session == nil {
                    session = try ContextBuilder.resolveSessionUuid(client)
                }
                // Once a poll has seen the row, later polls go by uuid —
                // `open` RESETS in place, so the uuid is stable across a
                // dead-doper re-open + re-spawn.
                var pinnedUuid = briefingUuid
                func fetchOnce() throws -> BriefingGetResponse {
                    let response = try client.briefingGet(BriefingGetRequest(
                        briefingUuid: pinnedUuid,
                        promptUuid: pinnedUuid == nil ? promptUuid : nil,
                        sessionUuid: pinnedUuid == nil ? session : nil,
                        step: pinnedUuid == nil ? step : nil,
                        clientKey: ClientKey.resolve()))
                    pinnedUuid = response.briefing.uuid
                    return response
                }
                guard wait else { return try fetchOnce() }
                let outcome = try awaitBriefingReady(timeoutSeconds: timeout, fetch: {
                    do {
                        return try fetchOnce()
                    } catch let error as DaemonClientError {
                        // A selector form may race the doper's own `open`
                        // (SUMMARY_ABSENT = row not opened yet) — retryable.
                        // A held --briefing-uuid means the row existed: any
                        // error on it stays a hard fail.
                        guard case .server(let payload) = error,
                              payload.codeRaw == "SUMMARY_ABSENT",
                              briefingUuid == nil else { throw error }
                        return nil
                    }
                })
                switch outcome {
                case .ready(let ready):
                    return ready
                case .timedOut(let lastSeen):
                    let state = lastSeen.map { "still \($0.status) (uuid \($0.uuid), v\($0.version))" }
                        ?? "still absent (was gm briefing open run?)"
                    fputs("""
                        [gm] briefing \(state) after \(timeout)s — dead-doper policy: FIRST \
                        re-check with a plain gm briefing get (a slow doper may have just \
                        finished — never reset a ready row); if still building, gm briefing \
                        open the same (owner, step) again (resets to building) and re-spawn \
                        the doper once; after a second failure proceed briefing-less with an \
                        explicit note.\n
                        """, stderr)
                    throw ExitCode(1)
                }
            }
            if output.json { printJSON(response) } else {
                let b = response.briefing
                let s = response.staleness
                print("[gm] briefing \(b.uuid) (step \(b.briefingForStep), \(b.status), v\(b.version))")
                if s.drifted {
                    print("  STALE: dope scope moved \(s.stampedRevision.map(String.init) ?? "?") → \(s.currentRevision.map(String.init) ?? "?")")
                }
                if !s.ghostDotPaths.isEmpty {
                    print("  ghosts: \(s.ghostDotPaths.joined(separator: ", "))")
                }
                print(b.body)
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List briefings for a prompt or a session (task-owned rows included); empty is normal.")

        @OptionGroup var output: OutputOptions
        @Option(name: .long) var promptUuid: String?
        @Option(name: .long) var sessionUuid: String?

        func run() throws {
            let response = try withClient {
                try $0.briefingList(BriefingListRequest(promptUuid: promptUuid, sessionUuid: sessionUuid))
            }
            if output.json { printJSON(response) } else {
                if response.briefings.isEmpty { print("[gm] no briefings") }
                for b in response.briefings {
                    let owner = b.promptUuid.map { "prompt \($0)" } ?? "task (session-owned)"
                    print("  \(b.uuid)  \(b.briefingForStep)  \(b.status)  \(owner)")
                }
            }
        }
    }

    struct Stub: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compose the SubagentStart injection stub (plain text, ≤2KB, empty when nothing applies — hook-safe by construction). The daemon resolves session → active prompt → the agent role's step.")

        @Option(name: .long, help: "The spawned agent's type (e.g. gmcc:code-explorer) — maps to its briefing step.")
        var agentType: String?

        func run() throws {
            let stub = try withClient { client -> String in
                // cwd → session resolution happens client-side; no session is
                // a silent empty stub, never an error (hook contract).
                guard let sessionUuid = try? ContextBuilder.resolveSessionUuid(client) else {
                    return ""
                }
                return try client.briefingStub(BriefingStubRequest(
                    agentType: agentType,
                    sessionUuid: sessionUuid,
                    clientKey: ClientKey.resolve())).stub
            }
            if !stub.isEmpty { print(stub) }
        }
    }
}
