import XCTest
@testable import GMCCDaemonKit

/// Doc drift as a build failure (the CheatsheetTests precedent, extended).
/// Walks the plugin's doc tree (commands/, skills/, prompts/, output-styles/)
/// and refuses the classes of rot this cleanup retired: hardcoded gm binary
/// paths, the retired session env family, the retired DOPE expansion, the
/// retired ~/.zshrc block, and `--adopt` leaking into bot workflows.
///
/// Allowlists are deliberate and commented — keep them SHORT; every entry
/// names why it is exempt.
final class DocsContractTests: XCTestCase {

    /// plugins/gmcc/, located from this file: Tests/GMCCDaemonKitTests/X.swift
    /// → daemon/ → plugins/gmcc/.
    private var pluginRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // drop DocsContractTests.swift
            .deletingLastPathComponent()   // drop GMCCDaemonKitTests
            .deletingLastPathComponent()   // drop Tests
            .deletingLastPathComponent()   // drop daemon → plugins/gmcc
    }

    private func docFiles() throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in ["commands", "skills", "prompts", "output-styles"] {
            let root = pluginRoot.appendingPathComponent(dir, isDirectory: true)
            guard fm.fileExists(atPath: root.path) else { continue }
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "md" { out.append(url) }
            }
        }
        XCTAssertGreaterThan(out.count, 20, "doc tree walk looks broken: \(pluginRoot.path)")
        return out
    }

    private func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: pluginRoot.path + "/", with: "")
    }

    private func violations(
        pattern: String, allowFiles: Set<String>, allowLine: ((String) -> Bool)? = nil
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        var hits: [String] = []
        for file in try docFiles() {
            let rel = relative(file)
            guard !allowFiles.contains(rel) else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                let range = NSRange(s.startIndex..., in: s)
                guard regex.firstMatch(in: s, range: range) != nil else { continue }
                if let allowLine, allowLine(s) { continue }
                hits.append("\(rel):\(index + 1): \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
        return hits
    }

    /// Hardcoded gm binary paths are wrong under sandbox (they'd drive the
    /// prod db) and redundant under the PATH shim. Exempt: bootstrap flows
    /// that run before the shim exists, permission-grant literals, and
    /// user-facing remediation messages that state where the binary lives.
    func testNoHardcodedGmBinaryPaths() throws {
        let hits = try violations(
            pattern: #"gmcc/bin/gm"#,
            allowFiles: [
                "commands/gm_init.md",              // bootstrap sequence + grant literals
                "commands/gmcc_daemon.md",          // remediation/success message text
                "commands/refresh_daemon_state.md", // staleness stat + message text
                "skills/gmcc_boot/SKILL.md",        // gm-missing remediation block
                "skills/gmcc_cleanup_system/SKILL.md", // grant literal it audits
            ],
            allowLine: { $0.contains("local_sandbox") })  // sandbox launchers are deliberately absolute
        XCTAssertEqual(hits, [], "hardcoded gm binary path in docs:\n" + hits.joined(separator: "\n"))
    }

    /// The retired session env family no longer exists — an unswept
    /// `$GMCC_SESSION_PATH` expands to EMPTY in a shell. Exempt: the gmcc
    /// skill's explicit retirement notice.
    func testNoRetiredEnvNames() throws {
        let hits = try violations(
            pattern: #"GMCC_PROJECTS|GMCC_PROJECT_PATH|GMCC_INSTANCE_PATH|GMCC_SESSION_PATH|GMCC_KBITE"#,
            allowFiles: [
                "skills/gmcc/SKILL.md",             // the retirement notice itself
            ])
        XCTAssertEqual(hits, [], "retired env var referenced in docs:\n" + hits.joined(separator: "\n"))
    }

    /// The old expansion is retired everywhere; DopeVocabulary is canonical.
    func testNoRetiredDopeExpansion() throws {
        let hits = try violations(
            pattern: NSRegularExpression.escapedPattern(for: DopeVocabulary.retiredAcronym),
            allowFiles: [])
        XCTAssertEqual(hits, [], "retired DOPE expansion in docs:\n" + hits.joined(separator: "\n"))
    }

    /// Nothing may recreate the ~/.zshrc gmcc env block. Exempt: the two
    /// places that talk ABOUT deleting it.
    func testZshrcBlockMarkerOnlyInCleanupDocs() throws {
        let hits = try violations(
            pattern: #">>> gmcc env >>>"#,
            allowFiles: [
                "commands/gm_init.md",                 // "check it does NOT exist" + pointer
                "skills/gmcc_cleanup_system/SKILL.md", // the deletion remedy
            ])
        XCTAssertEqual(hits, [], "zshrc gmcc block referenced outside cleanup docs:\n" + hits.joined(separator: "\n"))
    }

    /// --adopt is boot-sync-only; a bot tier instructing agents to use it
    /// would silently discard db-side dope work.
    func testAdoptFlagAbsentFromBotTiers() throws {
        for name in ["commands/gm_bot.md", "commands/gm_bot_rpi.md", "commands/gm_bot_team.md"] {
            let url = pluginRoot.appendingPathComponent(name)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains("--adopt"), "\(name) must not mention --adopt")
        }
    }
}
