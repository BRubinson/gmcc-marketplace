import ArgumentParser
import XCTest

@testable import gm

// Drift guard for gm cheatsheet: every leaf subcommand reachable from GM's
// ArgumentParser tree must appear in Cheatsheet.text as its full invocation
// path ("gm family verb"). A new verb cannot ship without a sheet line.
final class CheatsheetTests: XCTestCase {

    /// ArgumentParser's default command name: the type name converted to
    /// hyphen-separated lowercase (e.g. FileChange → "file-change"). Used
    /// only when a command doesn't set commandName explicitly.
    private func derivedName(_ type: ParsableCommand.Type) -> String {
        let typeName = String(describing: type)
        var out = ""
        for (i, ch) in typeName.enumerated() {
            if ch.isUppercase, i > 0 { out.append("-") }
            out.append(ch.lowercased())
        }
        return out
    }

    private func leafPaths(_ type: ParsableCommand.Type, prefix: String) -> [String] {
        let name = type.configuration.commandName ?? derivedName(type)
        let path = prefix.isEmpty ? name : "\(prefix) \(name)"
        let subs = type.configuration.subcommands
        guard !subs.isEmpty else { return [path] }
        return subs.flatMap { leafPaths($0, prefix: path) }
    }

    /// Semantic couplings the flag-name walk below CANNOT check — each is a
    /// runtime ValidationError, not a missing flag. When you change one of
    /// these, update the sheet line by hand:
    ///   - `gm file-change add --content` requires exactly one `--range`.
    ///   - `gm explore/review complete` need exactly one of `--overview` /
    ///     `--overview-file` (neither is optional; both together is an error).
    ///   - `gm explore/review get`: `--full`, `--max-rating`, `--rating-range`
    ///     are mutually exclusive.
    ///   - `gm explore/review` key-file-add / finding-add / rank are refused
    ///     once the summary is complete (reopen first).
    ///   - `gm prompt list` / `gm file-change list` / `gm search`: `--all` is
    ///     not combinable with `--session-uuid`.
    ///   - `gm dope property-add/-update`: `--enum-uuid` / `--related-property-uuid`
    ///     are coupled to `--data-type` (enum/relationship exactly) and mutually
    ///     exclusive; `gm dope ingest` requires the on-disk version to be exactly
    ///     db revision + 1; `gm dope write-repo` refuses when the files are ahead
    ///     of the db without `--force`; `gm dope read-repo` needs exactly one of
    ///     `--scope-uuid` / `--dir-path`.

    func testEveryLeafSubcommandAppearsInCheatsheet() {
        let leaves = GM.configuration.subcommands.flatMap { leafPaths($0, prefix: "gm") }
        XCTAssertGreaterThan(leaves.count, 50, "command tree walk looks broken")
        for leaf in leaves {
            XCTAssertTrue(
                Cheatsheet.text.contains(leaf),
                "cheatsheet is missing a line for `\(leaf)` — update Cheatsheet.text")
        }
    }

    /// Flag-level drift guard. Verb presence alone let four real drifts ship
    /// (the coupling list above). Every long flag a leaf accepts must appear
    /// on that leaf's sheet line, so a new --flag cannot ship undocumented.
    /// This checks NAMES only — required/optional/exclusive shape is prose.
    func testEveryLongFlagAppearsOnItsCheatsheetLine() {
        // --json is universal and documented once in the sheet header;
        // --help/--version are ArgumentParser's own.
        let exempt: Set<String> = ["json", "help", "version"]
        let lines = Cheatsheet.text.split(separator: "\n").map(String.init)
        var checked = 0

        for (leaf, type) in GM.configuration.subcommands.flatMap({ leafCommands($0, prefix: "gm") }) {
            guard let line = lines.first(where: { $0.contains(leaf) }) else {
                continue // a missing line is the other test's failure to report
            }
            for flag in longFlagNames(of: type) where !exempt.contains(flag) {
                checked += 1
                XCTAssertTrue(
                    line.contains("--\(flag)"),
                    "`\(leaf)` accepts --\(flag) but its cheatsheet line does not mention it:\n  \(line)")
            }
        }
        XCTAssertGreaterThan(checked, 80, "flag walk looks broken")
    }

