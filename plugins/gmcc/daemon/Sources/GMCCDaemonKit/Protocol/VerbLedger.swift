import Foundation

/// The verb registry in machine-readable form: which invocations are writes,
/// which pen tool replaces each one for an agent, and which are the primary's
/// gate doors.
///
/// HOISTED TO THE KIT because its most important consumer is a hook. The
/// PreToolUse write guard shells out for this on the Bash hot path and builds
/// its deny reason from it, so the deny names the exact replacement tool BY
/// CONSTRUCTION rather than from a hand-maintained list that goes stale the
/// moment the pen grows a tool. A guard whose ledger lived inside a front-end
/// binary would lose it the moment that binary was retired.
///
/// PURELY LOCAL — no daemon, no socket. A guard that needed a live daemon to
/// decide would fail closed exactly when the daemon is down.
///
/// It is also the WOULD-REFUSE LEDGER'S READER: the `.observe → .enforce` flip's
/// precondition is "the ledger names no live caller", and a precondition with no
/// reader is a remembered one rather than a checked one.
public enum VerbLedger {

    /// ONE ROW PER INVOCATION SPELLING, not per MessageType. A verb with aliases
    /// emits one row each, all carrying the same message type, role and pen
    /// tool — which is what lets the guard match on a flat list and still see
    /// every spelling.
    public struct VerbRow: Encodable, Sendable {
        public let messageType: String
        public let gm: String
        public let penTool: String?
        /// primary_door | record | read
        public let role: String
        /// Is this a write (record or primary_door)?
        public let write: Bool
        /// False for the canonical spelling, true for an alias of it.
        public let alias: Bool
        /// The canonical spelling this row belongs to (== `gm` when canonical).
        public let canonicalGm: String
    }

    public struct Payload: Encodable, Sendable {
        public let verbs: [VerbRow]
        /// invocation -> pen tool, for every write that HAS a replacement,
        /// aliases included. This map alone is enough to author a deny reason.
        public let penReplacements: [String: String]
        /// Every gate invocation no agent may call at all.
        public let primaryDoors: [String]
        /// observe | enforce.
        public let enforcement: String
        /// The flip precondition, in machine-readable form.
        public let wouldRefuse: VerbRegistry.WouldRefuseLedger
    }

    public static func build(writesOnly: Bool = false) -> Payload {
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
        return Payload(
            verbs: rows.sorted { $0.gm < $1.gm },
            penReplacements: replacements,
            primaryDoors: doors.sorted(),
            enforcement: VerbRegistry.enforcement.rawValue,
            wouldRefuse: VerbRegistry.wouldRefuseLedger())
    }
}
