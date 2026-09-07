import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm setup — client-side initialization: ensure ~/gmcc/ dirs, autostart the
/// daemon (which creates and migrates the db), and optionally install a
/// launchd agent. CONTEXT_ENSURE covers daemon-side bootstrap.
struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize ~/gmcc/ runtime dir, database, and (optionally) a launchd agent.")

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Also install ~/Library/LaunchAgents/com.gmcc.daemon.plist.")
    var launchd = false

    @Flag(name: .long, help: """
        Also install the bare-`gm` resolver shim onto the user's PATH \
        (resolves ${GMCC_ROOT:-$HOME/gmcc}/bin/gm at call time).
        """)
    var installPath = false

    @Option(name: .long, help: "Directory for the PATH shim (default: first writable of ~/.local/bin, ~/bin).")
    var pathDir: String?

    func run() throws {
        // The launchd plist/label and the PATH shim are prod singletons:
        // installing either from a sandboxed process would point every shell
        // (or launchd) at sandbox paths. Structural refusal, shared.
        if launchd { try requireProdEnvironment(for: "--launchd") }
        if installPath { try requireProdEnvironment(for: "--install-path") }

        try Paths.ensureRuntimeDirs()

        let response = try withClient { client in try client.status() }

        if launchd {
            try installLaunchdPlist()
        }
        var shimLocation: URL?
        if installPath {
            shimLocation = try installPathShim()
        }

        if output.json {
            printJSON(response)
        } else {
            print("[gm] setup complete")
            print("  runtime dir:    \(Paths.root.path)")
            print("  database:       \(response.dbPath)")
            print("  schema version: \(response.schemaVersion)")
            if launchd {
                print("  launchd agent:  ~/Library/LaunchAgents/com.gmcc.daemon.plist")
            }
            if let shimLocation {
                print("  gm shim:        \(shimLocation.path)")
                reportPathMembership(of: shimLocation.deletingLastPathComponent())
            }
        }
    }

    /// The prod-only refusal shared by --launchd and --install-path.
    private func requireProdEnvironment(for flag: String) throws {
        if ProcessInfo.processInfo.environment["GMCC_ROOT"]?.isEmpty == false {
            throw ValidationError(
                "gm setup \(flag) is prod-only: refusing while GMCC_ROOT is set (sandbox environment).")
        }
    }

    /// Install the call-time resolver shim. Idempotent: rewrites a file this
    /// setup owns; refuses to clobber anything else; refuses a target inside
    /// a gmcc runtime root (self-exec loop guard).
    private func installPathShim() throws -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = pathDir.map { [URL(fileURLWithPath: $0, isDirectory: true)] }
            ?? [home.appendingPathComponent(".local/bin", isDirectory: true),
                home.appendingPathComponent("bin", isDirectory: true)]

        guard let dir = candidates.first else {
            throw ValidationError("no shim directory candidate")
        }
        // Loop guard: a shim inside a gmcc runtime bin would exec itself.
        if dir.standardizedFileURL.path.hasSuffix("/gmcc/bin")
            || dir.standardizedFileURL.path.contains("/gmcc/bin/") {
            throw ValidationError(
                "refusing to install the gm shim inside a gmcc runtime bin (\(dir.path)) — it would exec itself.")
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("gm", isDirectory: false)
        if fm.fileExists(atPath: target.path) {
            let existing = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
            guard existing.contains("GMCC gm resolver") else {
                throw ValidationError(
                    "\(target.path) exists and is not the GMCC shim — refusing to overwrite; pass --path-dir to choose another directory.")
            }
        }
        try GmccEnvironment.shimScript.write(to: target, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        return target
    }

    /// GMCC never writes shell profiles — print the remedy instead.
    private func reportPathMembership(of dir: URL) {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let components = path.split(separator: ":").map(String.init)
        if !components.contains(dir.path) {
            print("  NOTE: \(dir.path) is not on your PATH — add to your shell profile:")
            print("        export PATH=\"\(dir.path):$PATH\"")
        }
    }

    private func installLaunchdPlist() throws {
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.gmcc.daemon</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(Paths.binDaemon.path)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
        let plistURL = agentsDir.appendingPathComponent("com.gmcc.daemon.plist")
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
    }
}
