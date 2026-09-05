import XCTest
@testable import GMCCDaemonKit

final class DopeSandboxTests: XCTestCase {

    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-sandbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoRoot)
    }

    private func makeBundle(version: Int64 = 1, domains: [String] = ["core"]) -> DopeDocumentBundle {
        DopeDocumentBundle(
            main: DopeMainDocument(
                version: version, scopeType: "SESSION_BASE",
                scope: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                domains: Dictionary(uniqueKeysWithValues: domains.map {
                    ($0, DopeMainDocument.expectedFile(forDomainCode: $0))
                })),
            domainFiles: domains.map {
                DopeDomainFileDocument(
                    version: version,
                    body: DopeDomainBody(code: $0, name: $0.capitalized,
                                         description: "", sortOrder: 0),
                    entities: [], enums: [])
            })
    }

    // MARK: - Resolution pre-flight

    func testResolveRejectsMissingStaleAndNonGitRoots() throws {
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(instanceRoot: ""))
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(instanceRoot: "relative/path"))
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(
            instanceRoot: "/nonexistent/definitely-stale-\(UUID().uuidString)")) { error in
            XCTAssertTrue("\(error)".contains("missing or stale"), "\(error)")
        }
        let notGit = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: notGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notGit) }
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(instanceRoot: notGit.path)) { error in
            XCTAssertTrue("\(error)".contains("not a git checkout"), "\(error)")
        }
        XCTAssertNoThrow(try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path))
    }

    // MARK: - Containment

    func testDomainFileRefusesEscapes() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        for bad in ["../escape", "a/b", "..", "UPPER", ""] {
            XCTAssertThrowsError(try sandbox.domainFile(code: bad), "'\(bad)' must be refused")
        }
        let good = try sandbox.domainFile(code: "core")
        XCTAssertTrue(good.path.hasPrefix(sandbox.dopeRoot.path + "/"))
    }

    func testReadRefusesTamperedDomainMap() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle())
        // Tamper: point the map outside domains/.
        let tampered = """
            {"version": 1, "scope_type": "SESSION_BASE",
             "scope": {"code": "gmcc", "name": "GMCC", "description": ""},
             "domains": {"core": "../../../etc/passwd"}}
            """
        try Data(tampered.utf8).write(to: sandbox.mainFile)
        XCTAssertThrowsError(try sandbox.readBundle()) { error in
            XCTAssertTrue("\(error)".contains("never followed"), "\(error)")
        }
    }

    // MARK: - Round trip + atomicity

    func testWriteReadRoundTripAndIdempotence() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let bundle = makeBundle(domains: ["core", "billing"])
        let first = try sandbox.writeAtomically(bundle)
        XCTAssertEqual(first.written.count, 4, "main + 2 domains + drawing config")

        let read = try sandbox.readBundle()
        XCTAssertEqual(read.bundle.main, bundle.main)
        // The reader returns files sorted by code; sort_order carries the
        // semantic order, so compare order-insensitively.
        XCTAssertEqual(read.bundle.domainFiles.sorted { $0.body.code < $1.body.code },
                       bundle.domainFiles.sorted { $0.body.code < $1.body.code })
        XCTAssertTrue(read.warnings.isEmpty)

        // Idempotence: identical bytes after a second write.
        let mainBefore = try Data(contentsOf: sandbox.mainFile)
        _ = try sandbox.writeAtomically(bundle)
        XCTAssertEqual(try Data(contentsOf: sandbox.mainFile), mainBefore)
    }

    func testWritePrunesStaleDomainFilesAndPreservesDrawingConfig() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle(domains: ["core", "billing"]))
        // A user-authored drawing config must survive rewrites.
        try Data("{\"zoom\": 2}".utf8).write(to: sandbox.drawingConfigFile)

        let second = try sandbox.writeAtomically(makeBundle(version: 2, domains: ["core"]))
        XCTAssertEqual(second.pruned, ["domains/billing.doped.json"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.domainsDirectory.appendingPathComponent("billing.doped.json").path))
        XCTAssertEqual(try Data(contentsOf: sandbox.drawingConfigFile),
                       Data("{\"zoom\": 2}".utf8))
    }

    func testPeekRevision() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        XCTAssertNil(sandbox.peekRevision())
        _ = try sandbox.writeAtomically(makeBundle(version: 7))
        XCTAssertEqual(sandbox.peekRevision(), 7)
    }

    func testFailedWriteLeavesOldTreeIntactAndNoStaging() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle(version: 1))
        let mainBefore = try Data(contentsOf: sandbox.mainFile)

        // A bundle whose domain code fails validation mid-staging throws
        // AFTER main has been staged — the old tree must be untouched.
        let bad = DopeDocumentBundle(
            main: makeBundle(version: 2).main,
            domainFiles: [DopeDomainFileDocument(
                version: 2,
                body: DopeDomainBody(code: "Bad-Code", name: "x", description: "", sortOrder: 0),
                entities: [], enums: [])])
        XCTAssertThrowsError(try sandbox.writeAtomically(bad))

        XCTAssertEqual(try Data(contentsOf: sandbox.mainFile), mainBefore,
                       "old tree must survive a failed write")
        let gmcc = repoRoot.appendingPathComponent(".gmcc")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: gmcc.path)
            .filter { $0.hasPrefix(".dope-staging") }
        XCTAssertTrue(leftovers.isEmpty, "staging directory leaked: \(leftovers)")
    }

    /// Review fix [45]: containment must resolve symlinks — a symlinked
    /// .gmcc/dope (or .gmcc) would otherwise redirect the atomic swap
    /// outside the repo while every lexical prefix check passes.
    func testSymlinkedDopeRootRefused() throws {
        let fm = FileManager.default
        let outside = fm.temporaryDirectory
            .appendingPathComponent("dope-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        let gmcc = repoRoot.appendingPathComponent(".gmcc", isDirectory: true)
        try fm.createDirectory(at: gmcc, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: gmcc.appendingPathComponent("dope"),
            withDestinationURL: outside)

        XCTAssertThrowsError(
            try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)) { error in
            XCTAssertTrue("\(error)".contains("symlink"), "\(error)")
        }
    }

    func testMissingTreeReadIsLoud() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        XCTAssertThrowsError(try sandbox.readBundle()) { error in
            XCTAssertTrue("\(error)".contains("no dope tree on disk"), "\(error)")
        }
    }
}
