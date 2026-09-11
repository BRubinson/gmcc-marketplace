import XCTest
@testable import GMCCDaemonKit

/// Doc drift as a build failure (the CheatsheetTests precedent, extended).
/// Walks the plugin's doc tree (commands/, skills/, prompts/, output-styles/)
/// and refuses the classes of rot this cleanup retired: hardcoded gm binary
/// paths, the retired session env family, the retired DOPE expansion, the
/// retired ~/.zshrc block, and `--adopt` leaking into bot workflows.
///
/// Three of these also walk `daemon/Sources`. That widening is the point: the
/// worst offenders of the SESSION_BASE / `.gmcc/dope` rot were the COMPILED
/// cheatsheet and the CLI `--help` abstracts, which a docs-only walk cannot
/// see even though they reach every session.
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

    /// plugins/gmcc/daemon/Sources — the CLI help text, cheatsheet body and
    /// doc comments that a `.md`-only walk misses.
    private func swiftFiles() throws -> [URL] {
        let fm = FileManager.default
        let root = pluginRoot.appendingPathComponent("daemon/Sources", isDirectory: true)
        var out: [URL] = []
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { out.append(url) }
        }
        XCTAssertGreaterThan(out.count, 20, "source tree walk looks broken: \(root.path)")
        return out
    }

    private func violations(
        pattern: String, allowFiles: Set<String>, allowLine: ((String) -> Bool)? = nil
    ) throws -> [String] {
        try violations(in: try docFiles(), pattern: pattern,
                       allowFiles: allowFiles, allowLine: allowLine)
    }

    private func violations(
        in files: [URL], pattern: String, allowFiles: Set<String>,
        allowLine: ((String) -> Bool)? = nil
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        var hits: [String] = []
        for file in files {
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

    /// m0025 retirements: the pre_architecture briefing step (the care
    /// package replaced it), the clarification summary text fields, the
    /// clarify ask/category verbs, the merged exploration_key_file table,
    /// and the finalize→prompt.goal copy. A doc resurrecting any of these
    /// re-teaches a retired machine. Exempt: nothing — history lives in
    /// migration comments (Swift), not docs.
    func testNoRetiredWorkflowConcepts() throws {
        let hits = try violations(
            pattern: #"pre_architecture|refined_goal|refined_detail|backstory_note|clarify ask|--category goal|exploration_key_file|copies refined|finalize copies"#,
            allowFiles: [])
        XCTAssertEqual(
            hits, [],
            "retired m0025 workflow concept in docs:\n" + hits.joined(separator: "\n"))
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

    /// m0013 renamed the tier to SESSION_INSTANCE. Docs AND sources: the tier
    /// name reaches users through the cheatsheet and `gm dope --help`, not
    /// just through markdown.
    func testNoRetiredSessionBaseTier() throws {
        let pattern = #"\bSESSION_BASE\b"#
        // The real flag is named --clone-from-session-base; it is not a tier
        // reference and must survive this sweep.
        let allowLine: (String) -> Bool = { $0.lowercased().contains("session-base") }
        var hits = try violations(pattern: pattern, allowFiles: [], allowLine: allowLine)
        hits += try violations(
            in: try swiftFiles(), pattern: pattern,
            allowFiles: [
                // The m0012/m0013 literals and history — SESSION_BASE is the
                // stored value these migrations read and rewrite.
                "daemon/Sources/GMCCDaemonKit/Database/Migrations.swift",
                // The legacy decode alias, so an old file still parses. The
                // file self-updates on its next write.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeLevel.swift",
                // Documents the retired spelling it is tolerant of.
                "daemon/Sources/GMCCDaemonKit/Protocol/Rows.swift",
            ],
            allowLine: allowLine)
        XCTAssertEqual(hits, [], "retired SESSION_BASE tier referenced:\n" + hits.joined(separator: "\n"))
    }

    /// The dope tree moved to `{instance_root}/.gmcc` — `.gmcc/dope` is the
    /// retired layout. A stale path here sent gm doctor's drift check at a
    /// file that never exists, so the finding silently never fired.
    func testNoRetiredDopeDirectory() throws {
        let pattern = #"\.gmcc/dope"#
        var hits = try violations(
            pattern: pattern,
            allowFiles: [
                // The layout reference itself — it names the retired path in
                // order to tell the reader it is retired.
                "skills/gmcc/ref/doped_files.md",
            ])
        hits += try violations(
            in: try swiftFiles(), pattern: pattern,
            allowFiles: [
                // Defines legacyDopeDirectoryName / legacyMainFileName.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeDocument.swift",
                // legacyDopeRoot + the note on why the old layout could be
                // swapped wholesale and the new one cannot.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeRepoSandbox.swift",
                // Probes the retired tree on purpose, to warn about a stale
                // checkout and tell the user how to republish it.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeBootSync.swift",
            ])
        XCTAssertEqual(hits, [], "retired .gmcc/dope path referenced:\n" + hits.joined(separator: "\n"))
    }

    /// m0012 renamed the dope domain-* verbs to persistence-*. A doc that
    /// still names the old family hands an agent an unknown subcommand.
    func testNoRetiredDopeVerbNames() throws {
        let hits = try violations(
            pattern: #"dope (domain-(add|update|delete)|\{domain,)"#,
            allowFiles: [])
        XCTAssertEqual(hits, [], "retired dope domain-* verb in docs:\n" + hits.joined(separator: "\n"))
    }

    /// The pen-down cleanup's premise killer: no doc may ever again claim a
    /// subagent runs in a "read-only sandbox" — that fiction is what kept the
    /// rpi transcription tax alive for months.
    func testNoReadOnlySandboxPremise() throws {
        let hits = try violations(pattern: #"read-only sandbox"#, allowFiles: [])
        XCTAssertEqual(hits, [], "the retired read-only-sandbox premise resurfaced:\n" + hits.joined(separator: "\n"))
    }

    /// The verbatim-paste mandate is retired: teammates get the compact core
    /// from SessionStart and Task subagents get the SubagentStart stub. A doc
    /// may SAY "never paste cheatsheets" — what it may not do is mandate
    /// pasting the sheet's verbatim output into spawn prompts again.
    func testNoCheatsheetPasteMandate() throws {
        let hits = try violations(
            pattern: #"verbatim output of\s+`?gm cheatsheet"#,
            allowFiles: [])
        XCTAssertEqual(hits, [], "a cheatsheet paste mandate resurfaced:\n" + hits.joined(separator: "\n"))
    }

    /// gmcc_daemon/SKILL.md drifted 5 wire versions behind the compiled sheet
    /// because it duplicated signatures and version literals. Structural fix:
    /// the skill may not carry a wire/schema-version literal or gm signature
    /// lines — the compiled `gm cheatsheet --full` is the sole authority.
    func testDaemonSkillCarriesNoVersionLiteralsOrSignatures() throws {
        let skill = pluginRoot.appendingPathComponent("skills/gmcc_daemon/SKILL.md")
        let text = try String(contentsOf: skill, encoding: .utf8)
        XCTAssertLessThan(
            text.utf8.count, 8192,
            "gmcc_daemon/SKILL.md outgrew its routing-skill diet")
        for pattern in [#"wire (protocol )?v\d"#, #"schema m\d{4}"#] {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNil(
                regex.firstMatch(in: text, range: range),
                "gmcc_daemon/SKILL.md carries a version literal (pattern \(pattern)) — the compiled cheatsheet is the only authority")
        }
        XCTAssertTrue(
            text.contains("gm cheatsheet --full"),
            "gmcc_daemon/SKILL.md must route signature questions to gm cheatsheet --full")
    }

    /// The retired identity-file agent system: nothing may point agents at
    /// prompts/*.prompt.md role files or output-styles/ again — identity
    /// lives in plugins/gmcc/agents/ defs now. The two crunch/maw prompts
    /// are the deliberate survivors.
    func testNoRetiredAgentIdentitySurfaces() throws {
        // Three faces of the same retired system (review finding 7fbaca71
        // widened this: the original pattern needed the .prompt.md suffix,
        // which let a 254-line skill canonizing the gmcc:agent:{name}
        // invocation syntax slip through): the role prompt files, the
        // output-styles fragments, the skills/gmcc_agent skill, and the
        // gmcc:agent:{...} invocation form itself. The crunch/maw prompts
        // (gmcc_agent_kbite_crunch_chew / gmcc_agent_maw_web_fetch) are the
        // deliberate survivors and match none of these.
        let hits = try violations(
            pattern: #"(gmcc_agent_(code_explorer|code_architect|code_quality_reviewer|finding_reranker)\.prompt\.md|output-styles/|skills/gmcc_agent\b|gmcc:agent:\{)"#,
            allowFiles: [])
        XCTAssertEqual(hits, [], "retired agent identity surface referenced in docs:\n" + hits.joined(separator: "\n"))
    }
}
