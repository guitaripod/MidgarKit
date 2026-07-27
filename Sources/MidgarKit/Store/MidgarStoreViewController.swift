#if canImport(UIKit)
import UIKit
import StoreKit

/// The storefront screen. Present it with ``Midgar/present(from:config:)``, embed
/// ``Midgar/makeStoreViewController(config:)``, or push this controller directly.
public final class MidgarStoreViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case featured
        case all

        var title: String {
            switch self {
            case .featured: return "Featured"
            case .all: return "All Apps"
            }
        }
    }

    private let config: MidgarConfig
    private let service = CatalogService()
    private lazy var telemetry = Telemetry(config: config)

    private var apps: [MidgarApp] = []
    private var impressed = Set<String>()
    private var didLoad = false
    private var isPresentingProduct = false

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, MidgarApp>!
    private let refreshControl = UIRefreshControl()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private lazy var emptyView = EmptyStateView(accent: config.resolvedAccent) { [weak self] in
        self?.handleRetry()
    }

    public init(config: MidgarConfig = .default) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.tintColor = config.resolvedAccent
        title = config.title
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        setupCollectionView()
        setupStateViews()
        Task { @MainActor in await load() }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            let section = Section(rawValue: index) ?? .all
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )

            switch section {
            case .featured:
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(0.86),
                        heightDimension: .absolute(FeaturedCardCell.preferredHeight)),
                    subitems: [item]
                )
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.interGroupSpacing = 12
                layoutSection.contentInsets = NSDirectionalEdgeInsets(
                    top: 0, leading: 0, bottom: 24, trailing: 0)
                layoutSection.boundarySupplementaryItems =
                    (self?.hasFeatured ?? false) ? [header] : []
                return layoutSection

            case .all:
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .estimated(92)))
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1), heightDimension: .estimated(92)),
                    subitems: [item]
                )
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.boundarySupplementaryItems =
                    (self?.hasFeatured ?? false) ? [header] : []
                return layoutSection
            }
        }
    }

    private var hasFeatured: Bool { apps.contains(where: \.featured) }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.refreshControl = refreshControl
        refreshControl.addAction(UIAction { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }, for: .valueChanged)
        view.addSubview(collectionView)

        let accent = config.resolvedAccent
        let featuredRegistration = UICollectionView.CellRegistration<FeaturedCardCell, MidgarApp> {
            cell, _, app in
            cell.configure(with: app, accent: accent)
        }
        let rowRegistration = UICollectionView.CellRegistration<AppRowCell, MidgarApp> {
            cell, _, app in
            cell.configure(with: app, accent: accent)
        }

        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView, indexPath, app in
            if Section(rawValue: indexPath.section) == .featured {
                return collectionView.dequeueConfiguredReusableCell(
                    using: featuredRegistration, for: indexPath, item: app)
            }
            return collectionView.dequeueConfiguredReusableCell(
                using: rowRegistration, for: indexPath, item: app)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self,
                  let section = self.dataSource.sectionIdentifier(for: indexPath.section)
            else { return }
            header.configure(title: section.title)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration, for: indexPath)
        }
    }

    private func setupStateViews() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = config.resolvedAccent
        view.addSubview(activityIndicator)

        emptyView.isHidden = true
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyView)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    @MainActor
    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        let cached = service.cachedSnapshot()
        if cached.isEmpty {
            activityIndicator.startAnimating()
        } else {
            apply(cached, animatingDifferences: false)
        }
        await refresh()
    }

    @MainActor
    private func refresh() async {
        let result = await service.build(config: config)
        refreshControl.endRefreshing()
        activityIndicator.stopAnimating()
        if result.apps.isEmpty {
            if apps.isEmpty {
                emptyView.isHidden = false
                UIAccessibility.post(notification: .screenChanged, argument: emptyView)
            }
        } else if !result.enriched && !apps.isEmpty {
            return
        } else {
            emptyView.isHidden = true
            apply(result.apps, animatingDifferences: !apps.isEmpty)
        }
    }

    @MainActor
    private func handleRetry() {
        emptyView.isHidden = true
        activityIndicator.startAnimating()
        Task { @MainActor in await refresh() }
    }

    /// Partitions into the two sections. An app appears in exactly one of them — a diffable data
    /// source treats a repeated item identifier across sections as a programmer error.
    private func apply(_ newApps: [MidgarApp], animatingDifferences: Bool) {
        apps = newApps
        let featured = newApps.filter(\.featured)
        let rest = newApps.filter { !$0.featured }

        var snapshot = NSDiffableDataSourceSnapshot<Section, MidgarApp>()
        if !featured.isEmpty {
            snapshot.appendSections([.featured])
            snapshot.appendItems(featured, toSection: .featured)
        }
        if !rest.isEmpty {
            snapshot.appendSections([.all])
            snapshot.appendItems(rest, toSection: .all)
        }
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func open(_ app: MidgarApp) {
        guard !isPresentingProduct, presentedViewController == nil else { return }
        isPresentingProduct = true
        telemetry.send(.tap, appId: app.appId)
        presentProduct(for: app)
    }

    private func presentProduct(for app: MidgarApp) {
        #if os(visionOS)
        isPresentingProduct = false
        UIApplication.shared.open(app.storeURL)
        #else
        let productViewController = SKStoreProductViewController()
        productViewController.delegate = self
        let parameters = [SKStoreProductParameterITunesItemIdentifier: app.appId]
        productViewController.loadProduct(withParameters: parameters) { [weak self] success, _ in
            guard let self else { return }
            if success {
                self.present(productViewController, animated: true)
            } else {
                self.isPresentingProduct = false
                UIApplication.shared.open(app.storeURL)
            }
        }
        #endif
    }

    private func registerImpression(_ app: MidgarApp) {
        guard impressed.insert(app.appId).inserted else { return }
        telemetry.send(.impression, appId: app.appId)
    }
}

extension MidgarStoreViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let app = dataSource.itemIdentifier(for: indexPath) else { return }
        open(app)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let app = dataSource.itemIdentifier(for: indexPath) else { return }
        registerImpression(app)
    }
}

extension MidgarStoreViewController: UICollectionViewDataSourcePrefetching {
    /// Warms the downsampled-image cache ahead of the scroll so a cell that scrolls into view
    /// usually has its artwork already decoded.
    public func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let scale = view.window?.screen.scale ?? traitCollection.displayScale
        for indexPath in indexPaths {
            guard let app = dataSource.itemIdentifier(for: indexPath) else { continue }
            let isFeatured = Section(rawValue: indexPath.section) == .featured
            Task { @MainActor in
                _ = await midgarLoadImage(app.iconURL, maxPixel: isFeatured ? 56 : 60, scale: scale)
                if isFeatured, let first = app.screenshotURLs.first {
                    _ = await midgarLoadImage(
                        first, maxPixel: FeaturedCardCell.preferredHeight, scale: scale)
                }
            }
        }
    }
}

#if !os(visionOS)
extension MidgarStoreViewController: @MainActor SKStoreProductViewControllerDelegate {
    public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        isPresentingProduct = false
        viewController.dismiss(animated: true)
    }
}
#endif
#endif
