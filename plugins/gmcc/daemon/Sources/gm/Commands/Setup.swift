import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm setup — client-side initialization: ensure ~/gmcc/ dirs, autostart the
/// daemon (which creates and migrates the db), and optionally install a
/// launchd agent. The legacy SETUP wire message is retired — CONTEXT_ENSURE
/// covers daemon-side bootstrap.
struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize ~/gmcc/ runtime dir, database, and (optionally) a launchd agent.")

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Also install ~/Library/LaunchAgents/com.gmcc.daemon.plist.")
    var launchd = false

    func run() throws {
        try Paths.ensureRuntimeDirs()

        let response = try withClient { client in try client.status() }

        if launchd {
            try installLaunchdPlist()
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
