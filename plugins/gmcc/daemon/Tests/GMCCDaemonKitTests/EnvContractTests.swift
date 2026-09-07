import XCTest
@testable import GMCCDaemonKit

/// The SessionStart env contract: emitted line shape, PATH dedup idempotence,
/// the shim's resolution rule, and the env-vs-db consistency findings.
final class EnvContractTests: XCTestCase {

    func testEmittedLinesAreEnvFileShaped() {
        let lines = GmccEnvironment.emit(
            pluginRoot: "/plugins/gmcc", inheritedPath: "/usr/bin:/bin")
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertTrue(line.range(of: #"^[A-Z_]+="#, options: .regularExpression) != nil,
                          "not a KEY=VALUE line: \(line)")
            XCTAssertFalse(line.contains("\n"))
        }
        XCTAssertTrue(lines.contains("GMCC_BOOTED=1"))
        XCTAssertTrue(lines.contains("GMCC_PLUGIN_ROOT=/plugins/gmcc"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("GMCC_CKFS_ROOT=") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("PATH=") })
    }

    func testDbCkfsRootWinsWhenProvided() {
        let lines = GmccEnvironment.emit(
            pluginRoot: "/p", inheritedPath: "", dbCkfsRoot: "/db/ckfs")
        XCTAssertTrue(lines.contains("GMCC_CKFS_ROOT=/db/ckfs"))
    }

    func testPathValueIsIdempotentAndLeadsWithRuntimeBin() {
        let mine = Paths.bin.path
        let once = GmccEnvironment.pathValue(current: "/usr/bin:/bin")
        XCTAssertTrue(once.hasPrefix("\(mine):"))
        let twice = GmccEnvironment.pathValue(current: once)
        XCTAssertEqual(once, twice, "re-emission must not stack PATH entries")
    }

    func testPathLineIsFullyResolvedLiteral() {
        let lines = GmccEnvironment.emit(pluginRoot: "/p", inheritedPath: "/usr/bin")
        let path = lines.first { $0.hasPrefix("PATH=") }!
        // CLAUDE_ENV_FILE does no shell expansion — a $PATH reference would
        // corrupt the session's PATH.
        XCTAssertFalse(path.contains("$"))
    }

    func testShimResolvesGmccRootAtCallTime() {
        XCTAssertTrue(GmccEnvironment.shimScript
            .contains(#"exec "${GMCC_ROOT:-$HOME/gmcc}/bin/gm" "$@""#))
        XCTAssertTrue(GmccEnvironment.shimScript.hasPrefix("#!/bin/sh"))
    }

    func testCheckFlagsCkfsRootMismatch() {
        // check() reads the claim from the process env; the db side comes in
        // via the response. Point the response somewhere the env can't be.
        let response = PathsGetResponse(
            gmccRoot: Paths.root.path, dbPath: "", socketPath: "", backupsRoot: "",
            ckfsRoot: "/definitely/not/the/env/value",
            kbiteRoot: "", kbiteOpenRoot: "", kbiteDigestedRoot: "")
        // Only meaningful when the env carries GMCC_CKFS_ROOT at all; the
        // finding is required whenever it does.
        if let claimed = ProcessInfo.processInfo.environment["GMCC_CKFS_ROOT"],
           !claimed.isEmpty {
            let findings = GmccEnvironment.check(response)
            XCTAssertTrue(findings.contains { $0.code == "ckfs_root_mismatch" })
        }
        // Agreement produces no ckfs finding.
        let agreeing = PathsGetResponse(
            gmccRoot: Paths.root.path, dbPath: "", socketPath: "", backupsRoot: "",
            ckfsRoot: GmccEnvironment.fallbackCkfsRoot.path,
            kbiteRoot: "", kbiteOpenRoot: "", kbiteDigestedRoot: "")
        XCTAssertFalse(GmccEnvironment.check(agreeing).contains { $0.code == "ckfs_root_mismatch" })
    }
}
