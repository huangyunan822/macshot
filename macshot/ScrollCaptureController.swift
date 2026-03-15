import Cocoa
import ScreenCaptureKit
import Vision

// MARK: - ScrollCaptureController

/// Manages a scroll-capture session: captures strips whenever scroll activity is detected,
/// stitches them together using SAD template matching to find the exact pixel overlap.
@MainActor
final class ScrollCaptureController {

    // MARK: - Public state

    private(set) var stripCount: Int = 0
    private(set) var stitchedImage: CGImage?
    private(set) var stitchedPixelSize: CGSize = .zero
    private(set) var isActive: Bool = false

    // MARK: - Callbacks

    var onStripAdded:  ((Int) -> Void)?
    var onSessionDone: ((NSImage?) -> Void)?

    // MARK: - Config

    var excludedWindowIDs: [CGWindowID] = []

    // MARK: - Private

    private let captureRect: NSRect
    private let screen: NSScreen

    private var scDisplay: SCDisplay?
    private var excludedSCWindows: [SCWindow] = []
    private var scSourceRect: CGRect = .zero

    // Scroll monitors
    private var scrollMonitorGlobal: Any?
    private var scrollMonitorLocal:  Any?

    // Throttle: capture at most once every `captureInterval` seconds while scrolling
    private let captureInterval: TimeInterval = 0.25
    private var lastCaptureTime: TimeInterval = 0
    private var pendingCaptureTask: Task<Void, Never>? = nil
    // End-of-scroll: capture one final frame after scroll momentum dies
    private var settlementTimer: Timer?
    private let settlementInterval: TimeInterval = 0.40
    // Guard: only one captureAndStitch at a time
    private var isCapturing: Bool = false

    // Stitching state — all in points (not pixels), Vision works in normalised/point space
    private var previousStrip: NSImage?       // last captured strip (for registration)
    private var runningStitched: NSImage?     // growing stitched canvas in points

    // MARK: - Init

    init(captureRect: NSRect, screen: NSScreen) {
        self.captureRect = captureRect
        self.screen      = screen
    }

    // MARK: - Session

    func startSession() async {
        guard !isActive else { return }

        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) {
            scDisplay = content.displays.first(where: { d in
                abs(d.frame.origin.x - screen.frame.origin.x) < 2 &&
                abs(d.frame.origin.y - (NSScreen.screens.map(\.frame.maxY).max() ?? 0) - screen.frame.origin.y) < 50
            }) ?? content.displays.first
            excludedSCWindows = content.windows.filter { excludedWindowIDs.contains(CGWindowID($0.windowID)) }
        }
        guard scDisplay != nil else { onSessionDone?(nil); return }

        // AppKit → SCKit coordinate conversion (bottom-left → top-left origin)
        let df = screen.frame
        scSourceRect = CGRect(
            x: captureRect.minX - df.minX,
            y: (df.maxY - captureRect.maxY) - df.minY,
            width:  captureRect.width,
            height: captureRect.height
        )

        guard let firstCG = await captureStrip() else { onSessionDone?(nil); return }
        let scale = screen.backingScaleFactor
        let firstImg = NSImage(cgImage: firstCG,
                               size: CGSize(width:  CGFloat(firstCG.width)  / scale,
                                            height: CGFloat(firstCG.height) / scale))
        isActive        = true
        previousStrip   = firstImg
        runningStitched = firstImg
        stitchedImage   = firstCG
        stitchedPixelSize = CGSize(width: CGFloat(firstCG.width), height: CGFloat(firstCG.height))
        stripCount      = 1
        onStripAdded?(stripCount)

