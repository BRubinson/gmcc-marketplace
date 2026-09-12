import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm verbs — print the verb registry: which `gm` invocations are writes,
/// which pen tool replaces each one for an agent, and which are the primary's
/// gate doors.
///
/// The registry's third consumer, and the reason it exists in machine-readable
/// form: `gmcc_gm_write_guard.sh` (PreToolUse, matcher Bash) decides from this
/// output, so a deny reason names the exact replacement tool BY CONSTRUCTION
/// rather than from a hand-maintained list that drifts the moment the pen
/// grows a tool.
///
/// Purely local — no daemon, no socket. A hook runs this on the Bash tool's
/// hot path, and a guard that needs a live daemon to decide would fail closed
/// exactly when the daemon is down.
///
/// It is also the WOULD-REFUSE LEDGER'S READER (amendment A5). The
/// `.observe → .enforce` flip's precondition is "the ledger names no live
/// caller", and a precondition with no reader is a remembered one. This is
/// the command that already prints the enforcement mode, and being local it
/// can answer even when the daemon that would be flipped is down.
struct Verbs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the verb registry: gm write verbs, their pen replacements, and the primary's gate doors.")

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Only the verbs an agent must not call through gm (the deny set).")
    var writesOnly = false

    /// ONE ROW PER `gm` SPELLING, not per MessageType. A verb with aliases
    /// (`gm bot summary` for EXPLORE_OPEN) emits one row each, all carrying
    /// the same message type, role and pen tool. That is what lets `gmcc_gm_write_guard.sh` keep matching
    /// on a flat `.verbs[] | .gm` list and still see every spelling — the
    /// guard needs no change to gain alias coverage.
    ///
    /// Snake_case on the wire like every other gm --json payload (WireCodec's
    /// shared strategy), so jq paths read the same.
    struct VerbRow: Encodable {
        let messageType: String
        let gm: String
        let penTool: String?
        /// primary_door | record | read
        let role: String
        /// Is this a write (record or primary_door)?
        let write: Bool
        /// False for the canonical spelling, true for an alias of it.
        let alias: Bool
        /// The canonical spelling this row belongs to (== `gm` when canonical).
        let canonicalGm: String
    }

    struct VerbsPayload: Encodable {
        let verbs: [VerbRow]
        /// gm invocation -> pen tool, for every write that HAS a replacement,
        /// aliases included. This map alone is enough to author a deny reason.
        let penReplacements: [String: String]
        /// Every gate invocation no agent may call at all.
        let primaryDoors: [String]
        /// observe | enforce.
        let enforcement: String
        /// AMENDMENT A5's MACHINE-READABLE PRECONDITION. The `.observe` →
        /// `.enforce` flip is only safe when this names nothing but genuine
        /// agents reaching for a primary door; a reader is what makes that a
        /// check rather than a memory. The registry's own ledger type, not a
        /// mirror of it — a second declaration of the same shape is the drift
        /// this whole registry exists to make impossible.
        let wouldRefuse: VerbRegistry.WouldRefuseLedger
    }

    /// Not `private`: `VerbRegistryTests` encodes this directly to pin that
    /// `gm verbs --json` really carries the would-refuse ledger. A5's whole
    /// point is that the flip precondition has a READER, and a reader nothing
    /// asserts is how it came to have none the first time.
    func payload() -> VerbsPayload {
        var rows: [VerbRow] = []
        var replacements: [String: String] = [:]
        var doors: [String] = []
        for spec in VerbRegistry.all {
            let role: String
            let isWrite: Bool
            switch spec.role {
            case .primaryDoor:
                role = "primary_door"
                isWrite = true
            case .record:
                role = "record"
                isWrite = true
            case .read:
                role = "read"
                isWrite = false
            }
            for (index, invocation) in spec.gmInvocations.enumerated() {
                if case .primaryDoor = spec.role { doors.append(invocation) }
                if isWrite, let pen = spec.penTool { replacements[invocation] = pen }
                guard !writesOnly || isWrite else { continue }
                rows.append(VerbRow(
                    messageType: spec.messageType.rawValue,
                    gm: invocation,
                    penTool: spec.penTool,
                    role: role,
                    write: isWrite,
                    alias: index > 0,
                    canonicalGm: spec.gmInvocation))
            }
        }
        return VerbsPayload(
            verbs: rows.sorted { $0.gm < $1.gm },
            penReplacements: replacements,
            primaryDoors: doors.sorted(),
            enforcement: VerbRegistry.enforcement.rawValue,
            wouldRefuse: VerbRegistry.wouldRefuseLedger())
    }

    func run() throws {
        let payload = payload()
        if output.json {
            printJSON(payload)
            return
        }
        print("[gm] verb registry (\(payload.verbs.count) invocations, enforcement \(payload.enforcement))")
        for row in payload.verbs {
            let replacement = row.penTool.map { "  →  pen \($0)" }
                ?? (row.role == "primary_door" ? "  →  PRIMARY DOOR (no pen tool; agents are refused)" : "")
            let alias = row.alias ? "  (alias of `\(row.canonicalGm)`)" : ""
            print("  \(row.write ? "W" : "r") \(row.gm)\(replacement)\(alias)")
        }
        // The flip precondition, printed where the flipper is already looking.
        print(VerbRegistry.wouldRefuseLedger().summaryLine)
    }
}
