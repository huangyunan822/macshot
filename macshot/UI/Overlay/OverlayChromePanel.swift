import Cocoa

/// A transparent, borderless child panel that floats just above the capture
/// overlay window to host a Liquid Glass toolbar.
///
/// Why a separate window: `NSGlassEffectView` uses behind-window blending — it
/// can only refract content from windows BEHIND it, never content in its own
/// window. The capture overlay draws the screenshot + dim mask in its own
/// window, so a glass toolbar placed inside it has nothing to refract. Hosting
/// the toolbar in this panel — ordered above the overlay — lets its glass sample
/// the overlay window beneath as its backdrop, producing real translucency.
///
/// The panel is kept TIGHT around the toolbar (not full-screen) so it only
/// intercepts clicks on the toolbar itself, leaving the rest of the overlay
/// interactive.
final class OverlayChromePanel: NSPanel {
    // By default never become key/main: clicking a toolbar button shouldn't make
    // this panel the key window, which would put NSGlassEffectView into its
    // brightened "active" state (buttons still click via acceptsFirstMouse).
    // Panels that host editable text fields (the resolution box) opt back in so
    // the fields can take keyboard focus.
    private let keyCapable: Bool
    override var canBecomeKey: Bool { keyCapable }
    override var canBecomeMain: Bool { false }

    init(hosting content: NSView, cornerRadius: CGFloat, canBecomeKey: Bool = false) {
        self.keyCapable = canBecomeKey
        super.init(contentRect: NSRect(origin: .zero, size: content.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #available(macOS 26.0, *) { animationBehavior = .none }

        let root = NSView(frame: NSRect(origin: .zero, size: content.frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        // Host the toolbar in glass; fall back to placing it directly (shouldn't
        // happen since we only create this panel when glass is enabled).
        if let glass = LiquidGlass.host(content, frame: root.bounds, cornerRadius: cornerRadius) {
            glass.autoresizingMask = [.width, .height]
            root.addSubview(glass)
        } else {
            content.frame = root.bounds
            content.autoresizingMask = [.width, .height]
            root.addSubview(content)
        }
        contentView = root
    }

    /// Move the panel to `screenRect` and size its content to match.
    func place(at screenRect: NSRect) {
        setFrame(screenRect, display: true)
    }
}
