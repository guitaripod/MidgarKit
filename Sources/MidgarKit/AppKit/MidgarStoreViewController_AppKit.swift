#if !canImport(UIKit) && canImport(AppKit)
import AppKit

/// The native macOS storefront. Present it as a sheet with ``Midgar/present(from:config:)``, embed
/// ``Midgar/makeStoreViewController(config:)``, or push this controller directly.
public final class MidgarStoreViewController: NSViewController {

    private let config: MidgarConfig
    private let service = CatalogService()
    private lazy var telemetry = Telemetry(config: config)

    private var apps: [MidgarApp] = []
    private var impressed = Set<String>()
    private var didLoad = false
    private var isOpening = false

    private let scrollView = NSScrollView()
    private let documentView = MidgarFlippedView()
    private let rowsStack = NSStackView()
    private let spinner = NSProgressIndicator()
    private var emptyState: NSView?

    public init(config: MidgarConfig = .default) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root
        preferredContentSize = NSSize(width: 480, height: 640)

        let header = makeHeader()
        root.addSubview(header)

        configureScrollView()
        root.addSubview(scrollView)

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(spinner)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in await load() }
    }

    private func makeHeader() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: config.title)
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.addSubview(titleLabel)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeTapped))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\u{1b}"
        doneButton.contentTintColor = config.resolvedAccent
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(doneButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            doneButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.distribution = .fill
        rowsStack.spacing = 0
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowsStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    @objc private func closeTapped() {
        dismiss(nil)
    }

    @MainActor
    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        let cached = service.cachedSnapshot()
        if cached.isEmpty {
            spinner.startAnimation(nil)
        } else {
            render(cached)
        }
        await refresh()
    }

    @MainActor
    private func refresh() async {
        let result = await service.build(config: config)
        spinner.stopAnimation(nil)
        if result.apps.isEmpty {
            if apps.isEmpty { showEmptyState() }
        } else if !result.enriched && !apps.isEmpty {
            return
        } else {
            removeEmptyState()
            render(result.apps)
        }
    }

    @MainActor
    private func handleRetry() {
        removeEmptyState()
        spinner.startAnimation(nil)
        Task { @MainActor in await refresh() }
    }

    @MainActor
    private func render(_ newApps: [MidgarApp]) {
        apps = newApps
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for app in newApps {
            let row = MidgarAppRowView(app: app, accent: config.resolvedAccent) { [weak self] in
                self?.open(app)
            }
            rowsStack.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor).isActive = true
            registerImpression(app)
        }
    }

    private func open(_ app: MidgarApp) {
        guard !isOpening else { return }
        isOpening = true
        telemetry.send(.tap, appId: app.appId)
        NSWorkspace.shared.open(app.storeURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isOpening = false
        }
    }

    private func registerImpression(_ app: MidgarApp) {
        guard impressed.insert(app.appId).inserted else { return }
        telemetry.send(.impression, appId: app.appId)
    }

    @MainActor
    private func showEmptyState() {
        guard emptyState == nil else { return }
        let state = MidgarEmptyStateView(accent: config.resolvedAccent) { [weak self] in
            self?.handleRetry()
        }
        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        NSLayoutConstraint.activate([
            state.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            state.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            state.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 40),
            state.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -40),
        ])
        emptyState = state
    }

    @MainActor
    private func removeEmptyState() {
        emptyState?.removeFromSuperview()
        emptyState = nil
    }
}

/// A top-anchored container so the storefront rows stack from the top down inside the scroll view.
private final class MidgarFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A single app shown in the macOS storefront: icon, copy, GET pill, optional screenshot strip,
/// and a hairline separator. The whole row is clickable, mirroring the iOS cell.
@MainActor
private final class MidgarAppRowView: NSView {
    private let app: MidgarApp
    private let accent: NSColor
    private let onOpen: () -> Void

    private let iconView = NSImageView()
    private let monogramLabel = NSTextField(labelWithString: "")
    private var iconTask: Task<Void, Never>?

