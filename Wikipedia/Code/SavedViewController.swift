import WMFComponents

protocol SavedViewControllerDelegate: NSObjectProtocol {
    func savedWillShowSortAlert(_ saved: SavedViewController, from button: UIBarButtonItem)
    func saved(_ saved: SavedViewController, searchBar: UISearchBar, textDidChange searchText: String)
    func saved(_ saved: SavedViewController, searchBarSearchButtonClicked searchBar: UISearchBar)
    func saved(_ saved: SavedViewController, searchBarTextDidBeginEditing searchBar: UISearchBar)
    func saved(_ saved: SavedViewController, searchBarTextDidEndEditing searchBar: UISearchBar)
    func saved(_ saved: SavedViewController, scopeBarIndexDidChange searchBar: UISearchBar)
}

// Wrapper for accessing View in Objective-C
@objc class WMFSavedViewControllerView: NSObject {
    @objc static let readingListsViewRawValue = SavedViewController.View.readingLists.rawValue
}

@objc(WMFSavedViewController)
class SavedViewController: ThemeableViewController, WMFNavigationBarConfiguring {

    private var savedArticlesViewController: SavedArticlesCollectionViewController?
    
    @objc weak var tabBarDelegate: AppTabBarDelegate?
    
    private lazy var readingListsViewController: ReadingListsViewController? = {
        guard let dataStore = dataStore else {
            assertionFailure("dataStore is nil")
            return nil
        }
        let readingListsCollectionViewController = ReadingListsViewController(with: dataStore)
        return readingListsCollectionViewController
    }()

    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var progressContainerView: UIView!

    lazy var addReadingListBarButtonItem: UIBarButtonItem = {
        return SystemBarButton(with: .add, target: readingListsViewController.self, action: #selector(readingListsViewController?.presentCreateReadingListViewController))
    }()
    
    fileprivate lazy var savedProgressViewController: SavedProgressViewController? = SavedProgressViewController.wmf_initialViewControllerFromClassStoryboard()

    public weak var savedDelegate: SavedViewControllerDelegate?

    // MARK: - Initalization and setup
    
    @objc public var dataStore: MWKDataStore? {
        didSet {
            guard let newValue = dataStore else {
                assertionFailure("cannot set dataStore to nil")
                return
            }
            savedArticlesViewController = SavedArticlesCollectionViewController(with: newValue)
            savedArticlesViewController?.delegate = self
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    // MARK: - Toggling views
    
    enum View: Int {
        case savedArticles, readingLists
    }

    private(set) var currentView: View = .savedArticles {
        didSet {
            switch currentView {
            case .savedArticles:
                removeChild(readingListsViewController)
                setSavedArticlesViewControllerIfNeeded()
                addSavedChildViewController(savedArticlesViewController)
                savedArticlesViewController?.editController.navigationDelegate = self
                readingListsViewController?.editController.navigationDelegate = nil
                savedDelegate = savedArticlesViewController
                activeEditableCollection = savedArticlesViewController
                evaluateEmptyState()
                ReadingListsFunnel.shared.logTappedAllArticlesTab()
                if let searchBar = navigationItem.searchController?.searchBar {
                    searchBar.placeholder = "Search saved articles"
                }
            case .readingLists :
                removeChild(savedArticlesViewController)
                addSavedChildViewController(readingListsViewController)
                savedArticlesViewController?.editController.navigationDelegate = nil
                readingListsViewController?.editController.navigationDelegate = self
                savedDelegate = readingListsViewController
                activeEditableCollection = readingListsViewController
                evaluateEmptyState()
                ReadingListsFunnel.shared.logTappedReadingListsTab()
                if let searchBar = navigationItem.searchController?.searchBar {
                    searchBar.placeholder = "Search reading lists"
                }
            }
        }
    }

    private enum ExtendedNavBarViewType {
        case none
        case search
        case createNewReadingList
    }

    private var isCurrentViewEmpty: Bool {
        guard let activeEditableCollection = activeEditableCollection else {
            return true
        }
        return activeEditableCollection.editController.isCollectionViewEmpty
    }

    private var activeEditableCollection: EditableCollection?
    
    private func addSavedChildViewController(_ vc: UIViewController?) {
        guard let vc = vc else {
            return
        }
        addChild(vc)
        containerView.wmf_addSubviewWithConstraintsToEdges(vc.view)
        vc.didMove(toParent: self)
    }
    
    private func removeChild(_ vc: UIViewController?) {
        guard let vc = vc else {
            return
        }
        vc.view.removeFromSuperview()
        vc.willMove(toParent: nil)
        vc.removeFromParent()
    }

    private func logTappedView(_ view: View) {
        switch view {
        case .savedArticles:
            NavigationEventsFunnel.shared.logEvent(action: .savedAll)
        case .readingLists:
            NavigationEventsFunnel.shared.logEvent(action: .savedLists)
        }
    }
    
    // MARK: - View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        wmf_add(childController:savedProgressViewController, andConstrainToEdgesOfContainerView: progressContainerView)

        if activeEditableCollection == nil {
            currentView = .savedArticles
        }

        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        configureNavigationBar()
        
        let savedArticlesWasNil = savedArticlesViewController == nil
        setSavedArticlesViewControllerIfNeeded()
        if savedArticlesViewController != nil,
            currentView == .savedArticles,
            savedArticlesWasNil {
            // reassign so activeEditableCollection gets reset
            currentView = .savedArticles
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if #available(iOS 18, *) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
                    configureNavigationBar()
                }
            }
        }
    }
    
