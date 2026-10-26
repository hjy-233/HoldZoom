//
//  HoldZoomApp.swift
//  HoldZoom
//

import AppKit
import SwiftUI

@main
struct HoldZoomApp: App {
    @NSApplicationDelegateAdaptor(HoldZoomAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class HoldZoomAppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: ZoomOverlayController?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlay = ZoomOverlayController()
        self.overlay = overlay

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "plus.magnifyingglass",
            accessibilityDescription: "HoldZoom"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePopover)
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 250, height: 276)
        popover.contentViewController = NSHostingController(
            rootView: HoldZoomPanel(
                onCapture: { [weak self] in self?.captureScreen() },
                onFlashlight: { [weak self] in self?.toggleFlashlight() },
                onSaveSession: { [weak self] in self?.saveCurrentSession() },
                onRestoreScreenshot: { [weak self] in self?.restoreLatestScreenshot() },
                onRestoreAnnotations: { [weak self] in self?.restoreLatestAnnotations() },
                onQuit: { [weak self] in self?.quit() }
            )
        )
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover,
              let button = statusItem?.button
        else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func captureScreen() {
        popover?.performClose(nil)
        guard let overlay else { return }

        Task {
            do {
                let image = try await ScreenCapture.capture()
                try overlay.show(image: image)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func toggleFlashlight() {
        popover?.performClose(nil)
        overlay?.toggleFlashlight()
    }

    private func saveCurrentSession() {
        popover?.performClose(nil)
        do {
            try overlay?.saveCurrentSession()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func restoreLatestScreenshot() {
        popover?.performClose(nil)
        do {
            try overlay?.restoreLatestScreenshot()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func restoreLatestAnnotations() {
        popover?.performClose(nil)
        do {
            try overlay?.restoreLatestAnnotations()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func quit() {
        overlay?.close()
        NSApp.terminate(nil)
    }
}

private struct HoldZoomPanel: View {
    let onCapture: () -> Void
    let onFlashlight: () -> Void
    let onSaveSession: () -> Void
    let onRestoreScreenshot: () -> Void
    let onRestoreAnnotations: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HoldZoom")
                .font(.headline)

            Button(action: onCapture) {
                Label("截图放大", systemImage: "plus.magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(action: onFlashlight) {
                Label("手电筒", systemImage: "flashlight.on.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(action: onSaveSession) {
                Label("永久保存当前会话", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(action: onRestoreScreenshot) {
                Label("恢复最近截图", systemImage: "photo")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(action: onRestoreAnnotations) {
                Label("仅恢复最近标注", systemImage: "pencil.tip.crop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Divider()

            Button(action: onQuit) {
                Label("退出 HoldZoom", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 250)
    }
}
