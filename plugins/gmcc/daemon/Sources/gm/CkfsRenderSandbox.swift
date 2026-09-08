import Foundation
import GMCCDaemonKit

/// Contained writer for rendered diagram files under the CKFS root.
///
/// Replaces `ScreenshotSandbox`, which existed to write into an instance's
/// repo checkout. That anchor is gone: renders live in CKFS storage now, at
/// every tier. Two consequences fall out and both are simplifications —
/// PROJECT-tier diagrams stop being a special case with nowhere to write,
/// and there is no `.gitignore` to own, because CKFS is outside the repo
/// entirely.
///
/// The three containment layers survive verbatim from `DopeRepoSandbox`,
/// because the threat did not change: a loud pre-flight on the root, name
/// re-validation on every segment, and a symlink-RESOLVING prefix guard on
/// the final path. Lexical checks alone would miss a symlink planted inside
/// the tree.
struct CkfsRenderSandbox {
    let ckfsRoot: URL

    struct SandboxError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func resolve(ckfsRoot raw: String) throws -> CkfsRenderSandbox {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SandboxError("ckfs_root is empty — run gm doctor")
        }
        guard trimmed.hasPrefix("/") else {
            throw SandboxError("ckfs_root is not an absolute path: \(trimmed)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SandboxError("ckfs_root is missing or stale: \(trimmed)")
        }
        return CkfsRenderSandbox(
            ckfsRoot: URL(fileURLWithPath: trimmed).standardizedFileURL)
    }

    /// Absolute URL for a CKFS-relative path, proven to stay inside the root.
    func url(forRelativePath relative: String) throws -> URL {
        let segments = try DiagramStorage.sanitizedSegments(relative, label: "render path")
        var url = ckfsRoot
        for segment in segments { url.appendPathComponent(segment) }
        return try contained(url)
    }

    /// Write bytes atomically, creating intermediate directories.
    @discardableResult
    func write(_ data: Data, toRelativePath relative: String) throws -> String {
        let url = try url(forRelativePath: relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url.path
    }

    func read(relativePath relative: String) -> Data? {
        guard let url = try? url(forRelativePath: relative) else { return nil }
        return try? Data(contentsOf: url)
    }

    func exists(relativePath relative: String) -> Bool {
        guard let url = try? url(forRelativePath: relative) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Symlink-resolving containment. Resolves the ROOT too, so a symlinked
    /// ckfs_root (a real setup, not a hypothetical) compares like with like
    /// instead of failing every write.
    private func contained(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        let resolvedRoot = ckfsRoot.resolvingSymlinksInPath().path
        // Resolve the deepest EXISTING ancestor: the file itself usually
        // does not exist yet on a first render, and resolvingSymlinksInPath
        // on a missing leaf cannot see through a symlinked parent.
        var probe = standardized.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: probe.path),
              probe.path != "/", probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        let resolvedProbe = probe.resolvingSymlinksInPath().path
        guard resolvedProbe == resolvedRoot
                || resolvedProbe.hasPrefix(resolvedRoot + "/") else {
            throw SandboxError(
                "path escapes the CKFS root: \(standardized.path) resolves under \(resolvedProbe)")
        }
        return standardized
    }
}
