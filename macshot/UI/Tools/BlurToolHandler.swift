import Cocoa

/// Handles blur tool interaction.
/// Shift-constrains to square. Captures composited image source for baking.
final class BlurToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .blur

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let annotation = Annotation(
            tool: .blur,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .blur),
            strokeWidth: canvas.currentStrokeWidth
        )
        annotation.sourceImage = canvas.compositedImage()
        annotation.sourceImageBounds = canvas.captureDrawRect
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        var clampedPoint = point

        if shiftHeld {
            clampedPoint = snapSquare(point, from: annotation.startPoint)
            canvas.snapGuideX = nil
            canvas.snapGuideY = nil
        } else {
            clampedPoint = canvas.snapPoint(point, excluding: annotation)
        }

        annotation.endPoint = clampedPoint
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        let dx = abs(annotation.endPoint.x - annotation.startPoint.x)
        let dy = abs(annotation.endPoint.y - annotation.startPoint.y)
        guard dx > 2 || dy > 2 else {
            canvas.activeAnnotation = nil
            canvas.setNeedsDisplay()
            return
        }
        commitAnnotation(annotation, canvas: canvas)
    }
}
