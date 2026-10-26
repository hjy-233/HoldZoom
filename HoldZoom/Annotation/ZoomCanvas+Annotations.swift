//
//  ZoomCanvas+Annotations.swift
//  HoldZoom
//  Created by hjy_666 on 2026/10/26.
//

import AppKit

private final class AnnotationToolButton: NSButton {
    var onRightClick: ((NSButton) -> Void)?

    override func rightMouseDown(with _: NSEvent) {
        onRightClick?(self)
    }
}

extension ZoomCanvas {
    func installAnnotationToolPicker() {
        let picker = NSVisualEffectView()
        picker.material = .hudWindow
        picker.blendingMode = .withinWindow
        picker.state = .active
        picker.wantsLayer = true
        picker.layer?.cornerRadius = 9
        picker.isHidden = true
        picker.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addAnnotationHistoryButtons(to: stack)

        for (index, tool) in AnnotationTool.allCases.enumerated() {
            let button = makeAnnotationToolButton(for: tool, index: index)
            stack.addArrangedSubview(button)
            annotationToolButtons[tool] = button
        }
        updateSelectedAnnotationToolButton()

        picker.addSubview(stack)
        addSubview(picker)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: picker.leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: picker.trailingAnchor, constant: -5),
            stack.topAnchor.constraint(equalTo: picker.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: picker.bottomAnchor, constant: -5),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            picker.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        annotationToolPicker = picker
        updateAnnotationHistoryButtons()
    }

    private func makeAnnotationToolButton(for tool: AnnotationTool, index: Int) -> AnnotationToolButton {
        let button = AnnotationToolButton(
            title: "",
            target: self,
            action: #selector(selectAnnotationTool(_:))
        )
        button.setButtonType(.toggle)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.tag = index
        button.onRightClick = { [weak self] button in
            self?.showAnnotationToolDetailsFromRightClick(button)
        }
        button.toolTip = "\(tool.label) · \(String(localized: "右键设置"))"
        button.setAccessibilityLabel(tool.label)
        if let image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.label) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = tool.label
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func addAnnotationHistoryButtons(to stack: NSStackView) {
        let undoButton = makeAnnotationHistoryButton(
            symbol: "arrow.uturn.backward",
            label: String(localized: "撤销"),
            action: #selector(undoAnnotationFromToolbar)
        )
        let redoButton = makeAnnotationHistoryButton(
            symbol: "arrow.uturn.forward",
            label: String(localized: "重做"),
            action: #selector(redoAnnotationFromToolbar)
        )
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)
        annotationUndoButton = undoButton
        annotationRedoButton = redoButton
    }

    private func makeAnnotationHistoryButton(
        symbol: String,
        label: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = label
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    @objc func selectAnnotationTool(_ sender: NSButton) {
        guard AnnotationTool.allCases.indices.contains(sender.tag) else { return }
        let tool = AnnotationTool.allCases[sender.tag]
        selectedAnnotationTool = tool
        updateSelectedAnnotationToolButton()
        needsDisplay = true
    }

    private func presentAnnotationToolDetails(for tool: AnnotationTool, anchoredTo sender: NSButton) {
        let isShowingRequestedTool = annotationToolDetailsPopover?.isShown == true
            && annotationToolDetailsTool == tool
        if isShowingRequestedTool {
            return
        }
        annotationToolDetailsPopover?.close()
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.delegate = self
        popover.contentViewController = AnnotationToolDetailsViewController(canvas: self, tool: tool)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
        annotationToolDetailsPopover = popover
        annotationToolDetailsTool = tool
        annotationToolDetailsStateDidChange?(true)
    }

    private func showAnnotationToolDetailsFromRightClick(_ button: NSButton) {
        guard let tool = annotationToolButtons.first(where: { $0.value === button })?.key else { return }
        selectedAnnotationTool = tool
        updateSelectedAnnotationToolButton()
        needsDisplay = true
        presentAnnotationToolDetails(for: tool, anchoredTo: button)
    }

    private func updateSelectedAnnotationToolButton() {
        for (tool, button) in annotationToolButtons {
            let isSelected = tool == selectedAnnotationTool
            button.state = isSelected ? .on : .off
            button.bezelColor = isSelected ? .controlAccentColor : nil
            button.contentTintColor = isSelected ? .white : .secondaryLabelColor
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              annotationToolDetailsPopover === popover
        else { return }
        annotationToolDetailsPopover = nil
        annotationToolDetailsTool = nil
        annotationToolDetailsStateDidChange?(false)
    }

    func handleAnnotationToolPicker(_ event: NSEvent, at location: NSPoint) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            guard annotationMode,
                  let picker = annotationToolPicker,
                  picker.frame.contains(location)
            else { return false }
            isAnnotationToolPickerGesture = true
            let pickerLocation = picker.convert(location, from: self)
            if let button = picker.hitTest(pickerLocation) as? NSButton {
                if event.type == .rightMouseDown {
                    showAnnotationToolDetailsFromRightClick(button)
                } else {
                    button.performClick(nil)
                }
            }
            return true
        case .leftMouseDragged, .rightMouseDragged:
            return isAnnotationToolPickerGesture
        case .leftMouseUp, .rightMouseUp:
            guard isAnnotationToolPickerGesture else { return false }
            isAnnotationToolPickerGesture = false
            return true
        default:
            return false
        }
    }

    func annotationPoint(at location: NSPoint) -> AnnotationPoint {
        let imageWidth = max(bounds.width * zoom, 1)
        let imageHeight = max(bounds.height * zoom, 1)
        let normalizedX = (location.x - imageOrigin.x) / imageWidth
        let normalizedY = (location.y - imageOrigin.y) / imageHeight
        return AnnotationPoint(
            normalizedX: Double(min(max(normalizedX, 0), 1)),
            normalizedY: Double(min(max(normalizedY, 0), 1))
        )
    }

    func drawAnnotations() {
        for stroke in annotationStrokes {
            drawAnnotation(stroke)
        }
        if let currentAnnotationPoints {
            drawAnnotation(
                AnnotationStroke(
                    points: currentAnnotationPoints,
                    tool: currentAnnotationTool,
                    color: annotationColor,
                    lineWidth: annotationLineWidth,
                    isFilled: annotationFillShapes
                )
            )
        }
    }

    func drawAnnotationModeIndicator() {
        let mode = String(localized: "标注模式")
        let selectedTool = String(localized: "当前工具")
        let title = "\(mode) · \(selectedTool)：\(selectedAnnotationTool.label)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = title.size(withAttributes: attributes)
        let indicator = NSRect(
            x: bounds.minX + 20,
            y: bounds.maxY - textSize.height - 32,
            width: textSize.width + 24,
            height: textSize.height + 12
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: indicator, xRadius: 8, yRadius: 8).fill()
        title.draw(
            at: NSPoint(x: indicator.minX + 12, y: indicator.minY + 6),
            withAttributes: attributes
        )
    }

    func drawAnnotation(_ stroke: AnnotationStroke) {
        guard let firstPoint = stroke.points.first else { return }
        if stroke.tool == .eraser {
            drawEraserCursor(at: viewPoint(for: stroke.points.last ?? firstPoint))
            return
        }

        let lineWidth = CGFloat(stroke.lineWidth) * zoom
        let color = stroke.color.nsColor
        color.setStroke()
        for polyline in annotationPolylines(points: stroke.points, tool: stroke.tool) {
            guard let first = polyline.first else { continue }
            if polyline.count == 1 {
                let dot = NSBezierPath(ovalIn: NSRect(
                    x: first.x - lineWidth / 2,
                    y: first.y - lineWidth / 2,
                    width: lineWidth,
                    height: lineWidth
                ))
                color.setFill()
                dot.fill()
                continue
            }

            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: first)
            for point in polyline.dropFirst() {
                path.line(to: point)
            }
            if stroke.tool == .rectangle || stroke.tool == .circle {
                path.close()
            }
            if stroke.isFilled, stroke.tool == .rectangle || stroke.tool == .circle {
                color.setFill()
                path.fill()
                color.setStroke()
            }
            path.stroke()
        }
    }

    func viewPoint(for point: AnnotationPoint) -> NSPoint {
        NSPoint(
            x: imageOrigin.x + CGFloat(point.normalizedX) * bounds.width * zoom,
            y: imageOrigin.y + CGFloat(point.normalizedY) * bounds.height * zoom
        )
    }

    func annotationPolylines(
        points: [AnnotationPoint],
        tool: AnnotationTool
    ) -> [[NSPoint]] {
        let viewPoints = points.map(viewPoint(for:))
        guard let start = viewPoints.first else { return [] }
        guard let end = viewPoints.last, viewPoints.count > 1 else { return [[start]] }

        switch tool {
        case .pen:
            return [viewPoints]
        case .line:
            return [[start, end]]
        case .rectangle:
            return [rectanglePolyline(from: start, to: end)]
        case .circle:
            return [circlePolyline(from: start, to: end)]
        case .arrow:
            return arrowPolylines(from: start, to: end)
        case .eraser:
            return []
        }
    }

    private func rectanglePolyline(from start: NSPoint, to end: NSPoint) -> [NSPoint] {
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        return [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.minY)
        ]
    }

    private func circlePolyline(from start: NSPoint, to end: NSPoint) -> [NSPoint] {
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        return (0 ... 48).map { index in
            let angle = CGFloat(index) / 48 * 2 * .pi
            return NSPoint(
                x: rect.midX + cos(angle) * rect.width / 2,
                y: rect.midY + sin(angle) * rect.height / 2
            )
        }
    }

    private func arrowPolylines(from start: NSPoint, to end: NSPoint) -> [[NSPoint]] {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let angle = atan2(deltaY, deltaX)
        let headLength = min(18 * zoom, hypot(deltaX, deltaY) * 0.6)
        let leftHead = NSPoint(
            x: end.x - cos(angle - .pi / 6) * headLength,
            y: end.y - sin(angle - .pi / 6) * headLength
        )
        let rightHead = NSPoint(
            x: end.x - cos(angle + .pi / 6) * headLength,
            y: end.y - sin(angle + .pi / 6) * headLength
        )
        return [[start, end], [leftHead, end, rightHead]]
    }

    private func drawEraserCursor(at point: NSPoint) {
        let radius = annotationEraserRadius
        let cursor = NSBezierPath(ovalIn: NSRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        cursor.lineWidth = 1.5
        NSColor.white.setStroke()
        cursor.stroke()
    }
}
