import AppKit
import SwiftUI
import Vision
@testable import SiftBar

// MARK: - Snapshot + OCR model

/// One OCR line. `box` is normalized, origin bottom-left (Vision convention).
struct OCRLine {
    let text: String
    let box: CGRect
}

struct OCRResult {
    let lines: [OCRLine]

    func contains(_ needle: String) -> Bool {
        lines.contains { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    func exact(_ text: String) -> Bool {
        lines.contains { $0.text.trimmingCharacters(in: .whitespaces) == text }
    }

    func count(exact text: String) -> Int {
        lines.filter { $0.text.trimmingCharacters(in: .whitespaces) == text }.count
    }

    func first(containing needle: String) -> OCRLine? {
        lines.first { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    var allText: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

// MARK: - Runner

final class Checker {
    private(set) var failures: [String] = []

    func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append(message)
        }
    }

    func expectContains(_ result: OCRResult, _ needle: String) {
        expect(result.contains(needle), "missing text: \(needle)")
    }

    func expectAbsent(_ result: OCRResult, _ needle: String) {
        expect(!result.contains(needle), "unexpected text: \(needle)")
    }
}

// MARK: - Hosting

@MainActor
func pump(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

@MainActor
func host<V: View>(_ view: V, size: CGSize, settle: TimeInterval = 1.2) -> NSWindow {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.wantsLayer = true

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    window.title = "SiftBar UI smoke"
    window.setFrameOrigin(NSPoint(x: 40, y: 40))
    window.orderFrontRegardless()

    pump(settle)
    hosting.layoutSubtreeIfNeeded()
    pump(0.2)
    return window
}

@MainActor
func snapshot(of view: NSView, scale: CGFloat = 2) -> CGImage? {
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * scale),
        pixelsHigh: Int(bounds.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = bounds.size

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // AppKit's display cache produces a correctly oriented bitmap for
    // layer-backed SwiftUI hosting views. `CALayer.render(in:)` is kept as a
    // fallback for views that have not drawn yet.
    view.cacheDisplay(in: bounds, to: rep)

    if isBlank(rep), let layer = view.layer {
        context.cgContext.scaleBy(x: scale, y: scale)
        layer.render(in: context.cgContext)
    }

    NSGraphicsContext.restoreGraphicsState()

    return rep.cgImage
}

func isBlank(_ rep: NSBitmapImageRep) -> Bool {
    guard let data = rep.bitmapData, rep.bytesPerRow > 0 else { return true }

    let step = max(1, rep.bytesPerRow * rep.pixelsHigh / 20_000)
    var minValue = UInt8.max
    var maxValue: UInt8 = 0
    var index = 0

    while index + 2 < rep.bytesPerRow * rep.pixelsHigh {
        let value = data[index]
        minValue = min(minValue, value)
        maxValue = max(maxValue, value)
        index += step
    }

    return Int(maxValue) - Int(minValue) < 4
}

func recognize(_ image: CGImage) -> OCRResult {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    do {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
        return OCRResult(lines: [])
    }

    let lines: [OCRLine] = (request.results ?? []).compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return OCRLine(text: candidate.string, box: observation.boundingBox)
    }

    return OCRResult(lines: lines)
}

@MainActor
func capture(_ window: NSWindow, settle: TimeInterval = 0.6) -> OCRResult {
    pump(settle)

    guard let view = window.contentView else {
        return OCRResult(lines: [])
    }

    window.displayIfNeeded()
    view.displayIfNeeded()
    pump(0.2)

    guard let image = snapshot(of: view) else {
        return OCRResult(lines: [])
    }

    if ProcessInfo.processInfo.environment["SIFTBAR_UI_SAVE"] == "1" {
        savePNG(image, name: ProcessInfo.processInfo.environment["SIFTBAR_UI_NAME"] ?? "snapshot")
    }

    return recognize(image)
}

func savePNG(_ image: CGImage, name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    let directory = ProcessInfo.processInfo.environment["SIFTBAR_UI_DIR"] ?? NSTemporaryDirectory()
    let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")

    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
        print("saved snapshot: \(url.path)")
    }
}

// MARK: - Fixtures

func demoItem(category: ItemCategory, titleContains: String) -> ScanItem? {
    DemoReport.make().items.first { $0.category == category && $0.title.contains(titleContains) }
}

// MARK: - Scenarios

@MainActor
func scenarioFirstRun(_ check: Checker) {
    let state = AppState(refreshAccess: false)
    let window = host(DashboardView().environmentObject(state), size: CGSize(width: 1000, height: 752))
    defer { window.orderOut(nil) }

    let ocr = capture(window)
    guard !ocr.lines.isEmpty else {
        check.expect(false, "first-run: OCR returned no text")
        return
    }

    check.expectContains(ocr, "Welcome to SiftBar")
    check.expectContains(ocr, "Run First Analysis")
    check.expectContains(ocr, "Read-only")
    check.expectContains(ocr, "History")
    check.expect(
        !hasHeaderAnalyze(ocr),
        "first-run: header Analyze button must be hidden while no report exists"
    )
}

@MainActor
func scenarioFirstRunAccess(_ check: Checker) {
    let granted = host(
        FirstRunView(
            includesProtectedFolders: true,
            isBusy: false,
            onAnalyze: {},
            onGrantAccess: {}
        ),
        size: CGSize(width: 900, height: 620)
    )
    defer { granted.orderOut(nil) }

    let grantedOCR = capture(granted)
    check.expectContains(grantedOCR, "Run First Analysis")
    check.expectContains(grantedOCR, "are included")
    check.expectAbsent(grantedOCR, "Grant Access")

    let denied = host(
        FirstRunView(
            includesProtectedFolders: false,
            isBusy: false,
            onAnalyze: {},
            onGrantAccess: {}
        ),
        size: CGSize(width: 900, height: 620)
    )
    defer { denied.orderOut(nil) }

    let deniedOCR = capture(denied)
    check.expectContains(deniedOCR, "skipped without Full Disk Access")
    check.expectContains(deniedOCR, "Grant Access")
}

@MainActor
func scenarioMenu(_ check: Checker) {
    let ready = AppState(refreshAccess: false)
    let readyWindow = host(
        MenuContentView().environmentObject(ready),
        size: CGSize(width: 340, height: 260)
    )
    defer { readyWindow.orderOut(nil) }

    let readyOCR = capture(readyWindow)
    check.expectContains(readyOCR, "Ready to analyze")
    check.expectContains(readyOCR, "Open Dashboard")
    check.expectContains(readyOCR, "Run Analysis")
    check.expectContains(readyOCR, "Quit SiftBar")

    let report = AppState(refreshAccess: false)
    report.loadDemoReport()
    let reportWindow = host(
        MenuContentView().environmentObject(report),
        size: CGSize(width: 340, height: 260)
    )
    defer { reportWindow.orderOut(nil) }

    let reportOCR = capture(reportWindow)
    check.expectContains(reportOCR, "need review")
    check.expectContains(reportOCR, "findings")
}

@MainActor
func scenarioOverview(_ check: Checker) {
    let state = AppState(refreshAccess: false)
    state.loadDemoReport()

    let window = host(
        DashboardView().environmentObject(state),
        size: CGSize(width: 1000, height: 752)
    )
    defer { window.orderOut(nil) }

    let ocr = capture(window)
    guard !ocr.lines.isEmpty else {
        check.expect(false, "overview: OCR returned no text")
        return
    }

    check.expectContains(ocr, "Overview")
    check.expectContains(ocr, "Found 24 items")
    check.expectContains(ocr, "Need review")
    check.expectContains(ocr, "Disk available")
    check.expect(
        hasHeaderAnalyze(ocr),
        "overview: header Analyze button should be visible after a scan"
    )
    check.expectAbsent(ocr, "Run First Analysis")
    check.expectAbsent(ocr, "No scan yet")
}

/// The header sits in the top band of the window (Vision uses bottom-left
/// origin, so the header is above 0.85). The first-run step card also contains
/// the word "Analyze", so position matters, not just the text. The button's
/// magnifier glyph can be OCR'd as a leading bullet, hence the substring check.
func hasHeaderAnalyze(_ ocr: OCRResult) -> Bool {
    ocr.lines.contains { line in
        line.box.maxY > 0.85
            && line.text.localizedCaseInsensitiveContains("Analyze")
            && !line.text.localizedCaseInsensitiveContains("Run First")
    }
}

@MainActor
func scenarioItemRow(_ check: Checker) {
    guard let item = demoItem(category: .caches, titleContains: "Design Helper") else {
        check.expect(false, "item-row: demo item not found")
        return
    }

    let window = host(
        ItemRow(
            item: item,
            isSelected: false,
            canSelect: item.canBeChanged,
            showsCategory: false,
            isChild: false,
            hasChildren: false,
            isExpanded: false,
            onToggleExpanded: {},
            onToggle: {},
            quickActionTitle: nil,
            onQuickAction: nil,
            controlsDisabled: false
        )
        .padding(12)
        .frame(width: 880),
        size: CGSize(width: 920, height: 140)
    )
    defer { window.orderOut(nil) }

    let ocr = capture(window)
    guard !ocr.lines.isEmpty else {
        check.expect(false, "item-row: OCR returned no text")
        return
    }

    check.expectContains(ocr, "Design Helper cache")
    check.expectContains(ocr, "Caution")

    // The impact value (title line) and the risk word (evidence line) must
    // share the same right edge. This is the regression fixed in c141ec3.
    guard let impact = ocr.first(containing: "GB"),
          let risk = ocr.first(containing: "Caution") else {
        check.expect(false, "item-row: impact value or risk label not recognized")
        return
    }

    let delta = abs(impact.box.maxX - risk.box.maxX)
    check.expect(
        delta < 0.02,
        String(format: "item-row: risk label is not right-aligned (delta %.3f)", delta)
    )
}

// MARK: - Main

@MainActor
func runScenario(_ name: String) -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let check = Checker()

    switch name {
    case "first-run": scenarioFirstRun(check)
    case "first-run-access": scenarioFirstRunAccess(check)
    case "menu": scenarioMenu(check)
    case "overview": scenarioOverview(check)
    case "item-row": scenarioItemRow(check)
    default:
        print("Unknown scenario: \(name)")
        return 2
    }

    if check.failures.isEmpty {
        print("PASS \(name)")
        return 0
    }

    print("FAIL \(name)")
    for failure in check.failures {
        print("  - \(failure)")
    }
    return 1
}

let scenario = CommandLine.arguments.dropFirst().first ?? "first-run"
let status = MainActor.assumeIsolated { runScenario(scenario) }
exit(status)
