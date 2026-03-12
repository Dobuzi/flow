import SwiftUI

struct OperatorControlsSection: View {
    let controls: OperatorControlsPanelState
    let activationFeedback: String?
    let isPerformingAction: Bool
    let onPromote: () -> Void
    let onDemote: () -> Void
    let onRollback: () -> Void

    var body: some View {
        Section("Operator Controls") {
            LabeledContent("Status", value: controls.operatorActivationStatus.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            LabeledContent("Active Snapshot", value: controls.activeSnapshotID ?? "None")
            LabeledContent("Last Known Good", value: controls.lastKnownGoodSnapshotID ?? "None")
            LabeledContent("Latest Candidate", value: controls.latestCandidateSnapshotID ?? "None")
            if let compatibility = controls.latestCandidateCompatibility {
                LabeledContent("Candidate Compatibility", value: compatibility.rawValue.capitalized)
            }
            if let eligible = controls.latestCandidateEligibleForActivation {
                LabeledContent("Candidate Eligible", value: eligible ? "Yes" : "No")
            }
            LabeledContent("Rollback Available", value: controls.rollbackAvailable ? "Yes" : "No")
            if let latestEventSummary = controls.latestActivationEventSummary {
                LabeledContent("Latest Activation Event", value: latestEventSummary)
            }

            operatorActionRow(controls.promote, action: onPromote)
            operatorActionRow(controls.demote, action: onDemote)
            operatorActionRow(controls.rollback, action: onRollback)

            if let activationFeedback {
                Text(activationFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isPerformingAction {
                ProgressView()
            }
        }
    }

    private func operatorActionRow(_ control: OperatorActionControl, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(control.title, action: action)
                .disabled(!control.canExecute || isPerformingAction)
            Text(control.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
