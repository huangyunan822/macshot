import Cocoa

/// Handles marker/highlighter tool interaction.
/// Accumulates freeform points on drag, semi-transparent wide stroke.
final class MarkerToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .marker

    /// Shift-constrain direction for freeform drawing. 0 = undecided, 1 = horizontal, 2 = vertical.
    private var freeformShiftDirection: Int = 0

    var cursor: NSCursor? {
        Self.penCursor
    }

    private static let penCursor: NSCursor = {
        let size: CGFloat = 20
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else {
            return NSCursor.crosshair
        }
        let tinted = NSImage(size: img.size, flipped: false) { r in
            img.draw(in: r)
            NSColor.white.setFill()
            r.fill(using: .sourceAtop)
            return true
        }
        return NSCursor(image: tinted, hotSpot: NSPoint(x: 2, y: tinted.size.height - 2))
    }()

    // MARK: - AnnotationToolHandler

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        freeformShiftDirection = 0
        let annotation = Annotation(
            tool: .marker,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .marker),
            strokeWidth: canvas.currentMarkerSize
        )
        annotation.points = [point]
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

        // No snap guides for freeform tools
        canvas.snapGuideX = nil
        canvas.snapGuideY = nil

        annotation.endPoint = clampedPoint
        annotation.points?.append(clampedPoint)
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        guard let points = annotation.points, !points.isEmpty else {
            canvas.activeAnnotation = nil
            return
        }

        // Single click: duplicate the point so drawFreeform renders a dot
        if points.count < 3, let p = points.first {
            annotation.points = [p, p, p]
        }

        // Update marker preview position so it doesn't jump back to the pre-drag location
        if let lastPt = annotation.points?.last {
            canvas.markerCursorPoint = lastPt
        }

        commitAnnotation(annotation, canvas: canvas)
        freeformShiftDirection = 0
    }
}