    private var strip: MidgarScreenshotStripView?

    init(app: MidgarApp, accent: NSColor, onOpen: @escaping () -> Void) {
        self.app = app
        self.accent = accent
        self.onOpen = onOpen
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        loadIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { iconTask?.cancel() }

    private var appAccent: NSColor { NSColor(hex: app.accentHex) ?? accent }

    private func build() {
        let icon = makeIconView()
        let textStack = makeTextStack()
        let getButton = makeGetButton()

        let topRow = NSStackView(views: [icon, textStack, getButton])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 12
        topRow.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

        let mainStack = NSStackView(views: [topRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        topRow.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        topRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        if !app.screenshotURLs.isEmpty {
            let strip = MidgarScreenshotStripView(urls: app.screenshotURLs)
            strip.translatesAutoresizingMaskIntoConstraints = false
            mainStack.addArrangedSubview(strip)
            strip.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
            strip.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
            self.strip = strip
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setupAccessibility()
    }

    private func makeIconView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = 13.5
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        container.layer?.masksToBounds = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        monogramLabel.alignment = .center
        monogramLabel.textColor = .white
        monogramLabel.font = .systemFont(ofSize: 24, weight: .bold)
        monogramLabel.isHidden = true
        monogramLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(monogramLabel)

        container.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 60),
            container.heightAnchor.constraint(equalToConstant: 60),
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            monogramLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            monogramLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func makeTextStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        if app.featured {
            let featured = NSTextField(labelWithAttributedString: featuredText())
            stack.addArrangedSubview(featured)
        }

        let title = NSTextField(labelWithString: app.name)
        title.font = NSFont.preferredFont(forTextStyle: .headline)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        stack.addArrangedSubview(title)

        if let tagline = app.tagline, !tagline.isEmpty {
            let taglineLabel = NSTextField(wrappingLabelWithString: tagline)
            taglineLabel.font = NSFont.preferredFont(forTextStyle: .subheadline)
            taglineLabel.textColor = .secondaryLabelColor
            taglineLabel.lineBreakMode = .byTruncatingTail
            taglineLabel.maximumNumberOfLines = 2
            taglineLabel.isSelectable = false
            stack.addArrangedSubview(taglineLabel)
        }

        let meta = NSTextField(labelWithAttributedString: metaText())
        meta.lineBreakMode = .byTruncatingTail
        meta.maximumNumberOfLines = 1
        stack.addArrangedSubview(meta)

        for case let label as NSTextField in stack.arrangedSubviews {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return stack
    }

    private func makeGetButton() -> NSButton {
        let button = MidgarPillButton(title: app.priceLabel.uppercased(), accent: appAccent)
        button.target = self
        button.action = #selector(getTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func featuredText() -> NSAttributedString {
        NSAttributedString(
            string: "FEATURED",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: appAccent,
                .kern: 0.6,
            ]
        )
    }

    private func metaText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let caption = NSFont.preferredFont(forTextStyle: .caption1)
        if app.hasRating, let rating = app.rating {
            result.append(NSAttributedString(
                string: "★ ",
                attributes: [.foregroundColor: NSColor.systemYellow, .font: caption]
            ))
            var ratingText = String(format: "%.1f", rating)
            if let count = app.ratingCount, count > 0 { ratingText += " (\(count))" }
            result.append(NSAttributedString(
                string: ratingText,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: caption]
            ))
        }
        if let genre = app.genre, !genre.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(
                    string: "  ·  ",
                    attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: caption]
                ))
            }
            result.append(NSAttributedString(
                string: genre,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: caption]
            ))
        }
        return result
    }

    private func loadIcon() {
        iconTask?.cancel()
        let appId = app.appId
        let url = app.iconURL
        let monogram = app.monogram
        let accent = appAccent
        iconTask = Task { @MainActor [weak self] in
            let loaded = await midgarLoadImage(url) ?? midgarBundledIcon(appId)
            guard let self, !Task.isCancelled else { return }
            if let loaded {
                self.iconView.image = loaded
                self.monogramLabel.isHidden = true
            } else {
                self.showMonogram(monogram, accent: accent)
            }
        }
    }

    private func showMonogram(_ text: String, accent: NSColor) {
        iconView.image = nil
        if let container = iconView.superview {
            container.layer?.backgroundColor = accent.cgColor
        }
        monogramLabel.stringValue = text
        monogramLabel.isHidden = false
    }

    private func setupAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityText())
    }

    private func accessibilityText() -> String {
        var parts = [app.name]
        if let tagline = app.tagline, !tagline.isEmpty { parts.append(tagline) }
        if app.hasRating, let rating = app.rating {
            parts.append(String(format: "rated %.1f stars", rating))
        }
        parts.append(app.priceLabel == "GET" ? "Free" : app.priceLabel)
        return parts.joined(separator: ", ")
    }

    @objc private func getTapped() { onOpen() }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let strip, strip.frame.contains(location) {
            super.mouseDown(with: event)
            return
        }
        onOpen()
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen()
        return true
    }
}

