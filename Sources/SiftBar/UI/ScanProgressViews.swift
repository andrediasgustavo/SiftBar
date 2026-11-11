import SwiftUI

// MARK: - A: full scan workspace (no previous report)

struct ScanWorkspaceView: View {
    let progress: ScanProgress?
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ring

            VStack(spacing: 5) {
                Text("Analyzing your Mac")
                    .font(.title2.weight(.semibold))

                Text(progress?.message ?? "Starting…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            bar
                .frame(width: 460)

            elapsedLine

            stepList
                .frame(width: 460)

            skeletonRows

            Button("Stop", action: onStop)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .help("Stop the analysis and keep your Mac unchanged")
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analyzing your Mac")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 5)

            Circle()
                .trim(from: 0, to: max(0.02, progress?.fraction ?? 0.02))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress?.fraction ?? 0)

            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * (progress?.fraction ?? 0.02)))
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress?.fraction ?? 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(Int((progress?.fraction ?? 0) * 100)) percent")
    }

    private var elapsedLine: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let started = progress?.startedAt ?? context.date
            let elapsed = max(0, context.date.timeIntervalSince(started))

            HStack(spacing: 7) {
                Text("Step \(progress?.step ?? 1) of 4")
                separator
                Text(String(format: "%.1fs elapsed", elapsed))
                separator
                Text("Usually 10–15s")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var separator: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(1...4, id: \.self) { step in
                stepRow(step)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func stepRow(_ step: Int) -> some View {
        let isDone = progress?.doneSteps.contains(step) ?? false
        let isCurrent = !isDone && (progress?.step ?? 1) == step

        return HStack(alignment: .top, spacing: 9) {
            statusIcon(done: isDone, current: isCurrent)

            VStack(alignment: .leading, spacing: 1) {
                Text(ScanProgress.title(for: step))
                    .font(.callout)
                    .foregroundStyle(isDone || isCurrent ? Color.primary : Color.secondary)

                if isCurrent {
                    Text(currentDetail(for: step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(step: step, done: isDone, current: isCurrent))
    }

    @ViewBuilder
    private func statusIcon(done: Bool, current: Bool) -> some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemGreen))
        } else if current {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.6)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)
        } else {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.2)
                .frame(width: 12, height: 12)
                .padding(.leading, 0.5)
        }
    }

    private func currentDetail(for step: Int) -> String {
        switch step {
        case 1: return "reading system state"
        case 2: return "apps, helpers and launch items"
        case 3: return "app caches and app data"
        default: return "measuring folders with du"
        }
    }

    private func accessibilityLabel(step: Int, done: Bool, current: Bool) -> String {
        let state = done ? "completed" : (current ? "in progress" : "waiting")
        return "\(ScanProgress.title(for: step)), \(state)"
    }

    private var skeletonRows: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: CGFloat(220 - index * 30), height: 9)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: CGFloat(380 - index * 40), height: 7)
                    }

                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 54, height: 8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
        }
        .frame(width: 560)
        .opacity(0.9)
        .accessibilityHidden(true)
    }
}

// MARK: - Slim line for the background map refresh

struct ScanProgressLine: View {
    let progress: ScanProgress?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * (progress?.fraction ?? 0.02)))
            }
        }
        .frame(height: 2)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress?.fraction ?? 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Refreshing the disk map")
        .accessibilityValue("\(Int((progress?.fraction ?? 0) * 100)) percent")
    }
}

// MARK: - B: banner over existing results

struct ScanProgressBanner: View {
    let progress: ScanProgress?
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ring

                VStack(alignment: .leading, spacing: 1) {
                    Text("Analyzing your Mac")
                        .font(.callout.weight(.semibold))

                    Text("Step \(progress?.step ?? 1) of 4 · \(progress?.message ?? "Starting…")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let started = progress?.startedAt ?? context.date
                    let elapsed = max(0, context.date.timeIntervalSince(started))

                    Text(String(format: "%.1fs", elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button("Stop", action: onStop)
                    .buttonStyle(.link)
                    .font(.callout)
                    .keyboardShortcut(.cancelAction)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geometry.size.width * (progress?.fraction ?? 0.02)))
                }
            }
            .frame(height: 4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress?.fraction ?? 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analyzing your Mac, step \(progress?.step ?? 1) of 4")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1.8)

            Circle()
                .trim(from: 0, to: max(0.02, progress?.fraction ?? 0.02))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