    /// The two-tier diet's guard rails: the compact core (what SessionStart
    /// injects into every session) must stay small, must point at --full,
    /// must name every top-level family, and must carry the INVARIANTS block
    /// — otherwise the diet silently regresses into either a bloated core or
    /// a core that hides capabilities with no pointer out.
    func testCompactCoreStaysOnItsDiet() {
        XCTAssertLessThan(
            Cheatsheet.coreText.utf8.count, 8192,
            "the compact core outgrew its budget — trim it, don't let SessionStart re-bloat")
        XCTAssertTrue(Cheatsheet.coreText.contains("gm cheatsheet --full"))
        XCTAssertTrue(Cheatsheet.coreText.contains("INVARIANTS"))
        for family in ["PROMPT", "CLARIFY", "ARCH", "EXPLORE", "REVIEW", "BRIEFING",
                       "DOPE", "DIAGRAM", "COGS", "KBITE", "FILE-CHANGE", "SANDBOX"] {
            XCTAssertTrue(
                Cheatsheet.coreText.contains(family),
                "compact core no longer names the \(family) family")
        }
    }

    /// Core/full parity: every `gm ...` signature line in the core's
    /// AGENT PEN VERBS block must exist VERBATIM in the full sheet — the
    /// block is extracted, not copied, and this is the guard that keeps it
    /// that way (a failed extraction leaves a loud MISSING sentinel).
    func testPenVerbBlockIsExtractedNotCopied() throws {
        XCTAssertFalse(
            Cheatsheet.coreText.contains("MISSING FULL-SHEET LINE"),
            "a pen-verb prefix no longer matches any full-sheet line")
        guard let blockStart = Cheatsheet.coreText.range(of: "AGENT PEN VERBS"),
              let blockEnd = Cheatsheet.coreText.range(of: "INVARIANTS") else {
            return XCTFail("core lost its AGENT PEN VERBS / INVARIANTS structure")
        }
        let block = Cheatsheet.coreText[blockStart.upperBound..<blockEnd.lowerBound]
        var checked = 0
        for raw in block.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("gm ") else { continue }
            // The zero-uuid briefing-get line is the one deliberate
            // core-specific phrasing (the full sheet documents all selectors).
            if line.hasPrefix("gm briefing get") { continue }
            checked += 1
            XCTAssertTrue(
                Cheatsheet.text.contains(line),
                "core pen-verb line drifted from the full sheet:\n  \(line)")
        }
        XCTAssertGreaterThan(checked, 5, "pen-verb block walk looks broken")
    }

    /// Long flag names a command accepts, read out of ArgumentParser's own
    /// rendered help so the walk can never disagree with the parser. Only the
    /// leading token group of an option line is scanned, so a flag NAMED in
    /// another option's help text is not mistaken for a flag of its own.
    private func longFlagNames(of type: ParsableCommand.Type) -> [String] {
        var names: [String] = []
        for raw in type.helpMessage(columns: 200).split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("-") else { continue }
            // "  --prompt-uuid <prompt-uuid>   Prompt uuid…" → the head before
            // the two-space gutter that separates usage from description.
            let head = line.components(separatedBy: "  ")[0]
            // "/" splits ArgumentParser's inversion pairs (--nullable/--no-nullable).
            for token in head.split(whereSeparator: { " ,<>|/".contains($0) }) {
                guard token.hasPrefix("--"), token.count > 2 else { continue }
                names.append(String(token.dropFirst(2)))
            }
        }
        return names
    }

    private func leafCommands(
        _ type: ParsableCommand.Type, prefix: String
    ) -> [(String, ParsableCommand.Type)] {
        let name = type.configuration.commandName ?? derivedName(type)
        let path = prefix.isEmpty ? name : "\(prefix) \(name)"
        let subs = type.configuration.subcommands
        guard !subs.isEmpty else { return [(path, type)] }
        return subs.flatMap { leafCommands($0, prefix: path) }
    }
}
