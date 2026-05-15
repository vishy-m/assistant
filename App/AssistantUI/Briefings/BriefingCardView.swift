import SwiftUI
import AssistantShared

struct BriefingCardView: View {
    let payload: BriefingPayload
    let onActionable: (BriefingPayload.Actionable) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(payload.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
            Text(payload.body)
                .font(.system(size: 14))
                .lineLimit(6)
            if !payload.actionables.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(payload.actionables.enumerated()), id: \.offset) { _, a in
                        Button(a.label) { onActionable(a) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }
}
