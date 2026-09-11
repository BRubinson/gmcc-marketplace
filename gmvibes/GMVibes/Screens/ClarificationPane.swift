import SwiftUI
import GMCCDaemonKit

/// Read-only clarification section — the app's render of the db-native
/// clarification (CLARIFY_GET, m0025 split): user questions with option/
/// selection children, weighted internal notes, and the care package (the
/// standalone clarified-intent bundle — nothing writes prompt content).
/// All clarify writes stay bot/CLI-side; the data model is shaped so a
/// future GMVibes surface can answer questions through these same rows.
struct ClarificationPane: View {
    let phase: PromptPhaseStore.Phase<ClarifyGetResponse>

    var body: some View {
        switch phase {
        case .idle:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading clarification…").font(.callout).foregroundStyle(.secondary)
            }
        case .absent:
            // Stays READ-ONLY: every clarify write is bot/CLI-side by design.
            Label("Not opened yet — run the bot to start clarification.",
                  systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .loaded(let response):
            content(response)
        }
    }

    @ViewBuilder
    private func content(_ response: ClarifyGetResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statusChip(response.summary.clarificationStatus)
                Spacer()
            }

            if let package = response.carePackage {
                carePackageBlock(package)
            }

            if !response.questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Questions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(response.questions, id: \.uuid) { question in
                        questionRow(question)
                    }
                }
            }

            if !response.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Internal Notes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(response.notes, id: \.uuid) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    // MARK: Care package

    @ViewBuilder
    private func carePackageBlock(_ package: CarePackageRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Care Package")
                    .font(.subheadline.weight(.semibold))
                packageChip(package.status)
                Spacer()
            }
            if !package.clarifiedIntent.isEmpty {
                Text(package.clarifiedIntent)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.blue.opacity(0.06), in: .rect(cornerRadius: 8))
            }
            let refCount = package.dopeRefs.count + package.kbiteRefs.count
                + package.explorationRefs.count
            if refCount > 0 {
                Text("\(package.dopeRefs.count) dope · \(package.kbiteRefs.count) kbite · \(package.explorationRefs.count) exploration refs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Questions

    private func questionRow(_ question: ClarificationQuestionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                rowStatusIcon(question.status)
                Text(question.question)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
            }
            ForEach(question.options, id: \.uuid) { option in
                let selected = question.selectedOptionUuids.contains(option.uuid)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.green : Color.secondary)
                    Text(option.body)
                        .font(.callout)
                        .foregroundStyle(selected ? .primary : .secondary)
                        .textSelection(.enabled)
                }
                .padding(.leading, 18)
            }
            if let answer = question.answerText, !answer.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(answer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.leading, 18)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Notes

    private func noteRow(_ note: ClarificationNoteRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let weight = note.weight {
                Text("w\(weight)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(weight < 100 ? .orange : .secondary)
            }
            Text(note.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: Chips

    @ViewBuilder
    private func rowStatusIcon(_ status: String) -> some View {
        switch ClarificationRowStatus(rawValue: status) {
        case .answered:
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").font(.caption).foregroundStyle(.secondary)
        default:
            Image(systemName: "circle").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func packageChip(_ status: String) -> some View {
        let (label, color): (String, Color) = status == "ready"
            ? ("Ready", .green) : ("Building", .orange)
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func statusChip(_ status: ClarificationStatus?) -> some View {
        let (label, color): (String, Color) = switch status {
        case .building: ("Building", .orange)
        case .answering: ("Answering", .blue)
        case .complete: ("Complete", .green)
        case .none: ("—", .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
