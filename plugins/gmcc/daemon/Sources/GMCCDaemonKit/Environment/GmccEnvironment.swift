import Foundation

/// Single home for the SessionStart env contract: the emitted line set, the
/// bare-`gm` resolution rule, the installable shim text, and the env-vs-db
/// consistency check. Kit-level so GMVibes can adopt the same resolution
/// without a second implementation.
///
/// `emit` is socket-free by construction — every value comes from
/// ProcessInfo/Paths (plus an optional db-provided ckfs root the caller
/// fetched best-effort). Only `check` needs a daemon response.
public enum GmccEnvironment {

    public struct Finding {
        public let code: String
        public let message: String
        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    /// `$GMCC_CKFS_ROOT` when set, else `~/gmcc_ckfs` — the daemon-free
    /// resolution used when the db value is unavailable.
    public static var fallbackCkfsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["GMCC_CKFS_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmcc_ckfs", isDirectory: true)
    }

    /// The full CLAUDE_ENV_FILE line set — KEY=VALUE, one per line, no shell
    /// interpolation (the env file does no expansion, so PATH ships as a
    /// fully-resolved literal).
    ///
    /// - `dbCkfsRoot`: pathsGet().ckfsRoot when the daemon answered — emitting
    ///   the DB value makes the env/db match invariant true by construction.
    public static func emit(
        pluginRoot: String, inheritedPath: String, dbCkfsRoot: String? = nil
    ) -> [String] {
        var lines = ["GMCC_BOOTED=1", "GMCC_PLUGIN_ROOT=\(pluginRoot)"]
        // GMCC_ROOT is a passthrough, not a computation: the SessionStart hook
        // parsed it from .gmcc_sandbox and Paths.root already resolved against
        // it. Emitting it is the split-brain fix — without this line the
        // session believes it is sandboxed while in-session gm drives prod.
        if let root = ProcessInfo.processInfo.environment["GMCC_ROOT"], !root.isEmpty {
            lines.append("GMCC_ROOT=\(root)")
        }
        lines.append("GMCC_CKFS_ROOT=\(dbCkfsRoot ?? fallbackCkfsRoot.path)")
        lines.append("PATH=\(pathValue(current: inheritedPath))")
        return lines
    }

    /// This runtime's bin first, deduped: prepend `Paths.bin` and drop any
    /// other component that already points at it, so re-boots are idempotent
    /// and a sandbox session can never resolve bare `gm` to the prod binary
    /// through a stale leading entry.
    public static func pathValue(current: String) -> String {
        let mine = Paths.bin.path
        let survivors = current
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0 != mine }
        return ([mine] + survivors).joined(separator: ":")
    }

    /// Env-vs-db agreement (the user's r35 ruling: "both should always match
    /// or we get worried"). The db is the source; the env is the claim.
    public static func check(_ paths: PathsGetResponse) -> [Finding] {
        var findings: [Finding] = []
        let env = ProcessInfo.processInfo.environment
        if let claimed = env["GMCC_CKFS_ROOT"], !claimed.isEmpty,
           URL(fileURLWithPath: claimed).standardizedFileURL.path
               != URL(fileURLWithPath: paths.ckfsRoot).standardizedFileURL.path {
            findings.append(Finding(code: "ckfs_root_mismatch", message:
                "[GMB] WARN: ckfs_root disagreement — env \(claimed) vs db \(paths.ckfsRoot). "
                + "In a sandbox: gm sandbox refresh. In prod: gm config set --key ckfs_root --value <correct>."))
        }
        if let claimed = env["GMCC_ROOT"], !claimed.isEmpty,
           URL(fileURLWithPath: claimed).standardizedFileURL.path
               != URL(fileURLWithPath: paths.gmccRoot).standardizedFileURL.path {
            findings.append(Finding(code: "gmcc_root_mismatch", message:
                "[GMB] WARN: gmcc_root disagreement — env \(claimed) vs daemon \(paths.gmccRoot). "
                + "The daemon answering this socket lives elsewhere; re-run gm sandbox refresh."))
        }
        return findings
    }

    /// The installable resolver shim. Resolves at CALL time so one install
    /// serves prod and every sandbox generation; sandbox launchers and the
    /// SessionStart hook set GMCC_ROOT.
    public static let shimScript = """
        #!/bin/sh
        # GMCC gm resolver — installed by `gm setup --install-path`. Do not edit.
        # Resolves at call time so one install serves prod and every sandbox
        # generation; sandbox launchers and the SessionStart hook set GMCC_ROOT.
        exec "${GMCC_ROOT:-$HOME/gmcc}/bin/gm" "$@"
        """
}
