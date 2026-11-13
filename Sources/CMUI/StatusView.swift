// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore

/// Grey pill button used on status screens and in dialogs (spec 2.1).
@MainActor
final class PillButton: NSButton {
    convenience init(title: String) {
        self.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Theme.cg(Theme.pillFill, for: self)
        attributedTitle = NSAttributedString(string: title, attributes: [.font: Theme.pillFont, .foregroundColor: Theme.primaryText])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        let text = attributedTitle.size()
        return NSSize(width: ceil(text.width) + 28, height: 28)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet { layer?.backgroundColor = Theme.cg(isHighlighted ? Theme.pillFillPressed : Theme.pillFill, for: self) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.cg(isHighlighted ? Theme.pillFillPressed : Theme.pillFill, for: self)
    }
}

/// "Switch to landscape · Not now" (spec 8.2.6): a small monochrome pill at the top of the screen.
@MainActor
final class LandscapeOfferView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = Theme.cg(Theme.panelFill, for: self)
        layer?.borderColor = Theme.cg(Theme.hairline, for: self)
    }

    var onAccept: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let row = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        applyColors()
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        row.addArrangedSubview(link("Switch to landscape", #selector(accept)))
        let dot = NSTextField(labelWithString: "·")
        dot.font = Theme.pillFont
        dot.textColor = Theme.secondaryText
        row.addArrangedSubview(dot)
        row.addArrangedSubview(link("Not now", #selector(dismiss)))
        addSubview(row)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func link(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: Theme.pillFont, .foregroundColor: Theme.primaryText])
        return button
    }

    override var fittingSize: NSSize {
        NSSize(width: row.fittingSize.width, height: 28)
    }

    override func layout() {
        super.layout()
        row.frame = bounds
        layer?.cornerRadius = bounds.height / 2
    }

    @objc private func accept() { onAccept?() }
    @objc private func dismiss() { onDismiss?() }
}

/// Centred glyph + bold title + one-line subtitle + grey pill buttons (spec 2.4), on Liquid Glass
/// (`NSGlassEffectView`, macOS 26+) or a dark behind-window blur on macOS 15–25. Only shown while not
/// connected; while mirroring this view is hidden and the screen is fully opaque.
@MainActor
final class StatusView: NSView {
    var onAction: ((StatusContent.Action) -> Void)?

    private let backdrop: NSView
    private let glyph = NSImageView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let buttonRow = NSStackView()
    private let stack = NSStackView()
    private var actions: [StatusContent.Action] = []

    /// Corner radius of the phone-shaped screen, applied to the glass so its edge follows the mask.
    var cornerRadius: CGFloat = 0 {
        didSet { applyCornerRadius() }
    }

    override init(frame: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.tintColor = Theme.glassTint
            backdrop = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .underWindowBackground
            blur.blendingMode = .behindWindow
            blur.state = .active
            backdrop = blur
        }
        super.init(frame: frame)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.frame = bounds
        addSubview(backdrop)

        glyph.contentTintColor = Theme.primaryText
        glyph.imageScaling = .scaleProportionallyDown
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        titleLabel.font = Theme.titleFont
        titleLabel.textColor = Theme.primaryText
        titleLabel.alignment = .center
        titleLabel.cell?.wraps = true
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        subtitleLabel.font = Theme.subtitleFont
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        // Hug the pills: a row stretched to the text width would pack them to the left instead of centring them.
        buttonRow.setHuggingPriority(.required, for: .horizontal)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        for view in [glyph, spinner, titleLabel, subtitleLabel, buttonRow] as [NSView] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(14, after: glyph)
        stack.setCustomSpacing(14, after: spinner)
        stack.setCustomSpacing(18, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ content: StatusContent) {
        glyph.image = Theme.symbol(content.glyph, size: Theme.statusGlyphPointSize, weight: .light)
        glyph.isHidden = content.showsSpinner
        spinner.isHidden = !content.showsSpinner
        if content.showsSpinner { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle
        for view in buttonRow.arrangedSubviews { view.removeFromSuperview() }
        actions = content.buttons.map(\.action)
        for (index, button) in content.buttons.enumerated() {
            let pill = PillButton(title: button.title)
            pill.tag = index
            pill.target = self
            pill.action = #selector(pillPressed(_:))
            buttonRow.addArrangedSubview(pill)
        }
        needsLayout = true
        setAccessibilityLabel("\(content.title). \(content.subtitle)")
    }

    /// Keeps only the glass (another view draws on it).
    func setContentHidden(_ hidden: Bool) {
        stack.isHidden = hidden
    }

    override func layout() {
        super.layout()
        titleLabel.preferredMaxLayoutWidth = max(0, bounds.width - 32)
        subtitleLabel.preferredMaxLayoutWidth = max(0, bounds.width - 32)
        buttonRow.orientation = .horizontal
        if buttonRow.fittingSize.width > bounds.width - 32 {
            buttonRow.orientation = .vertical
        }
    }

    private func applyCornerRadius() {
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            backdrop.wantsLayer = true
            backdrop.layer?.cornerCurve = .continuous
            backdrop.layer?.cornerRadius = cornerRadius
            backdrop.layer?.masksToBounds = true
        }
    }

    @objc private func pillPressed(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        onAction?(actions[sender.tag])
    }
}
#endif
