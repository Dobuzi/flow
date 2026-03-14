import SwiftUI

struct ActivationTimelineView: View {
    let sourceTitle: String
    let entries: [OperatorTimelineEntry]

    var body: some View {
        List {
            Section("Source") {
                Text(sourceTitle)
            }

            if entries.isEmpty {
                Section("Timeline") {
                    Text("No activation events yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Timeline") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(entry.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let snapshotID = entry.snapshotID {
                                Text(snapshotID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.timestamp)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Activation Timeline")
    }
}
