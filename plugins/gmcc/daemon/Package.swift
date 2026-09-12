// swift-tools-version:6.0

// GMCCDaemon — the GMCC daemon Swift package (v16).
//
// Products:
//   - GMCCDaemonKit  (library)   shared by gm, gmcc_daemon, and GMVibes (local package import)
//   - gmcc_daemon    (executable) the single-writer daemon that owns ~/gmcc/gmcc.db
//   - gm             (executable) the CLI Claude calls directly — a socket client, never touches the db
//
// Platform floor macOS 14: needed for the Observation framework (@Observable-friendly
// DaemonClient) and comfortably below GMVibes' deployment target.
// swift-argument-parser is GONE with the CLI it existed for. A large declarative
// command tree justified the dependency; a dozen ops verbs plus a raw
// passthrough does not, and gmcc_hook parses argv by hand.

import PackageDescription

let package = Package(
    name: "GMCCDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GMCCDaemonKit", targets: ["GMCCDaemonKit"]),
        .executable(name: "gmcc_daemon", targets: ["gmcc_daemon"]),
        .executable(name: "gmcc_mcp", targets: ["gmcc_mcp"]),
        .executable(name: "gmcc_hook", targets: ["gmcc_hook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "GMCCDaemonKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "gmcc_daemon",
            dependencies: ["GMCCDaemonKit"]
        ),
                // The MCP stdio server (m0025): the agent PEN surface as typed MCP
        // tools — a THIRD thin client of the daemon socket, never a second
        // db writer. Hand-rolled JSON-RPC (initialize/tools/list/tools/call)
        // over GMCCDaemonKit only — no new dependencies.
        .executableTarget(
            name: "gmcc_mcp",
            dependencies: ["GMCCDaemonKit"]
        ),
        // The shell-callable client. NO ArgumentParser: that dependency exists
        // for a large declarative command tree, and this is a dozen ops verbs
        // plus a raw passthrough. It dies with the CLI it was pulled for.
        .executableTarget(
            name: "gmcc_hook",
            dependencies: ["GMCCDaemonKit"]
        ),
        // Excluded from `swift build -c release` (build_daemon.sh) and from the
        // GMVibes vendor copy (library-only manifest) — daemon/gm ship untouched.
        .testTarget(
            name: "GMCCDaemonKitTests",
            // gm dependency: CheatsheetTests walks the GM command tree to keep
            // the cheatsheet drift-guarded against the real verb surface.
            dependencies: ["GMCCDaemonKit"],
            exclude: ["Fixtures"]
        ),
    ]
)
