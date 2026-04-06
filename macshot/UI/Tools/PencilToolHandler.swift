import Cocoa

/// Handles pencil (freeform draw) tool interaction.
/// Accumulates points on drag, applies Chaikin smoothing on finish.
final class PencilToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .pencil

    /// Shift-constrain direction for freeform drawing. 0 = undecided, 1 = horizontal, 2 = vertical.
    private var freeformShiftDirection: Int = 0
    /// Moving average window for live smoothing (Refined mode).
    private var rawPointBuffer: [NSPoint] = []
    private let smoothWindowSize: Int = 8

    var cursor: NSCursor? { nil }  // dot preview replaces system cursor

    // MARK: - AnnotationToolHandler

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        freeformShiftDirection = 0
        rawPointBuffer = [point]
        let annotation = Annotation(
            tool: .pencil,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .pencil),
            strokeWidth: canvas.currentStrokeWidth
        )
        annotation.points = [point]
        annotation.lineStyle = canvas.currentLineStyle
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        var clampedPoint = point

        if shiftHeld {
            let refPoint = annotation.points?.last ?? annotation.startPoint
            let dx = clampedPoint.x - refPoint.x
            let dy = clampedPoint.y - refPoint.y

            if freeformShiftDirection == 0 && hypot(dx, dy) > 5 {
                freeformShiftDirection = abs(dx) >= abs(dy) ? 1 : 2
            }
            if freeformShiftDirection == 1 {
                clampedPoint = NSPoint(x: clampedPoint.x, y: annotation.startPoint.y)
            } else if freeformShiftDirection == 2 {
                clampedPoint = NSPoint(x: annotation.startPoint.x, y: clampedPoint.y)
            } else {
                clampedPoint = annotation.startPoint
            }
        }

        // Refined mode: moving average of the last N raw points. Smooths jitter
        // while preserving the shape of curves and circles (unlike EMA which
        // pulls inward on circular paths).
        if canvas.pencilSmoothMode == 2 {
            rawPointBuffer.append(clampedPoint)
            if rawPointBuffer.count > smoothWindowSize {
                rawPointBuffer.removeFirst()
            }
            var avgX: CGFloat = 0, avgY: CGFloat = 0
            for p in rawPointBuffer { avgX += p.x; avgY += p.y }
            let n = CGFloat(rawPointBuffer.count)
            clampedPoint = NSPoint(x: avgX / n, y: avgY / n)
        }

        // No snap guides for freeform tools
        canvas.snapGuideX = nil
        canvas.snapGuideY = nil

        annotation.endPoint = clampedPoint
        annotation.points?.append(clampedPoint)
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }

        // In Refined mode, append the last raw cursor position so the stroke
        // endpoint lands where the user actually stopped.
        if canvas.pencilSmoothMode == 2, let lastRaw = rawPointBuffer.last {
            annotation.points?.append(lastRaw)
            annotation.endPoint = lastRaw
        }

        guard let points = annotation.points, !points.isEmpty else {
            canvas.activeAnnotation = nil
            return
        }

        // Single click: offset points slightly so the round line cap renders a visible dot
        if points.count < 3, let p = points.first {
            annotation.points = [p, NSPoint(x: p.x + 0.5, y: p.y), NSPoint(x: p.x + 0.5, y: p.y)]
        } else if canvas.pencilSmoothMode >= 1 {
            // Mode 1 (Smooth): Chaikin on finish
            // Mode 2 (Extra): already live-smoothed via EMA, apply Chaikin as final polish
            annotation.points = Self.chaikinSmooth(points, iterations: 2)
        }

        // Update drawing cursor position so dot doesn't jump back to pre-drag location
        if let lastPt = annotation.points?.last {
            canvas.drawingCursorPoint = lastPt
        }
        commitAnnotation(annotation, canvas: canvas)
        freeformShiftDirection = 0
        rawPointBuffer.removeAll()
    }

    // MARK: - Smoothing

    /// Chaikin corner-cutting: each iteration replaces every segment with two points
    /// at 25% and 75% along it, keeping endpoints fixed. 2 passes gives gentle smoothing.
    static func chaikinSmooth(_ pts: [NSPoint], iterations: Int) -> [NSPoint] {
        guard pts.count > 2 else { return pts }
        var result = pts
        for _ in 0..<iterations {
            var next: [NSPoint] = [result[0]]
            for i in 0..<result.count - 1 {
                let p0 = result[i]
                let p1 = result[i + 1]
                next.append(NSPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y))
                next.append(NSPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y))
            }
            next.append(result[result.count - 1])
            result = next
        }
        return result
    }
}
