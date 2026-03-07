import SwiftUI

struct NonBlockingErrorBanner: View {
    let error: FlowNonFatalError

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(errorTitle(for: error.scope))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text(error.message)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorTitle(for scope: FlowErrorScope) -> String {
        switch scope {
        case .dataLoad:
            return "Data Load Error"
        case .filtering:
            return "Filter Error"
        case .rendering:
            return "Render Error"
        case .insights:
            return "Insights Error"
        case .settings:
            return "Settings Error"
        }
    }
}
