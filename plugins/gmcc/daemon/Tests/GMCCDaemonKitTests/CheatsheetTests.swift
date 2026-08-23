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

    func testEveryLeafSubcommandAppearsInCheatsheet() {
        let leaves = GM.configuration.subcommands.flatMap { leafPaths($0, prefix: "gm") }
        XCTAssertGreaterThan(leaves.count, 50, "command tree walk looks broken")
        for leaf in leaves {
            XCTAssertTrue(
                Cheatsheet.text.contains(leaf),
                "cheatsheet is missing a line for `\(leaf)` — update Cheatsheet.text")
        }
    }
}
