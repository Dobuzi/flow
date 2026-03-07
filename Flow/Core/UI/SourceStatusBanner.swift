import SwiftUI

struct SourceStatusBanner: View {
    let status: DatasetSourceStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
            Text(status.message)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(backgroundColor.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("\(status.source.title) status: \(status.message)")
    }

    private var iconName: String {
        switch status.state {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.circle"
        case .limited:
            return "exclamationmark.triangle"
        case .unavailable:
            return "xmark.octagon"
        }
    }

    private var backgroundColor: Color {
        switch status.state {
        case .loading:
            return .blue
        case .ready:
            return .green
        case .limited:
            return .orange
        case .unavailable:
            return .red
        }
    }
}
