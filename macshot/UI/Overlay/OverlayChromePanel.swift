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
    // Panels that host editable text fields (the resolution box) opt back in,
    // but become key only when the clicked subview explicitly needs it.
    private let keyCapable: Bool
    override var canBecomeKey: Bool {
        guard keyCapable else { return false }
        if isKeyWindow { return true }
        guard let event = NSApp.currentEvent,
              event.window === self,
              event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown
        else {
            return false
        }
        return viewRequestsPanelKey(contentView?.hitTest(event.locationInWindow))
    }
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
        becomesKeyOnlyIfNeeded = canBecomeKey
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

    private func viewRequestsPanelKey(_ view: NSView?) -> Bool {
        var current = view
        while let v = current {
            if (v as? PanelKeyRequestingView)?.requestsPanelKeyForMouseDown == true {
                return true
            }
            current = v.superview
        }
        return false
    }
}

/// Adopted by controls inside an `OverlayChromePanel` that genuinely need the
/// panel to become key for a mouse-down, such as editable text fields. Buttons
/// and background views intentionally do not opt in, keeping glass inactive.
protocol PanelKeyRequestingView: AnyObject {
    var requestsPanelKeyForMouseDown: Bool { get }
}