    private func configureNavigationBar() {
        
        var titleConfig: WMFNavigationBarTitleConfig = WMFNavigationBarTitleConfig(title: CommonStrings.savedTabTitle, customView: nil, alignment: .leadingCompact)
        if #available(iOS 18, *) {
            if UIDevice.current.userInterfaceIdiom == .pad && traitCollection.horizontalSizeClass == .regular {
                titleConfig = WMFNavigationBarTitleConfig(title: CommonStrings.savedTabTitle, customView: nil, alignment: .leadingLarge)
            }
        }
        
        let allArticlesButtonTitle = WMFLocalizedString("saved-all-articles-title", value: "All articles", comment: "Title of the all articles button on Saved screen")
        let readingListsButtonTitle = WMFLocalizedString("saved-reading-lists-title", value: "Reading lists", comment: "Title of the reading lists button on Saved screen")
        
        let searchConfig = WMFNavigationBarSearchConfig(searchResultsController: nil, searchControllerDelegate: nil, searchResultsUpdater: nil, searchBarDelegate: self, searchBarPlaceholder: WMFLocalizedString("saved-search-default-text", value:"Search saved articles", comment:"Placeholder text for the search bar in Saved"), showsScopeBar: true, scopeButtonTitles: [allArticlesButtonTitle, readingListsButtonTitle])

        configureNavigationBar(titleConfig: titleConfig, closeButtonConfig: nil, profileButtonConfig: nil, searchBarConfig: searchConfig, hideNavigationBarOnScroll: true)
    }
    
    private func setSavedArticlesViewControllerIfNeeded() {
        if let dataStore = dataStore,
            savedArticlesViewController == nil {
            savedArticlesViewController = SavedArticlesCollectionViewController(with: dataStore)
            savedArticlesViewController?.delegate = self
            savedArticlesViewController?.apply(theme: theme)
        }
    }
    
    private func evaluateEmptyState() {
        if activeEditableCollection == nil {
            wmf_showEmptyView(of: .noSavedPages, theme: theme, frame: view.bounds)
        } else {
            wmf_hideEmptyView()
        }
    }
    
    // MARK: - Themeable
    
    override func apply(theme: Theme) {
        super.apply(theme: theme)
        guard viewIfLoaded != nil else {
            return
        }
        view.backgroundColor = theme.colors.chromeBackground
        
        savedArticlesViewController?.apply(theme: theme)
        readingListsViewController?.apply(theme: theme)
        savedProgressViewController?.apply(theme: theme)

        addReadingListBarButtonItem.tintColor = theme.colors.link
        
        themeNavigationBarLeadingTitleView()
        
        if let rightBarButtonItems = navigationItem.rightBarButtonItems {
            for barButtonItem in rightBarButtonItems {
                barButtonItem.tintColor = theme.colors.link
            }
        }
    }
    
    private lazy var sortBarButtonItem: UIBarButtonItem = {
        return UIBarButtonItem(title: CommonStrings.sortActionTitle, style: .plain, target: self, action: #selector(didTapSort(_:)))
    }()
    
    private lazy var fixedSpaceBarButtonItem: UIBarButtonItem = {
        let button = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        button.width = 20
        return button
    }()
    
    @objc func didTapSort(_ sender: UIBarButtonItem) {
        savedDelegate?.savedWillShowSortAlert(self, from: sender)
    }
}

