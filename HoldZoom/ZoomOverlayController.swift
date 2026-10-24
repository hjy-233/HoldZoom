//
//  ZoomOverlayController.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import AppKit

@MainActor
final class ZoomOverlayController {
    private var window: NSWindow?
    private var escapeMonitor: Any?

    func show(image: NSImage) {
        close()

        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false

        window.contentView = ZoomCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image
        )

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }

            return event
        }
    }

    func close() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }

        window?.close()
        window = nil
    }
}
