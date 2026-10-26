//
//  ZoomOverlayController.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import AppKit
import ApplicationServices

private final class ZoomOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}

private enum OverlayError: LocalizedError {
    case noScreen
    case inputTapUnavailable

    var errorDescription: String? {
        switch self {
        case .noScreen:
            String(localized: "无法找到屏幕")
        case .inputTapUnavailable:
            String(localized: "请在系统设置中允许 HoldZoom 使用辅助功能")
        }
    }
}

@MainActor
final class ZoomOverlayController {
    let settings = HoldZoomSettings.load()
    private let annotationSessionStore = AnnotationSessionStore()
    var window: NSWindow?
    private var previousApplication: NSRunningApplication?
    var overlayInputTap: OverlayInputTap?
    var annotationToolDetailsPreviousWindowLevel: NSWindow.Level?
    var localKeyboardMonitor: Any?
    var localControlMonitor: Any?
    var globalKeyboardMonitor: Any?
    var globalControlMonitor: Any?
    var controlCaptureTask: Task<Void, Never>?
    private var controlStateTimer: Timer?
    var isControlPressed = false
    var isAnnotationCapturePending = false
    private var isControlShortcutOverlay = false
    private var isShortcutFlashlightOverlay = false
    var hasPresentedCaptureError = false

    init() {
        requestAccessibilityPermission()
        requestScreenCapturePermission()
        installShortcutMonitors()
        installControlMonitors()
        startControlStatePolling()
    }

    func show(image: NSImage) throws {
        isControlShortcutOverlay = false
        isShortcutFlashlightOverlay = false
        closeOverlay()
        try display(image: image)
    }

    func saveCurrentSession() throws {
        guard let canvas = window?.contentView as? ZoomCanvas else {
            throw AnnotationSessionError.noCurrentOverlay
        }
        try annotationSessionStore.save(
            image: canvas.imageForSaving(),
            strokes: canvas.annotationStrokes
        )
    }

    func restoreLatestScreenshot() throws {
        let session = try annotationSessionStore.loadLatest()
        try show(image: session.image)
    }

    func restoreLatestAnnotations() throws {
        guard let canvas = window?.contentView as? ZoomCanvas else {
            throw AnnotationSessionError.noCurrentOverlay
        }
        let strokes = try annotationSessionStore.latestAnnotations(matching: canvas.imageForSaving())
        canvas.replaceAnnotations(with: strokes)
    }

    func showFromControlShortcut(image: NSImage) throws {
        isShortcutFlashlightOverlay = false
        closeOverlay()
        isControlShortcutOverlay = true
        try display(image: image)
    }

