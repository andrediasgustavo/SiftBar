import SwiftUI

/// One-time, optional onboarding for the only macOS permission SiftBar needs
/// beyond folder-by-folder prompts. It is intentionally not a permanent
/// banner: the user can keep using the app with a partial disk map.
struct AccessOnboardingView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Complete your disk picture")
                        .font(.title2.weight(.semibold))

                    Text("SiftBar already shows caches, leftovers, memory and startup items. To include Desktop, Documents and Downloads in the Disk map, macOS needs one more permission.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                bullet(
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    title: "Works now",
                    detail: "Caches, leftovers, memory, startup items, Applications and Library data."
                )
                bullet(
                    symbol: "exclamationmark.circle",
                    tint: .orange,
                    title: "Missing now",
                    detail: "Sizes and large files in Desktop, Documents and Downloads."
                )
            }

            Divider()

            Text("macOS protects each of those folders separately. Full Disk Access is a single macOS permission that covers all three. SiftBar only uses it for the disk scan.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = state.accessHint {
                Label(hint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Not now") {
                    state.skipAccess()
                }
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 8)

                if state.accessHint != nil {
                    Button("Check again") {
                        state.checkAccessAgain()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Open Full Disk Access") {
                    state.openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("You can continue without it. The Disk tab will show that the map is partial, and you can change this later.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Menu("Other ways to grant access") {
                    Button("Use folder prompts instead") {
                        state.useFolderPrompts()
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(22)
        .frame(width: 640)
        .interactiveDismissDisabled(true)
    }

    private func bullet(
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.callout.weight(.medium))
                .frame(width: 86, alignment: .leading)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
