#if canImport(UIKit)
import UIKit
import StoreKit

/// The storefront screen. Present it with ``Midgar/present(from:config:)``, embed
/// ``Midgar/makeStoreViewController(config:)``, or push this controller directly.
public final class MidgarStoreViewController: UIViewController {

    private let config: MidgarConfig
    private let service = CatalogService()
    private lazy var telemetry = Telemetry(config: config)

    private var apps: [MidgarApp] = []
    private var impressed = Set<String>()
    private var didLoad = false
    private var isPresentingProduct = false

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, MidgarApp>!
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

    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(240))
            )
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(240)),
                subitems: [item]
            )
            return NSCollectionLayoutSection(group: group)
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.refreshControl = refreshControl
        refreshControl.addAction(UIAction { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }, for: .valueChanged)
        view.addSubview(collectionView)

        let registration = UICollectionView.CellRegistration<AppCell, MidgarApp> { [weak self] cell, _, app in
            guard let self else { return }
            cell.configure(with: app, accent: self.config.resolvedAccent) { [weak self] in
                self?.open(app)
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, app in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: app)
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

    private func apply(_ newApps: [MidgarApp], animatingDifferences: Bool) {
        apps = newApps
        var snapshot = NSDiffableDataSourceSnapshot<Int, MidgarApp>()
        snapshot.appendSections([0])
        snapshot.appendItems(newApps, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func open(_ app: MidgarApp) {
        guard !isPresentingProduct, presentedViewController == nil else { return }
        isPresentingProduct = true
        telemetry.send(.tap, appId: app.appId)
        presentProduct(for: app)
    }

    private func presentProduct(for app: MidgarApp) {
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
    }

    private func registerImpression(_ app: MidgarApp) {
        guard impressed.insert(app.appId).inserted else { return }
        telemetry.send(.impression, appId: app.appId)
    }
}

extension MidgarStoreViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.item < apps.count else { return }
        open(apps[indexPath.item])
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.item < apps.count else { return }
        registerImpression(apps[indexPath.item])
    }
}

extension MidgarStoreViewController: @MainActor SKStoreProductViewControllerDelegate {
    public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        isPresentingProduct = false
        viewController.dismiss(animated: true)
    }
}
#endif
