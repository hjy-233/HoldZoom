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

    init(frame: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder _: NSCoder) {
        return nil
    }

    override func draw(_: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: bounds).fill()

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
    }

    override func scrollWheel(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        let sensitivity = event.hasPreciseScrollingDeltas ? 0.015 : 0.20
        let factor = CGFloat(exp(Double(event.scrollingDeltaY) * sensitivity))
        let newZoom = min(max(zoom * factor, 1), 8)
        guard newZoom != zoom else { return }

        let imageX = (mouse.x - imageOrigin.x) / zoom
        let imageY = (mouse.y - imageOrigin.y) / zoom

        zoom = newZoom
        imageOrigin.x = mouse.x - imageX * zoom
        imageOrigin.y = mouse.y - imageY * zoom

        imageOrigin.x = min(0, max(bounds.width * (1 - zoom), imageOrigin.x))
        imageOrigin.y = min(0, max(bounds.height * (1 - zoom), imageOrigin.y))

        needsDisplay = true
    }
}
