//
//  AnnotationToolDetailsViewController.swift
//  HoldZoom
//  Created by Codex on 2026/10/26.
//

import AppKit

@MainActor
final class AnnotationToolDetailsViewController: NSViewController {
    private weak var canvas: ZoomCanvas?
    private let tool: AnnotationTool
    private let lineWidthValue = NSTextField(labelWithString: "")
    private let eraserSizeValue = NSTextField(labelWithString: "")
    private weak var annotationColorWell: NSColorWell?

    init(canvas: ZoomCanvas, tool: AnnotationTool) {
        self.canvas = canvas
        self.tool = tool
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 240, height: tool == .eraser ? 150 : 190)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "\(tool.label)\(String(localized: "设置"))")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(title)

        if tool == .eraser {
            addEraserControls(to: stack)
        } else {
            addDrawingControls(to: stack)
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        view = container
    }

    private func addEraserControls(to stack: NSStackView) {
        let modeControl = NSSegmentedControl(
            labels: AnnotationEraserMode.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(eraserModeChanged(_:))
        )
        modeControl.selectedSegment = AnnotationEraserMode.allCases.firstIndex(
            of: canvas?.annotationEraserMode ?? .partial
        ) ?? 0
        modeControl.setAccessibilityLabel(String(localized: "擦除范围"))
        stack.addArrangedSubview(makeLabeledRow(String(localized: "擦除范围"), control: modeControl))

        eraserSizeValue.stringValue = eraserSizeLabel(canvas?.annotationEraserSize ?? 32)
        let slider = makeSlider(
            minimum: 8,
            maximum: 120,
            value: Double(canvas?.annotationEraserSize ?? 32),
            action: #selector(eraserSizeChanged(_:)),
            label: String(localized: "橡皮直径")
        )
        stack.addArrangedSubview(makeLabeledRow(String(localized: "大小"), control: slider))
        stack.addArrangedSubview(eraserSizeValue)
    }

    private func addDrawingControls(to stack: NSStackView) {
        let colorWell = NSColorWell()
        colorWell.color = canvas?.annotationColor.nsColor ?? .systemRed
        colorWell.isContinuous = true
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.setAccessibilityLabel(String(localized: "颜色"))
        annotationColorWell = colorWell
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelDidChange(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
        stack.addArrangedSubview(makeLabeledRow(String(localized: "颜色"), control: colorWell))

        lineWidthValue.stringValue = lineWidthLabel(canvas?.annotationLineWidth ?? 3)
        let slider = makeSlider(
            minimum: 1,
            maximum: 16,
            value: canvas?.annotationLineWidth ?? 3,
            action: #selector(lineWidthChanged(_:)),
            label: String(localized: "线宽")
        )
        stack.addArrangedSubview(makeLabeledRow(String(localized: "线宽"), control: slider))
        stack.addArrangedSubview(lineWidthValue)

        if tool == .circle || tool == .rectangle {
            let fillButton = NSButton(
                checkboxWithTitle: String(localized: "填充图形"),
                target: self,
                action: #selector(fillChanged(_:))
            )
            fillButton.state = canvas?.annotationFillShapes == true ? .on : .off
            stack.addArrangedSubview(fillButton)
        }
    }

    private func makeLabeledRow(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeSlider(
        minimum: Double,
        maximum: Double,
        value: Double,
        action: Selector,
        label: String
    ) -> NSSlider {
        let slider = NSSlider(value: value, minValue: minimum, maxValue: maximum, target: self, action: action)
        slider.isContinuous = false
        slider.setAccessibilityLabel(label)
        return slider
    }

    private func lineWidthLabel(_ value: Double) -> String {
        "\(String(localized: "线宽"))：\(Int(value.rounded())) pt"
    }

    private func eraserSizeLabel(_ value: CGFloat) -> String {
        "\(String(localized: "橡皮直径"))：\(Int(value.rounded())) pt"
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        applyAnnotationColor(sender.color)
    }

    @objc private func colorPanelDidChange(_ notification: Notification) {
        guard annotationColorWell?.isActive == true,
              let colorPanel = notification.object as? NSColorPanel
        else { return }
        applyAnnotationColor(colorPanel.color)
    }

    private func applyAnnotationColor(_ color: NSColor) {
        guard let canvas else { return }
        let annotationColor = AnnotationColor(color: color)
        guard canvas.annotationColor != annotationColor else { return }
        canvas.annotationColor = annotationColor
        notifyAppearanceChanged()
    }

    @objc private func lineWidthChanged(_ sender: NSSlider) {
        canvas?.annotationLineWidth = sender.doubleValue
        lineWidthValue.stringValue = lineWidthLabel(sender.doubleValue)
        notifyAppearanceChanged()
    }

    @objc private func eraserModeChanged(_ sender: NSSegmentedControl) {
        guard AnnotationEraserMode.allCases.indices.contains(sender.selectedSegment) else { return }
        canvas?.annotationEraserMode = AnnotationEraserMode.allCases[sender.selectedSegment]
        notifyAppearanceChanged()
    }

    @objc private func eraserSizeChanged(_ sender: NSSlider) {
        let size = CGFloat(sender.doubleValue)
        canvas?.annotationEraserSize = size
        eraserSizeValue.stringValue = eraserSizeLabel(size)
        notifyAppearanceChanged()
    }

    @objc private func fillChanged(_ sender: NSButton) {
        canvas?.annotationFillShapes = sender.state == .on
        notifyAppearanceChanged()
    }

    private func notifyAppearanceChanged() {
        guard let canvas else { return }
        canvas.annotationAppearanceDidChange?(canvas.annotationAppearance)
        canvas.needsDisplay = true
    }
}
