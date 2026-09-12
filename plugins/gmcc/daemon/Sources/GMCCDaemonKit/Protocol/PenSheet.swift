import Foundation

/// The agent-facing sheet, GENERATED FROM `VerbRegistry` rather than written
/// down.
///
/// It replaces the hand-maintained CLI cheatsheet for every agent-facing
/// purpose. That sheet's failure was structural, not editorial: it was prose
/// about a surface, so it could disagree with the surface, and it did — it
/// handed every spawned agent four `gm` reads while those same agents' own
/// definitions said "you have no shell, there is no CLI fallback and none is
/// needed." Generating from the registry makes that disagreement unrepresentable.
///
/// TWO PROPERTIES, TWO BUDGETS. `instructions` is what the MCP server returns
/// from `initialize`, where the budget is tight (2048 bytes, asserted at
/// startup). `text` is what a spawning agent receives as SubagentStart context,
/// where there is room for the invariants an agent actually needs and cannot
/// infer from a tool schema.
public enum PenSheet {

    /// Compact orientation for the MCP `initialize` response.
    public static var instructions: String {
        let roster = self.roster
        return """
            The GMCC pen: the GM-CDE workflow machine's record, as tools.

            START HERE — bot_next returns your current phase, its instructions, \
            your uuid bundle, and the gate blockers. Call it before anything else, \
            and again after every seal. It answers without being told a uuid.

            THE RULE — where a pen tool exists, it is the write path. The daemon \
            knows which channel a write came from.

            READ: \(roster.reads.joined(separator: ", ")).
            WRITE: \(roster.writes.joined(separator: ", ")).

            NOT YOURS — the primary's gate doors: \(roster.doors.joined(separator: ", ")). \
            Report that you are ready for one; never walk through it.
            """
    }

    /// The fuller sheet handed to a spawned agent at SubagentStart.
    ///
    /// THE INVARIANTS BLOCK IS THE LOAD-BEARING HALF. A tool schema conveys a
    /// parameter list and nothing else — it cannot tell an agent that the db is
    /// append-only, that a VERSION_CONFLICT is re-read-and-retry rather than a
    /// failure, or that a dope ref is a dot-path code and never a uuid. Those
    /// were the only parts of the retired cheatsheet worth keeping, and they are
    /// kept here.
    public static var text: String {
        """
        \(instructions)

        INVARIANTS
          - Thread --expected-version on every mutation. On VERSION_CONFLICT, \
        re-run the matching get, take .version, and retry — it is a normal \
        outcome of concurrent work, not an error to report.
          - The db is APPEND-ONLY history. Nothing is wiped, and a row you \
        wrote by mistake is corrected by writing again, never by deletion.
          - SUMMARY_ABSENT means the prompt exists but that summary was never \
        opened — open it. It is never a reason to fall back to a file.
          - Dope refs are dot-path CODES (domain.entity.property), never uuids.
          - Rate your OWN findings 0 (critical) to 999 (ignore); the read \
        threshold is 100. Never call rank or reopen — those belong to the primary.
          - Seal only your own summary. That seal is yours; another agent's is not.

        IF A PEN TOOL YOU NEED IS NOT IN YOUR TOOL LIST, the pen did not register \
        for this session. Report that and stop — do not work around it through \
        another channel, because a write the pen cannot make is a write nothing \
        records.
        """
    }

    // MARK: - Generation

    struct Roster {
        var reads: [String]
        var writes: [String]
        var doors: [String]
    }

    /// Orientation before record before write: an agent that calls bot_next
    /// first never needs the rest of this text.
    static var roster: Roster {
        let leadReads = ["bot_next", "bot_get", "bot_current_prompt"]
        var reads: [String] = leadReads
        var writes: [String] = []
        var doors: [String] = []
        for spec in VerbRegistry.all.sorted(by: { $0.messageType.rawValue < $1.messageType.rawValue }) {
            switch spec.role {
            case .primaryDoor:
                // Named by their PEN spelling, because that is the name that
                // still exists — the `gm` forms these used to carry are a dead
                // CLI's, and an agent told to avoid a command it could not run
                // anyway learns nothing.
                //
                // Named at all, rather than withheld, so an agent can say it is
                // ready for a specific door. Withholding the name only produces
                // an agent that reports "blocked" without saying on what.
                if let pen = spec.penTool { doors.append(pen) }
            case .read:
                if let tool = spec.penTool, !reads.contains(tool) { reads.append(tool) }
            case .record:
                if let tool = spec.penTool, !reads.contains(tool) { writes.append(tool) }
            }
        }
        for tool in VerbRegistry.compositePenTools.keys.sorted() where !reads.contains(tool) {
            reads.append(tool)
        }
        return Roster(reads: reads, writes: writes, doors: doors.sorted())
    }
}
