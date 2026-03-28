import Cocoa

/// Standalone editor view — subclass of OverlayView for the editor window.
/// When inside an NSScrollView, coordinate transforms are identity (view coords = canvas coords).
/// NSScrollView handles zoom, pan, centering, momentum — no manual math needed.
class EditorView: OverlayView {

    override var isEditorMode: Bool { true }
    override var isInsideScrollView: Bool { true }

    // MARK: - Background drawing (simple — NSScrollView handles centering/zoom)

    override func drawEditorBackground(context: NSGraphicsContext) {
        // Just draw the image. NSScrollView.backgroundColor handles the dark background.
        // CenteringClipView handles centering. Magnification handles zoom.
        if !beautifyEnabled, let image = screenshotImage {
            image.draw(in: selectionRect, from: .zero, operation: .copy, fraction: 1.0)
        }
    }

    // MARK: - Selection chrome (disabled in editor)

    override func shouldClipSelectionImage() -> Bool { false }
    override func shouldDrawSelectionBorder() -> Bool { false }
    override func shouldDrawSizeLabel() -> Bool { false }

    // MARK: - Coordinate transforms (identity — scroll view handles everything)

    override func adjustPointForEditor(_ p: NSPoint) -> NSPoint { p }
    override func applyEditorTransform(to context: NSGraphicsContext) {}

    // MARK: - Selection interaction (disabled in editor)

    override func shouldAllowSelectionResize() -> Bool { false }
    override func shouldAllowNewSelection() -> Bool { false }
    override func shouldAllowDetach() -> Bool { false }

    // MARK: - Zoom (not needed — NSScrollView handles it)

    override func canPanAtOneX() -> Bool { false }
    override func clampZoomAnchorForEditor(r: NSRect, z: CGFloat, ac: NSPoint, av: inout NSPoint) {}

    // MARK: - Export

    override var captureDrawRect: NSRect { selectionRect }

    // Top bar is handled by EditorTopBarView (real NSView in the container)
}
