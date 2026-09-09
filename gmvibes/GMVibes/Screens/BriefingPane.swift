import SwiftUI
import GMCCDaemonKit

/// Read-only briefing section (BRIEFING_LIST + per-row BRIEFING_GET): the
/// context packages a doper agent assembled per phase step. One sub-section
/// per row, keyed by `briefing_for_step` (registry-extensible — whatever LIST
/// returns is rendered, never a hardcoded step set). Staleness is the
/// daemon's read-time computation; it renders as a subtle amber badge with
/// expandable ghost-path detail — warn, never block. All briefing writes
/// stay bot/CLI-side.
struct BriefingPane: View {
    let phase: PromptPhaseStore.Phase<[PromptPhaseStore.BriefingItem]>

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading briefings…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            notOpened
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .loaded(let items):
            if items.isEmpty {
                // Empty list IS the never-opened state — briefings have no
                // SUMMARY_ABSENT on LIST.
                notOpened
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(items, id: \.briefing.uuid) { item in
                        section(item)
                    }
                }
            }
        }
    }

    private var notOpened: some View {
        Label("No briefings yet — the doper writes one at each phase boundary.",
              systemImage: "shippingbox")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func section(_ item: PromptPhaseStore.BriefingItem) -> some View {
        let briefing = item.briefing
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(stepTitle(briefing.briefingForStep))
                    .font(.subheadline.weight(.semibold))
                statusChip(briefing.status)
                stalenessBadge(item.staleness)
                Spacer()
            }

            // Body is non-empty only once ready; while building the doper is
            // still composing — absence isn't an error.
            if !briefing.body.isEmpty {
                Text(briefing.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.teal.opacity(0.06), in: .rect(cornerRadius: 8))
            }

            let dopePaths = decodeDopeRefs(briefing.dopeRefs)
            if !dopePaths.isEmpty {
                sectionHeader("Dope Refs")
                chipFlow(dopePaths, ghosts: Set(item.staleness.ghostDotPaths))
            }

            let kbites = decodeKbiteRefs(briefing.kbiteRefs)
            if !kbites.isEmpty {
                sectionHeader("KBites")
                ForEach(kbites, id: \.fileUuid) { ref in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "text.book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ref.brief.isEmpty ? ref.fileUuid : ref.brief)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Staleness (warn, never block)

    @ViewBuilder
    private func stalenessBadge(_ staleness: BriefingStaleness) -> some View {
        let ghosts = staleness.ghostDotPaths
        if staleness.drifted || !ghosts.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    if let stamped = staleness.stampedRevision,
                       let current = staleness.currentRevision, staleness.drifted {
                        Text("Dope scope moved: composed at r\(stamped), now r\(current).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ghosts, id: \.self) { path in
                        Text(path)
                            .font(.caption.monospaced())
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            } label: {
                Label(ghosts.isEmpty ? "dope drifted" : "dope drifted · \(ghosts.count) ghost\(ghosts.count == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: .capsule)
                    .foregroundStyle(.orange)
            }
            .disclosureGroupStyle(.automatic)
        }
    }

    // MARK: Refs

    private struct KbiteRef: Decodable {
        let fileUuid: String
        let brief: String

        enum CodingKeys: String, CodingKey {
            case fileUuid = "file_uuid"
            case brief
        }
    }

    private func decodeDopeRefs(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func decodeKbiteRefs(_ json: String) -> [KbiteRef] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([KbiteRef].self, from: data)) ?? []
    }

    private func chipFlow(_ paths: [String], ghosts: Set<String>) -> some View {
        // Simple wrapping-free flow: dot-paths are short and few; a vertical
        // list keeps them selectable and legible without a layout dependency.
        VStack(alignment: .leading, spacing: 3) {
            ForEach(paths, id: \.self) { path in
                Text(path)
                    .font(.caption.monospaced())
                    .strikethrough(ghosts.contains(path))
                    .foregroundStyle(ghosts.contains(path) ? .secondary : .primary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary.opacity(0.4), in: .capsule)
            }
        }
    }

    // MARK: Bits

    private func stepTitle(_ raw: String) -> String {
        raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "ready": ("Ready", .green)
        case "building": ("Building", .orange)
        default: (status, .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
