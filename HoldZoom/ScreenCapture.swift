//
//  ScreenCapture.swift
//  HoldZoom
//
//  Created by hjy_666 on 2026/10/24.
//

import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    case screenRecordingPermission

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            String(localized: "无法找到屏幕")
        case .screenRecordingPermission:
            String(localized: "请在系统设置的“隐私与安全性”中允许 HoldZoom 录制屏幕，然后重新打开 HoldZoom")
        }
    }
}

@MainActor
enum ScreenCapture {
    static func capture() async throws -> NSImage {
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            throw CaptureError.screenRecordingPermission
        }

        let content = try await SCShareableContent
            .excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            excludingWindows: []
        )

        let config = SCStreamConfiguration()

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.captureResolution = .best
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return NSImage(
            cgImage: image,
            size: NSSize(
                width: display.frame.width,
                height: display.frame.height
            )
        )
    }
}
