import SwiftUI
import GMCCDaemonKit

/// The session view's DIAGRAMS tab — a real list of the session's SAVED
/// diagrams (DIAGRAM_LIST at SESSION tier), not the dope scopes it used to
/// show. A diagram is a document now; the scope it is drawn over is one of
/// its properties, not its identity.
///
/// Creating one binds it to a dope scope (read through the session's existing
/// DopeStore, so the tab shares one cache with the dope tab) and the CREATE
/// is what seeds the canvas — see DiagramCatalogStore.create. Importing pulls
/// a PROJECT-tier diagram down into this session as a copy.
struct SessionDiagramsPane: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(DiagramCatalogStore.self) private var diagrams
    let scope: SessionScope
    let windowID: SessionWindowID
    let projectUuid: String
    let onOpen: (DiagramWindowID) -> Void

    @State private var busy = false
    @State private var actionError: String?

    private var dopeStore: DopeStore { scope.dope }
    private var scopes: [DopeScopeRow] { dopeStore.sessionCandidates(.init(promptUuid: nil)) }
    private var owner: DiagramCatalogStore.Owner { .session(scope.sessionUuid) }
    private var rows: [DiagramRow] { diagrams.rows(owner) }
    private var projectRows: [DiagramRow] { diagrams.rows(.project(projectUuid)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .diagramList(scope.sessionUuid))
            await dopeStore.refresh(promptUuid: nil)
            await diagrams.refresh(owner)
            await diagrams.refresh(.project(projectUuid))
            for await _ in stream {
                await diagrams.refresh(owner)
            }
        }
        .alert("Diagram action failed", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Header actions

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                if scopes.isEmpty {
                    Text("Initialize a dope scope from the Dope tab first")
                } else {
                    ForEach(scopes, id: \.uuid) { row in
                        Button("\(row.name)  ·  \(row.code)") { create(from: row) }
                    }
                }
            } label: {
                Label("New Diagram", systemImage: "plus")
            }
            .disabled(busy)
            .help("Create a session diagram over one dope scope — the canvas is "
                  + "scaffolded from that scope once, at creation")

            Menu {
                if projectRows.isEmpty {
                    Text("This project has no project-tier diagrams")
                } else {
                    ForEach(projectRows, id: \.uuid) { row in
                        Button("\(row.name)  ·  \(row.code)") { importProjectDiagram(row) }
                    }
                }
            } label: {
                Label("Import Project Diagram", systemImage: "square.and.arrow.down")
            }
            .disabled(busy || projectRows.isEmpty)
            .help("Copy a project diagram into this session")

            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            // The normal pre-create state, not an error.
            ContentUnavailableView(
                "No Diagrams Yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text(scopes.isEmpty
                    ? "A diagram is drawn over a dope scope. Initialize one from the "
                      + "Dope tab, then create a diagram here."
                    : "Create one with New Diagram — it is scaffolded from the dope "
                      + "scope you pick."))
        } else {
            List(rows, id: \.uuid) { row in
                DiagramListRow(row: row, subtitle: subtitle(row)) {
                    onOpen(DiagramWindowID.saved(row, session: windowID))
                } menu: {
                    Button("Promote to Project") { promote(row) }
                        .help("Move this diagram up to the project tier")
                }
            }
            .listStyle(.inset)
        }
    }

    private func subtitle(_ row: DiagramRow) -> String {
        var parts = [row.code, "revision \(row.revision)"]
        if let scopeCode = row.dopeScopeCode { parts.insert("dope \(scopeCode)", at: 1) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func create(from scopeRow: DopeScopeRow) {
        run {
            let code = Self.uniqueCode(base: "\(scopeRow.code)_canvas",
                                       taken: Set(rows.map(\.code)))
            _ = try await diagrams.create(
                owner: owner, code: code, name: scopeRow.name,
                dopeScopeCode: scopeRow.code, projectUuid: projectUuid,
                sessionUuid: scope.sessionUuid)
        }
    }

    private func importProjectDiagram(_ row: DiagramRow) {
        run {
            let code = Self.uniqueCode(base: row.code, taken: Set(rows.map(\.code)))
            _ = try await diagrams.copy(row, to: owner, code: code, name: row.name,
                                        projectUuid: projectUuid)
        }
    }

    private func promote(_ row: DiagramRow) {
        run {
            try await diagrams.promote(row, to: .project, ownerUuid: projectUuid,
                                       from: owner)
        }
    }

    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await body()
            } catch let error as LocalizedError {
                actionError = error.errorDescription ?? String(describing: error)
            } catch let error as DaemonError {
                actionError = error.userMessage
            } catch {
                actionError = String(describing: error)
            }
            busy = false
        }
    }

    /// DIAGRAM_INIT is idempotent per (owner, code) — reusing a code would
    /// silently hand back the EXISTING diagram instead of making a new one,
    /// so a copy or a second canvas over one scope needs a fresh code.
    static func uniqueCode(base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base)_\(index)") { index += 1 }
        return "\(base)_\(index)"
    }
}

/// One diagram row: name, identity line, an overflow menu of row-level
/// actions. Shared by the session pane and the project rail.
struct DiagramListRow<Menu: View>: View {
    let row: DiagramRow
    let subtitle: String
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.body).lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SwiftUI.Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
    }
}
