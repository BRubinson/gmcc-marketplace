import ArgumentParser
import CryptoKit
import Foundation
import GMCCDaemonKit

/// Client-side identity derivation, shared by every subcommand that needs the
/// project → instance → session triple. The CLI gathers the git context (repo
/// root, basename, branch) from the working directory and mirrors
/// detect_repo.sh's identity conventions (instance code =
/// {repo}_{4-char md5 of abs path}, branch slugified / → __) so db rows line
/// up with the ckfs tree. Where a ckfs data file already carries a uuid or a
/// kbite registry, both are passed along so the db reuses/seeds them.
struct GitContext {
    let repoRoot: String
    let repoName: String
    let branch: String

    /// {repo}_{first 4 hex of md5(abs path)} — matches detect_repo.sh's hash4.
    /// Single Swift home of the convention: InstanceIdentity in the kit
    /// (shared with SandboxRetarget).
    var instanceCode: String {
        InstanceIdentity.code(repoName: repoName, absolutePath: repoRoot)
    }

    /// Branch with / slugified to __ — matches detect_repo.sh.
    var sessionCode: String {
        branch.replacingOccurrences(of: "/", with: "__")
    }

    static func detect() throws -> GitContext {
        guard let repoRoot = runGit(["rev-parse", "--show-toplevel"]) else {
            throw ValidationError("not inside a git repository — gm needs git context")
        }
        // Detached HEAD prints nothing here. Fail loudly instead of falling
        // back to "main": the daemon-side SESSION_RESOLVE reports detached as
        // "nothing checked out", and a silent main fallback would have gm
        // writing into the main session while the daemon disagrees.
        guard let branch = runGit(["branch", "--show-current"]), !branch.isEmpty else {
            throw ValidationError("HEAD is detached — gm needs a checked-out branch for session context")
        }
        return GitContext(
            repoRoot: repoRoot,
            repoName: URL(fileURLWithPath: repoRoot).lastPathComponent,
            branch: branch
        )
    }

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }
}

enum CkfsYaml {
    /// `~/gmcc_ckfs/`, or `$GMCC_CKFS_ROOT` when set — same env name the
    /// SessionStart hook already exports, so sandbox sessions redirect the
    /// CLI's yaml reads without a second variable.
    static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["GMCC_CKFS_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmcc_ckfs", isDirectory: true)
    }()

    /// Extract the first top-level `uuid:` from a ckfs data yaml, if present.
    static func uuid(_ relativePath: String) -> String? {
        scalar("uuid", relativePath)
    }

    /// Extract the first top-level single-line scalar value for `key:` from a
    /// ckfs data yaml, if present. Block scalars (|, >) are not resolved.
    static func scalar(_ key: String, _ relativePath: String) -> String? {
        guard let text = try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8) else {
            return nil
        }
        let prefix = "\(key): "
        for line in text.split(separator: "\n") {
            if line.hasPrefix(prefix) {
                let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Strip one layer of surrounding quotes — GMVibes' yaml encoder may quote
    /// scalars, and a literal-quoted code would create a duplicate kbite row.
    private static func unquoted(_ value: String) -> String {
        var v = value
        if v.count >= 2,
           (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    /// Lenient parse of a top-level `kbite:` registry: block-list scalar items
    /// (`- foo`), `- name:`/`- code:` mapping keys, inline flow lists
    /// (`kbite: [a, b]`), and a bare inline scalar. Returns nil for an
    /// empty/absent registry so the daemon's create-time inheritance (copy
    /// parent junctions) applies instead.
}

enum ContextBuilder {
    /// Build the full CONTEXT_ENSURE payload from the working directory's git
    /// identity plus whatever the ckfs tree already knows (uuids). Kbite
    /// registries are db-native — no yaml kbite reads on this path.
    static func ensureRequest() throws -> ContextEnsureRequest {
        let git = try GitContext.detect()
        let projectRel = "projects/\(git.repoName)"
        let instanceRel = "\(projectRel)/instances/\(git.instanceCode)"
        let sessionRel = "\(instanceRel)/sessions/\(git.sessionCode)"
        return ContextEnsureRequest(
            project: ProjectContext(
                gitRepoName: git.repoName,
                code: git.repoName,
                name: git.repoName,
                ckfsRelativeStoragePath: projectRel,
                uuid: CkfsYaml.uuid("\(projectRel)/project_data.gmcc.yaml")
            ),
            instance: InstanceContext(
                code: git.instanceCode,
                name: git.instanceCode,
                absoluteFileSystemPath: git.repoRoot,
                ckfsRelativeStoragePath: instanceRel,
                uuid: CkfsYaml.uuid("\(instanceRel)/instance_data.gmcc.yaml")
            ),
            session: SessionContext(
                code: git.sessionCode,
                name: git.sessionCode,
                ckfsRelativeStoragePath: sessionRel,
                uuid: CkfsYaml.uuid("\(sessionRel)/session_data.gmcc.yaml")
            )
        )
    }

    /// Idempotent resolve: ensure the chain and return the session uuid.
    /// Used by session/prompt subcommands when no --session-uuid is given.
    static func resolveSessionUuid(_ client: DaemonClient) throws -> String {
        try client.ensureContext(try ensureRequest()).sessionUuid
    }
}

/// Client-side kbite path resolution — the daemon never reads $GMCC_KBITE_*;
/// gm resolves absolute paths here and passes them in payloads.
enum KbitePaths {
    static func openMaw(name: String) throws -> URL {
        // Env-first keeps sandbox launchers (which set it explicitly)
        // working unchanged; the db fallback is what makes dropping the
        // session export safe — $GMCC_KBITE_OPEN is no longer emitted by
        // gm context env, the db owns the roots.
        if let root = ProcessInfo.processInfo.environment["GMCC_KBITE_OPEN"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
        }
        let paths = try withClient { try $0.pathsGet() }
        return URL(fileURLWithPath: paths.kbiteOpenRoot, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}

// ArgumentParser conformances for wire enums used as CLI options.
extension ChangeKind: ExpressibleByArgument {}
extension PromptStatus: ExpressibleByArgument {}
extension KbiteScope: ExpressibleByArgument {}
extension KeywordTagLevel: ExpressibleByArgument {}
extension ClarificationCategory: ExpressibleByArgument {}
extension AnswerSource: ExpressibleByArgument {}
extension ChangeDepth: ExpressibleByArgument {}
extension ConfigKey: ExpressibleByArgument {}
extension SearchKind: ExpressibleByArgument {}
extension ExplorationFindingKind: ExpressibleByArgument {}
extension ReviewFindingKind: ExpressibleByArgument {}
extension ReviewVerdict: ExpressibleByArgument {}
extension ReviewFindingStatus: ExpressibleByArgument {}
extension DopeEntityType: ExpressibleByArgument {}
extension DopePropertyDataType: ExpressibleByArgument {}
