import ArgumentParser
import Foundation
import GMCCDaemonKit

/// gm project list — enumerate every project in the db (the Landing browse
/// entry point).
struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Browse projects.",
        subcommands: [List.self, Update.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "All projects, ordered by code.")

        @OptionGroup var output: OutputOptions

        func run() throws {
            let response = try withClient { client in
                try client.listProjects()
            }
            if output.json {
                printJSON(response)
            } else {
                print("[gm] \(response.projects.count) project(s)")
                for p in response.projects {
                    print("  \(p.code) (\(p.name)) \(p.uuid)")
                    print("    primary branch: \(p.primaryProjectBranch)")
                }
            }
        }
    }

    /// gm project update — the only project-level mutation. Today it sets
    /// primary_project_branch (BASE_DOPED_BRANCH): the branch whose
    /// SESSION_INSTANCE dope scope may promote into the project's
    /// BASE_PROJECT scope. A project setting, not an instance one — it
    /// applies across every checkout consistently.
    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update a project's settings.")

        @Option(name: .customLong("project-uuid"), help: "Project to update.")
        var projectUuid: String

        @Option(name: .customLong("expected-version"),
                help: "Optimistic lock; from gm project list.")
        var expectedVersion: Int64

        @Option(name: .customLong("primary-project-branch"),
                help: "Branch whose dope scope promotes into BASE_PROJECT (default 'main').")
        var primaryProjectBranch: String?

        @OptionGroup var output: OutputOptions

        func run() throws {
            let response = try withClient { client in
                try client.updateProject(ProjectUpdateRequest(
                    projectUuid: projectUuid,
                    expectedVersion: expectedVersion,
                    primaryProjectBranch: primaryProjectBranch))
            }
            if output.json {
                printJSON(response)
            } else {
                let p = response.project
                print("[gm] project \(p.code) updated (v\(p.version))")
                print("  primary branch: \(p.primaryProjectBranch)")
            }
        }
    }
}
