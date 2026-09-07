import SwiftUI
import GMCCDaemonKit

/// The session view's DIAGRAMS tab — the third tab, between prompts and dope.
///
/// A diagram is a canvas over one dope scope, so this lists the session's
/// scopes and opens the full-window Doped Viewer on the one you pick. It is
/// deliberately NOT a list of saved canvases: diagrams are not persisted past
/// the db in this pass, so presenting stored documents would promise a
/// durability that does not exist yet. When diagram persistence lands, this
/// pane grows a real diagram list behind the same navigation callback.
///
/// Reads through the session's existing DopeStore rather than issuing its own
/// DOPE_LIST, so the tab shares one cache with the dope tab and never shows a
/// divergent scope list.
struct SessionDiagramsPane: View {
    let scope: SessionScope
    /// Receives the scope CODE — the diagram workspace is keyed by it, the
    /// same contract DopePane's Diagram button uses.
    let onOpen: (String) -> Void

    private var store: DopeStore { scope.dope }
    private var scopes: [DopeScopeRow] { store.sessionCandidates(.init(promptUuid: nil)) }

    var body: some View {
        Group {
            if scopes.isEmpty {
                // The normal pre-init state, not an error: a session has no
                // dope scope until one is initialized from the Dope tab.
                ContentUnavailableView(
                    "No dope scopes yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(
                        "A diagram draws one dope scope. Initialize a scope from the Dope tab "
                        + "and it will appear here."))
            } else {
                List(scopes, id: \.uuid) { row in
                    Button { onOpen(row.code) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.body)
                                Text("\(row.code) · \(row.scopeType) · revision \(row.revision)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .task { await store.refresh(promptUuid: nil) }
    }
}
