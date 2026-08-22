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
// ArgumentParser is deliberately kept off GMCCDaemonKit so GMVibes doesn't inherit a CLI parser.

import PackageDescription

let package = Package(
    name: "GMCCDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GMCCDaemonKit", targets: ["GMCCDaemonKit"]),
        .executable(name: "gmcc_daemon", targets: ["gmcc_daemon"]),
        .executable(name: "gm", targets: ["gm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
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
        .executableTarget(
            name: "gm",
            dependencies: [
                "GMCCDaemonKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Excluded from `swift build -c release` (build_daemon.sh) and from the
        // GMVibes vendor copy (library-only manifest) — daemon/gm ship untouched.
        .testTarget(
            name: "GMCCDaemonKitTests",
            dependencies: ["GMCCDaemonKit"],
            exclude: ["Fixtures"]
        ),
    ]
)
