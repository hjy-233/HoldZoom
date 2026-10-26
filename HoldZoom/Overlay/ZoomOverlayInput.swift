//
//  ZoomOverlayInput.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/25.
//

import AppKit

@MainActor
extension ZoomOverlayController {
    func installInputTap(for canvas: ZoomCanvas) -> Bool {
        let panKeys = settings.shortcuts.panUp
            + settings.shortcuts.panLeft
            + settings.shortcuts.panDown
            + settings.shortcuts.panRight
        let keyCodes = Set(panKeys.compactMap(HoldZoomSettings.KeyBinding.keyCode(for:)))
        guard let overlayWindowNumber = canvas.window?.windowNumber else { return false }

        let tap = OverlayInputTap(
            panKeyCodes: keyCodes,
            panModifiers: Set(settings.shortcuts.panModifiers),
            exitShortcut: settings.shortcuts.exitOverlay,
            annotationEnterShortcut: settings.shortcuts.annotations.enter,
            annotationShortcuts: settings.shortcuts.annotations.all,
            captureModifier: settings.shortcuts.captureWhileHeld,
            overlayWindowNumber: overlayWindowNumber
        ) { [weak self, weak canvas] event, location in
            guard let self, let canvas else { return }
            handleOverlayInput(event, at: location, canvas: canvas)
        }
        canvas.annotationToolDetailsStateDidChange = { [weak self, weak tap] isShown in
            tap?.annotationToolDetailsIsShown = isShown
            guard let self, let window = self.window else { return }
            if isShown {
                guard self.annotationToolDetailsPreviousWindowLevel == nil else { return }
                self.annotationToolDetailsPreviousWindowLevel = window.level
                window.level = .floating
            } else if let previousLevel = self.annotationToolDetailsPreviousWindowLevel {
                window.level = previousLevel
                self.annotationToolDetailsPreviousWindowLevel = nil
            }
        }
        guard tap.install() else { return false }
        overlayInputTap = tap
        return true
    }

    func handleOverlayInput(_ event: NSEvent, at location: NSPoint, canvas: ZoomCanvas) {
        guard let window = canvas.window else { return }
        let windowLocation = window.convertPoint(fromScreen: location)
        let mouse = canvas.convert(windowLocation, from: nil)

        if event.type == .scrollWheel {
            handleScroll(event, at: mouse, canvas: canvas)
            return
        }
        if event.type == .keyDown, handleKeyboardShortcut(event, canvas: canvas) {
            return
        }
        if canvas.handleAnnotationToolPicker(event, at: mouse) {
            return
        }
        handlePointerOrPanKey(event, at: mouse, canvas: canvas)
    }

    private func handleScroll(_ event: NSEvent, at mouse: NSPoint, canvas: ZoomCanvas) {
        canvas.handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            controlPressed: canvas.annotationMode
                || event.modifierFlags.contains(settings.shortcuts.zoom.eventFlag),
            at: mouse
        )
    }

    private func handleKeyboardShortcut(_ event: NSEvent, canvas: ZoomCanvas) -> Bool {
        let shortcuts = settings.shortcuts.annotations
        let ignoredModifiers: Set<HoldZoomSettings.ModifierKey> = [
            settings.shortcuts.captureWhileHeld
        ]
        let shouldEnterAnnotationMode = !canvas.annotationMode
            && event.modifierFlags.contains(settings.shortcuts.captureWhileHeld.eventFlag)
            && shortcuts.enter.matches(event, ignoring: ignoredModifiers)
        if shouldEnterAnnotationMode {
            canvas.enterAnnotationMode()
            overlayInputTap?.annotationMode = true
            return true
        }
        if canvas.annotationMode {
            if shortcuts.undo.matches(event, ignoring: ignoredModifiers) {
                canvas.undoAnnotation()
                return true
            }
            if shortcuts.redo.matches(event, ignoring: ignoredModifiers) {
                canvas.redoAnnotation()
                return true
            }
            if shortcuts.clear.matches(event, ignoring: ignoredModifiers) {
                canvas.clearAnnotations()
                return true
            }
            if shortcuts.save.matches(event, ignoring: ignoredModifiers) {
                do {
                    try saveCurrentSession()
                } catch {
                    NSAlert(error: error).runModal()
                }
                return true
            }
        }

        guard settings.shortcuts.exitOverlay.matches(event, ignoring: ignoredModifiers) else {
            return false
        }
        if canvas.annotationMode {
            canvas.exitAnnotationMode()
            overlayInputTap?.annotationMode = false
        } else {
            dismissOverlay()
        }
        return true
    }

    private func handlePointerOrPanKey(_ event: NSEvent, at mouse: NSPoint, canvas: ZoomCanvas) {
        switch event.type {
        case .leftMouseDown where canvas.annotationMode:
            canvas.beginAnnotation(at: mouse)
        case .leftMouseDown, .rightMouseDown:
            canvas.beginDragging(at: mouse)
        case .leftMouseDragged where canvas.annotationMode:
            canvas.continueAnnotation(at: mouse)
        case .leftMouseDragged, .rightMouseDragged:
            canvas.continueDragging(at: mouse)
        case .leftMouseUp where canvas.annotationMode:
            canvas.endAnnotation()
            canvas.endDragging()
        case .leftMouseUp, .rightMouseUp:
            canvas.endDragging()
        case .keyDown:
            canvas.keyDown(with: event)
        case .keyUp:
            canvas.keyUp(with: event)
        default:
            break
        }
    }
}
