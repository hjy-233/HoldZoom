//
//  ZoomOverlayAnnotationCapture.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/25.
//

import AppKit

@MainActor
extension ZoomOverlayController {
    func isAnnotationEntryShortcut(_ event: NSEvent) -> Bool {
        let captureModifier = settings.shortcuts.captureWhileHeld
        return event.modifierFlags.contains(captureModifier.eventFlag)
            && settings.shortcuts.annotations.enter.matches(
                event,
                ignoring: [captureModifier]
            )
    }

    func beginAnnotationCaptureFromShortcut() {
        guard window == nil, !isAnnotationCapturePending else { return }
        controlCaptureTask?.cancel()
        isAnnotationCapturePending = true
        controlCaptureTask = Task { [weak self] in
            await self?.showCapturedImageEnteringAnnotationMode()
        }
    }

    func showCapturedImageAfterControlPress() async {
        do {
            let delay = settings.shortcuts.captureDelay ?? 0.25
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }

            let image = try await ScreenCapture.capture()
            guard isControlPressed, !Task.isCancelled, window == nil else { return }
            try showFromControlShortcut(image: image)
        } catch is CancellationError {
            return
        } catch {
            NSLog("HoldZoom failed to show captured screen: %@", error.localizedDescription)
            guard !hasPresentedCaptureError else { return }
            hasPresentedCaptureError = true
            NSAlert(error: error).runModal()
        }
    }

    private func showCapturedImageEnteringAnnotationMode() async {
        defer { isAnnotationCapturePending = false }
        do {
            let image = try await ScreenCapture.capture()
            guard !Task.isCancelled, window == nil else { return }
            try showFromControlShortcut(image: image)
            if let canvas = window?.contentView as? ZoomCanvas {
                canvas.enterAnnotationMode()
                overlayInputTap?.annotationMode = true
            }
        } catch is CancellationError {
            return
        } catch {
            NSLog("HoldZoom failed to capture screen for annotation: %@", error.localizedDescription)
            guard !hasPresentedCaptureError else { return }
            hasPresentedCaptureError = true
            NSAlert(error: error).runModal()
        }
    }
}
