import Cocoa

extension OverlayView {

    func drawMouseHighlights() {
        let now = Date()

        for entry in mouseHighlightPoints {
            let age = now.timeIntervalSince(entry.time)
            guard age <= 0.3 else { continue }
            let alpha = max(0, 1.0 - age / 0.3)
            let radius: CGFloat = 18 + CGFloat(age) * 60
            let rect = NSRect(
                x: entry.point.x - radius, y: entry.point.y - radius, width: radius * 2,
                height: radius * 2)
            NSColor.systemYellow.withAlphaComponent(0.35 * alpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.systemYellow.withAlphaComponent(0.6 * alpha).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            ring.lineWidth = 2
            ring.stroke()
        }

        if !mouseHighlightPoints.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.mouseHighlightPoints.removeAll { now.timeIntervalSince($0.time) > 0.3 }
                self.needsDisplay = true
                self.displayIfNeeded()
            }
        }
    }

    func startMouseHighlightMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            guard let self = self else { return }
            guard let window = self.window else { return }
            let windowPoint = window.convertPoint(fromScreen: event.locationInWindow)
            let viewPoint = self.convert(windowPoint, from: nil)
            DispatchQueue.main.async {
                self.mouseHighlightPoints.append((point: viewPoint, time: Date()))
                self.needsDisplay = true
                self.displayIfNeeded()
            }
        }
    }

    func stopMouseHighlightMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        mouseHighlightPoints.removeAll()
    }
}