        // Monitor both global (events to other apps) and local (events falling through overlay)
        scrollMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.onScrollEvent()
        }
        scrollMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onScrollEvent()
            return event
        }
    }

    func stopSession() {
        isActive = false
        settlementTimer?.invalidate(); settlementTimer = nil
        pendingCaptureTask?.cancel(); pendingCaptureTask = nil
        if let m = scrollMonitorGlobal { NSEvent.removeMonitor(m); scrollMonitorGlobal = nil }
        if let m = scrollMonitorLocal  { NSEvent.removeMonitor(m); scrollMonitorLocal  = nil }
        deliverResult()
    }

    // MARK: - Scroll handling

    private func onScrollEvent() {
        guard isActive else { return }

        // Reset settlement timer on every scroll event
        settlementTimer?.invalidate()
        settlementTimer = Timer.scheduledTimer(withTimeInterval: settlementInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in await self.captureAndStitch() }
        }

        // Throttle: don't capture more often than captureInterval
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= captureInterval else { return }
        lastCaptureTime = now

        pendingCaptureTask?.cancel()
        pendingCaptureTask = Task { [weak self] in
            await self?.captureAndStitch()
        }
    }

    private func captureAndStitch() async {
        guard isActive, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard let cgStrip = await captureStrip() else { return }
        let scale = screen.backingScaleFactor
        let newStrip = NSImage(cgImage: cgStrip,
                               size: CGSize(width:  CGFloat(cgStrip.width)  / scale,
                                            height: CGFloat(cgStrip.height) / scale))

        guard let prev = previousStrip else { return }

        guard let offset = verticalOffset(from: newStrip, to: prev) else {
            // Can't register — skip
            previousStrip = newStrip
            return
        }

        if offset > 0 {
            // Downward scroll: new content at the bottom
            guard let composed = compositeBelow(base: runningStitched ?? prev,
                                                new: newStrip,
                                                offset: offset) else { return }
            runningStitched = composed
            stitchedImage   = composed.cgImage(forProposedRect: nil, context: nil, hints: nil)
            stitchedPixelSize = CGSize(width: composed.size.width  * scale,
                                       height: composed.size.height * scale)
            previousStrip = newStrip
            stripCount   += 1
            onStripAdded?(stripCount)
        } else if offset < 0 {
            // Upward scroll: trim bottom of canvas
            let crop = abs(offset)
            if let trimmed = cropBottom(of: runningStitched ?? prev, by: crop) {
                runningStitched = trimmed
                stitchedImage   = trimmed.cgImage(forProposedRect: nil, context: nil, hints: nil)
                stitchedPixelSize = CGSize(width: trimmed.size.width  * scale,
                                           height: trimmed.size.height * scale)
            }
            previousStrip = newStrip
        }
        // offset == 0 → no movement, skip
    }

    // MARK: - Strip capture

    private func captureStrip() async -> CGImage? {
        guard let display = scDisplay else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: excludedSCWindows)
        let config = SCStreamConfiguration()
        config.sourceRect        = scSourceRect
        config.width             = Int(captureRect.width  * screen.backingScaleFactor)
        config.height            = Int(captureRect.height * screen.backingScaleFactor)
        config.showsCursor       = false
        config.captureResolution = .best
        guard let raw = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                     configuration: config) else { return nil }
        return copyToCPUBacked(raw) ?? raw
    }

    // MARK: - Vision-based offset detection

    /// Returns the vertical translation (in points) needed to align `current` onto `reference`.
    /// Positive = current is below reference (downward scroll).
    /// Negative = current is above reference (upward scroll).
    /// nil = registration failed.
    private func verticalOffset(from current: NSImage, to reference: NSImage) -> CGFloat? {
        guard let curCG = current.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let refCG = reference.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: refCG)
        let handler = VNImageRequestHandler(cgImage: curCG, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first as? VNImageTranslationAlignmentObservation else { return nil }

        let ty = obs.alignmentTransform.ty
        // Convert Vision pixel offset → AppKit points
        guard current.size.height > 0 else { return nil }
        let pixelScale = CGFloat(curCG.height) / current.size.height
        return ty / (pixelScale > 0 ? pixelScale : 1)
    }

    // MARK: - Stitching helpers

    /// Composite `new` below `base`, overlapping by (new.height - offset) points.
    private func compositeBelow(base: NSImage, new: NSImage, offset: CGFloat) -> NSImage? {
        let totalH = base.size.height + offset
        let size   = NSSize(width: base.size.width, height: totalH)
        let result = NSImage(size: size)
        result.lockFocus()
        // base sits at the top
        base.draw(in: CGRect(x: 0, y: totalH - base.size.height,
                             width: base.size.width, height: base.size.height))
        // new sits at the bottom (overlaps with the bottom of base by new.height - offset)
        new.draw(in: CGRect(x: 0, y: 0, width: new.size.width, height: new.size.height))
        result.unlockFocus()
        return result
    }

    /// Remove `amount` points from the bottom of `image` (undo an upward scroll).
    private func cropBottom(of image: NSImage, by amount: CGFloat) -> NSImage? {
        let newH = image.size.height - amount
        guard newH > 0 else { return image }
        let size   = NSSize(width: image.size.width, height: newH)
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in:   NSRect(origin: .zero, size: size),
                   from: NSRect(x: 0, y: amount, width: image.size.width, height: newH),
                   operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }

    private func copyToCPUBacked(_ src: CGImage) -> CGImage? {
        let w = src.width, h = src.height
        let cs         = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: bitmapInfo) else { return nil }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Deliver result

    private func deliverResult() {
        guard let img = runningStitched else { onSessionDone?(nil); return }
        onSessionDone?(img)
    }
}
