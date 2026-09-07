import Foundation
import GMCCDaemonKit

/// Contained writer for `{instanceRoot}/.gmcc/.screenshots/` — the ONLY repo
/// filesystem output of the diagram feature, produced by the gm CLIENT
/// process (the daemon gains no new file writer). Copies DopeRepoSandbox's
/// three containment layers: loud pre-flight on the instance root, name
/// re-validation, and a symlink-resolving prefix guard on every path handed
/// out.
///
/// Gitignore ownership: on first use the sandbox writes
/// `.gmcc/.screenshots/.gitignore` containing `*` — a SELF-IGNORING
/// directory (git honors nested ignore files), so the feature never edits
/// the user's root .gitignore (no merge conflicts, no clobbered content,
/// works in every checkout with zero migration).
struct ScreenshotSandbox {
    let instanceRoot: URL
    let screenshotsRoot: URL

    struct SandboxError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func resolve(instanceRoot raw: String) throws -> ScreenshotSandbox {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SandboxError("instance root is empty — the diagram's instance row has no path")
        }
        guard trimmed.hasPrefix("/") else {
            throw SandboxError("instance root is not an absolute path: \(trimmed)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SandboxError("instance root is missing or stale: \(trimmed)")
        }
        let root = URL(fileURLWithPath: trimmed).standardizedFileURL
        let screenshots = root.appendingPathComponent(".gmcc/.screenshots", isDirectory: true)
        let resolvedRoot = root.resolvingSymlinksInPath()
        let resolvedShots = screenshots.resolvingSymlinksInPath()
        guard resolvedShots.path.hasPrefix(resolvedRoot.path + "/") else {
            throw SandboxError(
                "refusing symlinked screenshots root: \(screenshots.path) resolves to \(resolvedShots.path)")
        }
        return ScreenshotSandbox(instanceRoot: root, screenshotsRoot: screenshots)
    }

    /// Write PNG bytes as `{name}.png`, creating the self-gitignored
    /// directory on first use. Returns the absolute path written.
    func writePNG(_ data: Data, name: String) throws -> String {
        // Name re-validation even for callers that built it themselves — a
        // `/` or `..` can never smuggle a write outside the sandbox.
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."),
              !name.hasPrefix(".") else {
            throw SandboxError("illegal screenshot name: \(name)")
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: screenshotsRoot.path) {
            try fm.createDirectory(at: screenshotsRoot, withIntermediateDirectories: true)
        }
        let gitignore = screenshotsRoot.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: gitignore.path) {
            try Data("*\n".utf8).write(to: gitignore, options: .atomic)
        }
        let url = try contained(screenshotsRoot.appendingPathComponent(name + ".png"))
        try data.write(to: url, options: .atomic)
        return url.path
    }

    /// Final belt-and-braces guard — symlink-resolving, not lexical.
    private func contained(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        let resolvedRoot = screenshotsRoot.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(resolvedRoot.path + "/") else {
            throw SandboxError("path escapes the screenshots root: \(url.path)")
        }
        return standardized
    }
}
