//
//  ZoomCanvas.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import AppKit

final class ZoomCanvas: NSView {
    private let image: NSImage
    private var zoom: CGFloat = 1
    private var imageOrigin: NSPoint = .zero
    private var flashlightEnabled = false
    private var flashlightCenter: NSPoint?
    private var dragLocation: NSPoint?

    private let flashlightRadius: CGFloat = 100
    private let keyboardPanDistance: CGFloat = 80

    init(frame: NSRect, image: NSImage, flashlightEnabled: Bool = false) {
        self.image = image
        self.flashlightEnabled = flashlightEnabled
        super.init(frame: frame)
        if flashlightEnabled {
            NSCursor.hide()
        }
    }

    required init?(coder _: NSCoder) {
        return nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()

        guard let context = NSGraphicsContext.current else { return }
        let previousInterpolation = context.imageInterpolation
        context.imageInterpolation = .none
        defer { context.imageInterpolation = previousInterpolation }

        let imageRect = NSRect(
            x: imageOrigin.x,
            y: imageOrigin.y,
            width: bounds.width * zoom,
            height: bounds.height * zoom
        )

        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        guard flashlightEnabled else { return }

        let center = flashlightCenter ?? NSPoint(x: bounds.midX, y: bounds.midY)
        let flashlightPath = NSBezierPath(rect: bounds)
        flashlightPath.appendOval(
            in: NSRect(
                x: center.x - flashlightRadius,
                y: center.y - flashlightRadius,
                width: flashlightRadius * 2,
                height: flashlightRadius * 2
            )
        )
        flashlightPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.82).setFill()
        flashlightPath.fill()
    }

    override func scrollWheel(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        flashlightCenter = mouse
        if flashlightEnabled {
            needsDisplay = true
        }
        handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            controlPressed: event.modifierFlags.contains(.control) && !flashlightEnabled,
            at: mouse
        )
    }

    override func mouseMoved(with event: NSEvent) {
        updateFlashlightCenter(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        beginDragging(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginDragging(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        continueDragging(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        continueDragging(with: event)
    }

    override func mouseUp(with _: NSEvent) {
        endDragging()
    }

    override func rightMouseUp(with _: NSEvent) {
        endDragging()
    }

    override func keyDown(with event: NSEvent) {
        let distance = keyboardPanDistance
        let movement: NSPoint
        switch event.keyCode {
        case 13, 126:
            movement = NSPoint(x: 0, y: -distance)
        case 0, 123:
            movement = NSPoint(x: distance, y: 0)
        case 1, 125:
            movement = NSPoint(x: 0, y: distance)
        case 2, 124:
            movement = NSPoint(x: -distance, y: 0)
        default:
            super.keyDown(with: event)
            return
        }
        moveImage(by: movement)
    }

    private func updateFlashlightCenter(with event: NSEvent) {
        flashlightCenter = convert(event.locationInWindow, from: nil)
        if flashlightEnabled {
            needsDisplay = true
        }
    }

    private func setFlashlightEnabled(_ enabled: Bool) {
        guard flashlightEnabled != enabled else { return }
        flashlightEnabled = enabled

        if enabled {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
    }

    func toggleFlashlight() {
        setFlashlightEnabled(!flashlightEnabled)
        flashlightCenter = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            setFlashlightEnabled(false)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func beginDragging(with event: NSEvent) {
        updateFlashlightCenter(with: event)
        dragLocation = convert(event.locationInWindow, from: nil)
    }

    private func continueDragging(with event: NSEvent) {
        updateFlashlightCenter(with: event)
        guard let previousLocation = dragLocation else { return }

        let location = convert(event.locationInWindow, from: nil)
        moveImage(
            by: NSPoint(
                x: location.x - previousLocation.x,
                y: location.y - previousLocation.y
            )
        )
        dragLocation = location
    }

    private func endDragging() {
        dragLocation = nil
    }

    private func moveImage(by distance: NSPoint) {
        imageOrigin.x += distance.x
        imageOrigin.y += distance.y
        clampImageOrigin()
        needsDisplay = true
    }

    private func handleScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        isPrecise: Bool,
        controlPressed: Bool,
        at mouse: NSPoint
    ) {
        guard controlPressed else {
            imageOrigin.x += deltaX
            imageOrigin.y += deltaY
            clampImageOrigin()
            needsDisplay = true
            return
        }

        let sensitivity = isPrecise ? 0.015 : 0.20
        let factor = CGFloat(exp(Double(deltaY) * sensitivity))
        let newZoom = min(max(zoom * factor, 1), 8)
        guard newZoom != zoom else { return }

        let imageX = (mouse.x - imageOrigin.x) / zoom
        let imageY = (mouse.y - imageOrigin.y) / zoom

        zoom = newZoom
        imageOrigin.x = mouse.x - imageX * zoom
        imageOrigin.y = mouse.y - imageY * zoom
        clampImageOrigin()
        needsDisplay = true
    }

    private func clampImageOrigin() {
        imageOrigin.x = min(0, max(minimumImageOriginX, imageOrigin.x))
        imageOrigin.y = min(0, max(minimumImageOriginY, imageOrigin.y))
    }

    private var minimumImageOriginX: CGFloat {
        bounds.width * (1 - zoom)
    }

    private var minimumImageOriginY: CGFloat {
        bounds.height * (1 - zoom)
    }
}
