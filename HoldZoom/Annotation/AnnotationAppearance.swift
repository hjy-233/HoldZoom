//
//  AnnotationAppearance.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/26.
//

import Foundation

struct AnnotationAppearance: Codable {
    var color: AnnotationColor
    var lineWidth: Double
    var fillShapes: Bool
    var eraserMode: AnnotationEraserMode
    var eraserSize: CGFloat

    var isValid: Bool {
        color.red.isFinite && (0 ... 1).contains(color.red)
            && color.green.isFinite && (0 ... 1).contains(color.green)
            && color.blue.isFinite && (0 ... 1).contains(color.blue)
            && color.alpha.isFinite && (0 ... 1).contains(color.alpha)
            && lineWidth.isFinite && (1 ... 16).contains(lineWidth)
            && eraserSize.isFinite && (8 ... 120).contains(eraserSize)
    }
}

private enum HoldZoomSettingsCodingKeys: String, CodingKey {
    case shortcuts
    case zoom
    case flashlight
    case keyboardPan
    case annotationAppearance
}

extension HoldZoomSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: HoldZoomSettingsCodingKeys.self)
        shortcuts = try container.decode(Shortcuts.self, forKey: .shortcuts)
        zoom = try container.decode(Zoom.self, forKey: .zoom)
        flashlight = try container.decode(Flashlight.self, forKey: .flashlight)
        keyboardPan = try container.decode(KeyboardPan.self, forKey: .keyboardPan)
        annotationAppearance = try container.decodeIfPresent(
            AnnotationAppearance.self,
            forKey: .annotationAppearance
        ) ?? HoldZoomSettings.default.annotationAppearance
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: HoldZoomSettingsCodingKeys.self)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(zoom, forKey: .zoom)
        try container.encode(flashlight, forKey: .flashlight)
        try container.encode(keyboardPan, forKey: .keyboardPan)
        try container.encode(annotationAppearance, forKey: .annotationAppearance)
    }
}