    private func display(image: NSImage) throws {
        guard let screen = NSScreen.main else {
            throw OverlayError.noScreen
        }

        let canvas = ZoomCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            image: image,
            settings: settings
        )
        canvas.annotationAppearanceDidChange = { appearance in
            do {
                try HoldZoomSettings.save(annotationAppearance: appearance)
            } catch {
                NSLog("HoldZoom could not save annotation settings: %@", error.localizedDescription)
            }
        }
        try display(canvas, on: screen, ignoresMouseEvents: false)
    }

    private func displayFlashlight() throws {
        guard let screen = NSScreen.main else {
            throw OverlayError.noScreen
        }

        let canvas = FlashlightCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            settings: settings
        )
        try display(canvas, on: screen, ignoresMouseEvents: true)
    }

    private func display(
        _ contentView: NSView,
        on screen: NSScreen,
        ignoresMouseEvents: Bool
    ) throws {
        previousApplication = NSWorkspace.shared.frontmostApplication

        let window = ZoomOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        // Keep status menus above the overlay.
        window.level = .mainMenu
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        window.backgroundColor = ignoresMouseEvents ? .clear : .black
        window.isOpaque = !ignoresMouseEvents
        window.hasShadow = false
        window.ignoresMouseEvents = ignoresMouseEvents
        window.acceptsMouseMovedEvents = true
        window.contentView = contentView

        self.window = window

        if ignoresMouseEvents {
            window.orderFrontRegardless()
        } else {
            window.orderFrontRegardless()
            if let canvas = contentView as? ZoomCanvas {
                guard installInputTap(for: canvas) else {
                    closeOverlay()
                    throw OverlayError.inputTapUnavailable
                }
            }
        }
    }

    func toggleShortcutFlashlight() {
        if isShortcutFlashlightOverlay {
            isShortcutFlashlightOverlay = false
            closeFlashlightOverlay()
            return
        }

        controlCaptureTask?.cancel()
        controlCaptureTask = nil
        isControlShortcutOverlay = false
        closeOverlay()
        isShortcutFlashlightOverlay = true
        do {
            try displayFlashlight()
        } catch {
            isShortcutFlashlightOverlay = false
            NSLog("HoldZoom failed to show flashlight: %@", error.localizedDescription)
            NSAlert(error: error).runModal()
        }
    }

    func toggleFlashlight() {
        toggleShortcutFlashlight()
    }

    private func closeFlashlightOverlay() {
        guard let flashlightWindow = window,
              let canvas = flashlightWindow.contentView as? FlashlightCanvas
        else {
            closeOverlay()
            return
        }

        canvas.dismiss { [weak self, weak flashlightWindow] in
            guard let self,
                  let flashlightWindow,
                  self.window === flashlightWindow
            else { return }
            self.closeOverlay()
        }
    }

    func setControlPressed(_ isPressed: Bool) {
        guard isControlPressed != isPressed else { return }
        isControlPressed = isPressed

        if isPressed {
            startControlStatePolling()
            guard window == nil, !isAnnotationCapturePending else { return }
            controlCaptureTask?.cancel()
            controlCaptureTask = Task { [weak self] in
                await self?.showCapturedImageAfterControlPress()
            }
        } else {
            guard !isAnnotationCapturePending else { return }
            controlCaptureTask?.cancel()
            controlCaptureTask = nil
            guard isControlShortcutOverlay else { return }
            guard let canvas = window?.contentView as? ZoomCanvas,
                  canvas.annotationMode || !canvas.annotationStrokes.isEmpty
            else {
                closeOverlay()
                return
            }
        }
    }

    func close() {
        controlCaptureTask?.cancel()
        controlCaptureTask = nil
        isAnnotationCapturePending = false
        isControlShortcutOverlay = false
        isShortcutFlashlightOverlay = false
        closeOverlay()
    }

    func dismissOverlay() {
        guard isShortcutFlashlightOverlay else {
            closeOverlay()
            return
        }

        isShortcutFlashlightOverlay = false
        closeFlashlightOverlay()
    }

    private func closeOverlay() {
        overlayInputTap?.invalidate()
        overlayInputTap = nil
        if let previousLevel = annotationToolDetailsPreviousWindowLevel {
            window?.level = previousLevel
            annotationToolDetailsPreviousWindowLevel = nil
        }
        isControlShortcutOverlay = false
        guard window != nil else {
            return
        }

        window?.close()
        window = nil
        isShortcutFlashlightOverlay = false

        let shouldRestorePreviousApplication = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == Bundle.main.bundleIdentifier
        if let previousApplication {
            self.previousApplication = nil
            if shouldRestorePreviousApplication {
                previousApplication.activate(options: [])
            }
        }
    }
}

private extension ZoomOverlayController {
    func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenCapturePermission() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    func startControlStatePolling() {
        guard controlStateTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let captureModifier = self.settings.shortcuts.captureWhileHeld.eventSourceFlag
            let isPressed = CGEventSource.flagsState(.combinedSessionState).contains(captureModifier)
            DispatchQueue.main.async { [weak self] in
                self?.setControlPressed(isPressed)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        controlStateTimer = timer
    }
}
