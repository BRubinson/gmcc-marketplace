import ArgumentParser
import Foundation
import GMCCDaemonKit

// GitContext / CkfsYaml / ContextBuilder / ClientKey moved into
// GMCCDaemonKit/Client/ClientContext.swift (m0025) so gm and the gmcc_mcp
// server share ONE implementation. This file keeps the gm-only pieces:
// kbite path resolution and the ArgumentParser conformances.

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

    /// The digested-archive tree for one kbite (same env-first idiom as
    /// openMaw — sandbox launchers set the var, prod resolves via the db).
    static func digested(name: String) throws -> URL {
        if let root = ProcessInfo.processInfo.environment["GMCC_KBITE_DIGESTED"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
        }
        let paths = try withClient { try $0.pathsGet() }
        return URL(fileURLWithPath: paths.kbiteDigestedRoot, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// The kbite identity dir ({kbite_root}/{name}: KBITE_PURPOSE.md etc.).
    static func identity(name: String) throws -> URL {
        let paths = try withClient { try $0.pathsGet() }
        return URL(fileURLWithPath: paths.kbiteRoot, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// The one universal archive bucket — purged/replaced trees MOVE here,
    /// never rm.
    static func coldStorage() throws -> URL {
        let paths = try withClient { try $0.pathsGet() }
        return URL(fileURLWithPath: paths.ckfsRoot, isDirectory: true)
            .appendingPathComponent("_archive", isDirectory: true)
            .appendingPathComponent("cold_storage", isDirectory: true)
    }
}

// ArgumentParser conformances for wire enums used as CLI options.
extension ChangeKind: ExpressibleByArgument {}
extension PromptStatus: ExpressibleByArgument {}
extension KbiteScope: ExpressibleByArgument {}
extension KeywordTagLevel: ExpressibleByArgument {}
extension KbiteImportCollision: ExpressibleByArgument {}
extension ChangeDepth: ExpressibleByArgument {}
extension ConfigKey: ExpressibleByArgument {}
extension SearchKind: ExpressibleByArgument {}
extension ExplorationFindingKind: ExpressibleByArgument {}
extension CarePackageRefKind: ExpressibleByArgument {}
extension BotVariant: ExpressibleByArgument {}
extension ReviewFindingKind: ExpressibleByArgument {}
extension ReviewVerdict: ExpressibleByArgument {}
extension ReviewFindingStatus: ExpressibleByArgument {}
extension DopeEntityType: ExpressibleByArgument {}
extension DopePropertyDataType: ExpressibleByArgument {}
