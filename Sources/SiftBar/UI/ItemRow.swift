import SwiftUI

struct ItemRow: View {
    let item: ScanItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RiskBadge(risk: item.risk)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(item.impactLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.evidence)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        Text(risk.label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}
