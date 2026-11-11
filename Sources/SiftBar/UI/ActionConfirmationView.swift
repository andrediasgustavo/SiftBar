import SwiftUI

struct ActionConfirmationView: View {
    let items: [ScanItem]
    let isRunning: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text(item.risk.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(ActionExecutor.preview(for: item))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            if let warning = item.warning {
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)

                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            footer
        }
        .padding(20)
        .frame(width: 580)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(ActionExecutor.sheetTitle(for: items))
                    .font(.headline)

                Text("SiftBar runs the commands below. Some actions cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let note = cautionNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 8)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            // Destructive actions must not be the default button: HIG asks for
            // the primary role to stay on a non-destructive choice so Return
            // cannot move data to the Trash by accident.
            Button(actionTitle, role: .destructive, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isRunning)
        }
    }

    /// The warning should match what the batch actually does: quitting a
    /// process can lose unsaved work, but disabling a launch item does not.
    private var cautionNote: String? {
        guard items.contains(where: { $0.risk == .caution }) || items.contains(where: { $0.warning != nil }) else {
            return nil
        }

        // Warnings are already shown per item above; do not repeat them in the
        // footer. Only surface a different, batch-wide risk.
        if items.contains(where: { $0.warning != nil }) {
            return items.contains(where: {
                if case .killProcess = $0.action { return true }
                return false
            }) ? "Quitting a process may lose unsaved work." : nil
        }

        if items.contains(where: { if case .killProcess = $0.action { return true }; return false }) {
            return "Quitting a process may lose unsaved work."
        }

        if items.contains(where: { if case .disableLaunchItem = $0.action { return true }; return false }) {
            return "Disabling an item changes what starts at login."
        }

        if items.contains(where: { if case .deletePath = $0.action { return true }; return false }) {
            return "Caches are moved to the Trash and can be restored."
        }

        if items.contains(where: { if case .trashLeftover = $0.action { return true }; return false }) {
            return "Leftover app data is moved to the Trash. Empty the Trash to free the space."
        }

        return "Review caution items before applying."
    }

    private var actionTitle: String {
        guard items.count == 1, let item = items.first else {
            return ActionExecutor.confirmTitle(for: items)
        }

        return ActionExecutor.verb(for: item.action)
    }
}