// MARK: - NavigationDelegate

extension SavedViewController: CollectionViewEditControllerNavigationDelegate {
    var currentTheme: Theme {
        return self.theme
    }
    
    func didChangeEditingState(from oldEditingState: EditingState, to newEditingState: EditingState, rightBarButton: UIBarButtonItem?, leftBarButton: UIBarButtonItem?) {

        let editButton = rightBarButton
        let sortBarButtonItem = self.sortBarButtonItem
        sortBarButtonItem.tintColor = theme.colors.link
        editButton?.tintColor = theme.colors.link
        
        navigationItem.rightBarButtonItems = [editButton, fixedSpaceBarButtonItem, sortBarButtonItem].compactMap {$0}
        
        let editingStates: [EditingState] = [.swiping, .open, .editing]
        let isEditing = editingStates.contains(newEditingState)
        if newEditingState == .open,
            let batchEditToolbar = savedArticlesViewController?.editController.batchEditToolbarView,
            let contentView = containerView,
            let appTabBar = tabBarDelegate?.tabBar {
                accessibilityElements = [batchEditToolbar, contentView, appTabBar]
        } else {
            accessibilityElements = []
        }
        guard isEditing else {
            return
        }
        
        ReadingListsFunnel.shared.logTappedEditButton()
    }
    
    func newEditingState(for currentEditingState: EditingState, fromEditBarButtonWithSystemItem systemItem: UIBarButtonItem.SystemItem) -> EditingState {
        let newEditingState: EditingState
        
        switch currentEditingState {
        case .open:
            newEditingState = .closed
        default:
            newEditingState = .open
        }
        
        return newEditingState
    }
    
    func emptyStateDidChange(_ empty: Bool) {
        if empty {
            
        } else {
            
        }
    }
}

// MARK: - UISearchBarDelegate

extension SavedViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        savedDelegate?.saved(self, searchBar: searchBar, textDidChange: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        savedDelegate?.saved(self, searchBarSearchButtonClicked: searchBar)
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        savedDelegate?.saved(self, searchBarTextDidBeginEditing: searchBar)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        savedDelegate?.saved(self, searchBarTextDidEndEditing: searchBar)
    }
    
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        if selectedScope == 0 {
            currentView = .savedArticles
        } else {
            currentView = .readingLists
        }
        logTappedView(currentView)
        
        searchBar.text = nil
        savedDelegate?.saved(self, scopeBarIndexDidChange: searchBar)
    }
}

extension SavedViewController: ReadingListEntryCollectionViewControllerDelegate {
    func setupReadingListDetailHeaderView(_ headerView: ReadingListDetailHeaderView) {
        assertionFailure("Unexpected")
    }
    
    func readingListEntryCollectionViewController(_ viewController: ReadingListEntryCollectionViewController, didUpdate collectionView: UICollectionView) {
    }
    
    func readingListEntryCollectionViewControllerDidChangeEmptyState(_ viewController: ReadingListEntryCollectionViewController) {
    }
    
    func readingListEntryCollectionViewControllerDidSelectArticleURL(_ articleURL: URL, viewController: ReadingListEntryCollectionViewController) {
        navigate(to: articleURL)
    }
    
}
