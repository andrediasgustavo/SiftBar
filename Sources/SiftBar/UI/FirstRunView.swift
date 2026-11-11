import SwiftUI

/// First-run screen shown while there is no report yet.
///
/// It explains the three-step loop, lists what SiftBar inspects, reports the
/// Full Disk Access status and offers the single primary action. The header
/// hides its Analyze button in this state, so the window has exactly one call
/// to action.
struct FirstRunView: View {
    let includesProtectedFolders: Bool
    let isBusy: Bool
    let onAnalyze: () -> Void
    let onGrantAccess: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text("Welcome to SiftBar")
                    .font(.title2.weight(.semibold))

                Text("SiftBar is read-only: it inspects your Mac and only changes what you explicitly confirm. Nothing is modified without your approval.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
            }

            steps

            categories

            accessRow

            Button(action: onAnalyze) {
                Label(
                    isBusy ? "Analyzing…" : "Run First Analysis",
                    systemImage: "magnifyingglass"
                )
                .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)

            Text("You can run it again at any time from the menu bar or with ⌘R.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to SiftBar. Ready to analyze.")
    }

    // MARK: - Steps

    private var steps: some View {
        HStack(alignment: .top, spacing: 10) {
            step(number: 1, title: "Analyze", detail: "Read-only inspection")
            step(number: 2, title: "Review", detail: "Grouped by risk")
            step(number: 3, title: "Apply", detail: "Only what you confirm")
        }
        .frame(maxWidth: 560)
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .background(
                        Color.accentColor.opacity(0.14),
                        in: Circle()
                    )

                Text(title)
                    .font(.callout.weight(.medium))
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail).")
    }

    // MARK: - What it inspects

    private var categories: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: 8)],
            spacing: 8
        ) {
            ForEach(ItemCategory.allCases, id: \.rawValue) { category in
                Label(category.title, systemImage: category.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: Capsule())
            }
        }
        .frame(maxWidth: 560)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Inspects memory, processes, startup items, services, disk, caches and leftovers."
        )
    }

    // MARK: - Access

    @ViewBuilder
    private var accessRow: some View {
        if includesProtectedFolders {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .accessibilityHidden(true)

                Text("Desktop, Documents and Downloads are included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .accessibilityHidden(true)

                Text("Desktop, Documents and Downloads are skipped without Full Disk Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Grant Access…", action: onGrantAccess)
                    .buttonStyle(.link)
                    .font(.caption)
                    .fixedSize()
            }
        }
    }
}
