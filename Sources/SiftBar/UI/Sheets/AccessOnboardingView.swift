import SwiftUI

/// Optional access flow for adding Desktop, Documents and Downloads to the
/// read-only disk map. Each step has one primary action; access is checked by
/// the relaunched process rather than by a separate button that cannot pick up
/// a new TCC grant in the current process.
struct AccessOnboardingView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if state.hasOpenedAccessSettings {
                waitingContent
            } else {
                introduction
            }

            if let hint = state.accessHint {
                Label(hint, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("access.feedback")
            }

            Label(
                state.accessStatusText,
                systemImage: state.includesProtectedFolders
                    ? "checkmark.circle.fill"
                    : "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("access.status")

            Divider()

            if state.hasOpenedAccessSettings {
                waitingActions
            } else {
                introductionActions
            }

            folderPromptsAlternative
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.hasOpenedAccessSettings ? "gear" : "internaldrive.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    Color.accentColor.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.hasOpenedAccessSettings ? "Finish Full Disk Access" : "Include Personal Folders")
                    .font(.title2.weight(.semibold))

                Text(state.hasOpenedAccessSettings
                     ? "Complete the permission in System Settings, then return here. SiftBar will reopen and check it for you."
                     : "Add Desktop, Documents and Downloads to SiftBar’s read-only disk map. Analysis never moves or deletes your files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            accessRow(
                symbol: "checkmark.circle.fill",
                tint: Color(nsColor: .systemGreen),
                title: "Already included",
                detail: "Caches, Applications, Library data, memory and startup items."
            )
            accessRow(
                symbol: "plus.circle",
                tint: Color.accentColor,
                title: "Add with access",
                detail: "Folder sizes and large files in Desktop, Documents and Downloads."
            )

            Text("Full Disk Access is managed by macOS. SiftBar cannot enable it for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var waitingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            instruction(
                number: 1,
                title: "Add SiftBar",
                detail: "In Full Disk Access, click + and choose SiftBar in Applications."
            )
            instruction(
                number: 2,
                title: "Turn SiftBar on",
                detail: "Enable the switch next to SiftBar, then return to this window."
            )
            instruction(
                number: 3,
                title: "Restart and check",
                detail: "Use the button below. The app reopens and verifies access automatically."
            )

            Button("Open Full Disk Settings Again…") {
                state.openFullDiskAccessSettings()
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("access.open-settings-again")
        }
    }

    private var introductionActions: some View {
        HStack(spacing: 12) {
            Button("Not Now") {
                state.skipAccess()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("access.not-now")

            Spacer()

            Button("Open Full Disk Settings…") {
                state.openFullDiskAccessSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("access.open-settings")
        }
    }

    private var waitingActions: some View {
        HStack(spacing: 12) {
            Button("Not Now") {
                state.skipAccess()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(state.isRestarting)
            .accessibilityIdentifier("access.not-now")

            Spacer()

            Button {
                state.restartAndCheckAccess()
            } label: {
                HStack(spacing: 7) {
                    if state.isRestarting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(state.isRestarting ? "Reopening…" : "Restart & Check Access")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(state.isRestarting)
            .accessibilityIdentifier("access.restart")
        }
    }

    private var folderPromptsAlternative: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Prefer not to grant Full Disk Access?")
                .foregroundStyle(.secondary)

            Button("Choose Folders Instead…") {
                state.useFolderPrompts()
            }
            .buttonStyle(.link)
            .disabled(state.isRestarting)
            .help("macOS asks once per folder. You do not need to add SiftBar to the Full Disk Access list.")
            .accessibilityIdentifier("access.folder-prompts")
        }
        .font(.caption)
    }

    private func accessRow(
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func instruction(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
