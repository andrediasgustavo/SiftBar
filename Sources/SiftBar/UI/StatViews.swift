import SwiftUI

/// A single key number in the header strip.
struct Stat {
    let value: String
    let label: String
    let tint: Color
    let help: String
}

struct StatBlock: View {
    let stat: Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stat.value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(stat.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(stat.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(stat.help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.label): \(stat.value). \(stat.help)")
    }
}
