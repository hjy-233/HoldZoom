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
    private var pressedKeyboardDirections: [UInt16: NSPoint] = [:]
    private var keyboardPanTimer: Timer?
    private var keyboardPanStartedAt: TimeInterval?
    private var keyboardPanLastUpdate: TimeInterval?
    private var keyboardPanVelocity: NSPoint = .zero

    private let flashlightRadius: CGFloat = 100
    private let keyboardPanInitialSpeed: CGFloat = 180
    private let keyboardPanMaximumSpeed: CGFloat = 2200
    private let keyboardPanAccelerationDuration: TimeInterval = 0.3

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
        guard let direction = keyboardDirection(for: event.keyCode) else {
            super.keyDown(with: event)
            return
        }

        if pressedKeyboardDirections.isEmpty {
            keyboardPanStartedAt = ProcessInfo.processInfo.systemUptime
        }
        pressedKeyboardDirections[event.keyCode] = direction
        startKeyboardPanTimerIfNeeded()
    }

    override func keyUp(with event: NSEvent) {
        guard keyboardDirection(for: event.keyCode) != nil else {
            super.keyUp(with: event)
            return
        }

        pressedKeyboardDirections[event.keyCode] = nil
        if pressedKeyboardDirections.isEmpty {
            keyboardPanStartedAt = nil
        }
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
            keyboardPanTimer?.invalidate()
            keyboardPanTimer = nil
            pressedKeyboardDirections.removeAll()
            keyboardPanVelocity = .zero
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

private extension ZoomCanvas {
    func keyboardDirection(for keyCode: UInt16) -> NSPoint? {
        switch keyCode {
        case 13, 126:
            NSPoint(x: 0, y: -1)
        case 0, 123:
            NSPoint(x: 1, y: 0)
        case 1, 125:
            NSPoint(x: 0, y: 1)
        case 2, 124:
            NSPoint(x: -1, y: 0)
        default:
            nil
        }
    }

    func startKeyboardPanTimerIfNeeded() {
        guard keyboardPanTimer == nil else { return }
        keyboardPanLastUpdate = ProcessInfo.processInfo.systemUptime

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateKeyboardPan()
        }
        keyboardPanTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateKeyboardPan() {
        let now = ProcessInfo.processInfo.systemUptime
        let previousUpdate = keyboardPanLastUpdate ?? now
        let deltaTime = min(now - previousUpdate, 0.05)
        keyboardPanLastUpdate = now

        let direction = pressedKeyboardDirections.values.reduce(.zero) { result, value in
            NSPoint(x: result.x + value.x, y: result.y + value.y)
        }
        let directionLength = hypot(direction.x, direction.y)
        let hasDirection = directionLength > 0
        let targetVelocity = keyboardPanTargetVelocity(
            direction: direction,
            directionLength: directionLength,
            now: now
        )
        let response = hasDirection ? 24.0 : 10.0
        let blend = 1 - exp(-response * deltaTime)
        keyboardPanVelocity.x += (targetVelocity.x - keyboardPanVelocity.x) * blend
        keyboardPanVelocity.y += (targetVelocity.y - keyboardPanVelocity.y) * blend

        if deltaTime > 0 {
            moveImage(
                by: NSPoint(
                    x: keyboardPanVelocity.x * deltaTime,
                    y: keyboardPanVelocity.y * deltaTime
                )
            )
        }

        if !hasDirection, hypot(keyboardPanVelocity.x, keyboardPanVelocity.y) < 5 {
            keyboardPanTimer?.invalidate()
            keyboardPanTimer = nil
            keyboardPanLastUpdate = nil
            keyboardPanVelocity = .zero
        }
    }

    func keyboardPanTargetVelocity(
        direction: NSPoint,
        directionLength: CGFloat,
        now: TimeInterval
    ) -> NSPoint {
        guard directionLength > 0,
              let keyboardPanStartedAt
        else { return .zero }

        let elapsed = now - keyboardPanStartedAt
        let progress = min(elapsed / keyboardPanAccelerationDuration, 1)
        let easedProgress = CGFloat(progress * progress)
        let speed = keyboardPanInitialSpeed
            + (keyboardPanMaximumSpeed - keyboardPanInitialSpeed) * easedProgress

        return NSPoint(
            x: direction.x / directionLength * speed,
            y: direction.y / directionLength * speed
        )
    }
}