/// A capsule GET/price pill: accent text on a faint accent fill, approximating the iOS look.
private final class MidgarPillButton: NSButton {
    private let accent: NSColor

    init(title: String, accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .rounded
        wantsLayer = true
        font = NSFont.preferredFont(forTextStyle: .footnote).midgarBold
        contentTintColor = accent
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: accent,
                .font: NSFont.preferredFont(forTextStyle: .footnote).midgarBold,
            ]
        )
        layer?.backgroundColor = accent.withAlphaComponent(0.14).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 24
        size.height = max(size.height, 26)
        return size
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        layer?.cornerCurve = .continuous
    }
}

/// A horizontally scrolling strip of app screenshots, each sized to its aspect ratio once loaded.
@MainActor
private final class MidgarScreenshotStripView: NSView {
    static let preferredHeight: CGFloat = 188

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var shots: [MidgarScreenshotView] = []

    init(urls: [URL]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            document.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
        ])

        for url in urls.prefix(10) {
            let shot = MidgarScreenshotView(url: url)
            stack.addArrangedSubview(shot)
            shots.append(shot)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A single rounded screenshot thumbnail that resizes its width to the image aspect ratio on load.
@MainActor
private final class MidgarScreenshotView: NSImageView {
    private var widthConstraint: NSLayoutConstraint!
    private var loadTask: Task<Void, Never>?

    init(url: URL) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        widthConstraint = widthAnchor.constraint(equalToConstant: MidgarScreenshotStripView.preferredHeight * 0.56)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MidgarScreenshotStripView.preferredHeight),
            widthConstraint,
        ])
        load(url: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { loadTask?.cancel() }

    private func load(url: URL) {
        loadTask = Task { @MainActor [weak self] in
            let loaded = await midgarLoadImage(url)
            guard let self, !Task.isCancelled, let loaded, loaded.size.height > 0 else { return }
            self.image = loaded
            let height = MidgarScreenshotStripView.preferredHeight
            self.widthConstraint.constant = (height * loaded.size.width / loaded.size.height).rounded()
        }
    }
}

/// The empty state shown when no apps are available: an icon, copy, and a Retry button.
@MainActor
private final class MidgarEmptyStateView: NSView {
    private let onRetry: () -> Void

    init(accent: NSColor, onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        super.init(frame: .zero)

        let imageView = NSImageView()
        if let symbol = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) {
            imageView.image = symbol
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
        }
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Nothing here yet")
        title.font = NSFont.preferredFont(forTextStyle: .headline)
        title.textColor = .labelColor
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: "Check your connection and try again.")
        subtitle.font = NSFont.preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let retry = NSButton(title: "Retry", target: self, action: #selector(retryTapped))
        retry.bezelStyle = .rounded
        retry.contentTintColor = accent

        let stack = NSStackView(views: [imageView, title, subtitle, retry])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func retryTapped() { onRetry() }
}

private extension NSFont {
    var midgarBold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
#endif
