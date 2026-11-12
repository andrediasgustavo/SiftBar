import SwiftUI

/// One slice of a proportional bar (memory breakdown, disk categories).
struct BreakdownSegment: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let color: Color
    let memoryUnits: Bool

    init(name: String, bytes: Int64, color: Color, memoryUnits: Bool = false) {
        self.name = name
        self.bytes = bytes
        self.color = color
        self.memoryUnits = memoryUnits
    }

    var label: String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: memoryUnits ? .memory : .file
        )
    }
}

struct BreakdownBar: View {
    let segments: [BreakdownSegment]
    let total: Int64

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(segments.filter { $0.bytes > 0 }) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(for: segment, in: geometry.size.width))
                }
            }
        }
        .frame(height: 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.name) \($0.label)" }.joined(separator: ", "))
    }

    private func width(for segment: BreakdownSegment, in available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(0, available * CGFloat(segment.bytes) / CGFloat(total))
    }
}

struct BreakdownLegend: View {
    let segment: BreakdownSegment

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(segment.color)
                .frame(width: 7, height: 7)

            Text(segment.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(segment.label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}
