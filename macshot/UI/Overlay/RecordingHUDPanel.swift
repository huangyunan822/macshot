import Cocoa

/// Floating red pill showing elapsed recording time.
/// Uses its own NSPanel so it floats above the overlay independently.
class RecordingHUDPanel: NSPanel {

    private let timeLabel = NSTextField(labelWithString: "● 00:00")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 2
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 14
        contentView = container

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isEditable = false
        timeLabel.alignment = .center
        container.addSubview(timeLabel)
    }

    func update(elapsedSeconds: Int) {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        timeLabel.stringValue = "● \(String(format: "%02d:%02d", mins, secs))"
        timeLabel.sizeToFit()

        let pillW = timeLabel.frame.width + 24
        let pillH: CGFloat = 28
        timeLabel.frame.origin = NSPoint(x: 12, y: (pillH - timeLabel.frame.height) / 2)
        contentView?.frame.size = NSSize(width: pillW, height: pillH)

        // Resize window to fit
        var f = frame
        f.size = NSSize(width: pillW, height: pillH)
        setFrame(f, display: true)
    }

    func position(relativeTo selectionRect: NSRect, in overlayWindow: NSWindow) {
        let selScreen = overlayWindow.convertToScreen(selectionRect)
        let pillW = frame.width
        let pillH = frame.height

        var pillX = selScreen.maxX - pillW - 8
        var pillY = selScreen.maxY + 8

        if let screen = overlayWindow.screen {
            pillX = max(screen.visibleFrame.minX + 4, min(pillX, screen.visibleFrame.maxX - pillW - 4))
            pillY = min(pillY, screen.visibleFrame.maxY - pillH - 4)
        }

        setFrameOrigin(NSPoint(x: pillX, y: pillY))
    }
}
