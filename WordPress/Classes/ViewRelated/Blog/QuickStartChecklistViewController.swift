class QuickStartChecklistViewController: UITableViewController {
    private var dataSource: QuickStartChecklistDataSource? {
        didSet {
            self.tableView?.dataSource = dataSource
        }
    }
    private var dataManager: QuickStartChecklistManager? {
        didSet {
            tableView?.dataSource = dataManager
            tableView?.delegate = dataManager
        }
    }
    private var blog: Blog?
    private var list: [QuickStartTour] = []
    private var observer: NSObjectProtocol?

    @objc convenience init(blog: Blog) {
        self.init(blog: blog, list: QuickStartTourGuide.checklistTours)
    }

    convenience init(blog: Blog, list: [QuickStartTour]) {
        self.init()
        self.blog = blog
        self.list = list

        startObservingForQuickStart()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let tableView = UITableView(frame: .zero)

        let quickStartV2Enabled = Feature.enabled(.quickStartV2)

        if quickStartV2Enabled {
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 90.0
            tableView.tableFooterView = UIView(frame: .zero)
        } else {
            if #available(iOS 11, *) {
                tableView.estimatedRowHeight = UITableView.automaticDimension
            } else {
                tableView.estimatedRowHeight = WPTableViewDefaultRowHeight
            }

            let congratulationsNib = UINib(nibName: "QuickStartCongratulationsCell", bundle: Bundle(for: QuickStartCongratulationsCell.self))
            tableView.register(congratulationsNib, forCellReuseIdentifier: QuickStartCongratulationsCell.reuseIdentifier)
            let skipAllNib = UINib(nibName: "QuickStartSkipAllCell", bundle: Bundle(for: QuickStartSkipAllCell.self))
            tableView.register(skipAllNib, forCellReuseIdentifier: QuickStartSkipAllCell.reuseIdentifier)
        }

        self.tableView = tableView

        let nibName = quickStartV2Enabled ? "QuickStartChecklistCellV2" : "QuickStartChecklistCell"
        let cellNib = UINib(nibName: nibName, bundle: Bundle(for: QuickStartChecklistCell.self))
        tableView.register(cellNib, forCellReuseIdentifier: QuickStartChecklistCell.reuseIdentifier)

        guard let blog = blog else {
            return
        }
        if quickStartV2Enabled {
            dataManager = QuickStartChecklistManager(blog: blog, tours: list) { [weak self] analyticsKey in
                DispatchQueue.main.async {
                    self?.popViewController(analyticsKey: analyticsKey)
                }
            }
        } else {
            dataSource = QuickStartChecklistDataSource(blog: blog, tours: list)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if dataSource?.shouldShowCongratulations() ?? false {
            if let blog = blog {
                QuickStartTourGuide.find()?.complete(tour: QuickStartCongratulationsTour(), for: blog)
            }
        }

        WPAnalytics.track(.quickStartChecklistViewed)
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if let section = Sections(rawValue: indexPath.section) {
            switch section {
            case .congratulations:
                return nil
            case .checklistItems:
                guard let tour = dataSource?.tour(at: indexPath),
                    !(tour is QuickStartCreateTour) else {
                        return nil
                }
            case .skipAll:
                guard let blog = blog else {
                    return nil
                }
                QuickStartTourGuide.find()?.skipAll(for: blog) { [weak self] in
                    self?.reload()
                    self?.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                }
                return nil
            }
        }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let tourGuide = QuickStartTourGuide.find(),
            Sections(rawValue: indexPath.section) == .checklistItems,
            let blog = blog,
            let tour = dataSource?.tour(at: indexPath) else {
                return
        }
        tourGuide.start(tour: tour, for: blog)
        popViewController(analyticsKey: tour.analyticsKey)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    private func startObservingForQuickStart() {
        observer = NotificationCenter.default.addObserver(forName: .QuickStartTourElementChangedNotification, object: nil, queue: nil) { [weak self] (notification) in
            guard let userInfo = notification.userInfo,
                let element = userInfo[QuickStartTourGuide.notificationElementKey] as? QuickStartTourElement,
                element == .tourCompleted else {
                    return
            }

            self?.reload()
        }
    }

    private func reload() {
        if Feature.enabled(.quickStartV2) {
            dataManager?.reloadData()
        } else {
            dataSource?.loadCompletedTours()
        }
        tableView.reloadData()
    }

    private func popViewController(analyticsKey: String) {
        WPAnalytics.track(.quickStartChecklistItemTapped, withProperties: ["task_name": analyticsKey])
        navigationController?.popViewController(animated: true)
    }
}

private class QuickStartChecklistDataSource: NSObject, UITableViewDataSource {
    private var blog: Blog
    private var tours: [QuickStartTour]
    private var completedTours = Set<String>()

    init(blog: Blog, tours: [QuickStartTour]) {
        self.blog = blog
        self.tours = tours

        super.init()
        loadCompletedTours()
    }

    func loadCompletedTours() {
        guard let tours = blog.completedQuickStartTours else {
            return
        }

        completedTours = Set<String>()
        for tour in tours {
            completedTours.insert(tour.tourID)
        }
    }

    // managing tours

    func tour(at indexPath: IndexPath) -> QuickStartTour {
        return tours[indexPath.row]
    }

    func isCompleted(tour: QuickStartTour) -> Bool {
        return completedTours.contains(tour.key)
    }

    func shouldShowCongratulations() -> Bool {
        // TODO: fix this count implementation to be compatible with v2
        let completedToursCount = QuickStartTourGuide.countChecklistCompleted(for: blog)
        return completedToursCount >= tours.count
    }

    // UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Sections(rawValue: section) else {
            return 0
        }

        switch section {
        case .congratulations:
            if shouldShowCongratulations() {
                return 1
            } else {
                return 0
            }
        case .checklistItems:
            return tours.count
        case .skipAll:
            return shouldShowCongratulations() ? 0 : 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let section = Sections(rawValue: indexPath.section) {
            switch section {
            case .congratulations:
                if let cell = tableView.dequeueReusableCell(withIdentifier: QuickStartCongratulationsCell.reuseIdentifier) as? QuickStartCongratulationsCell {
                    return cell
                }
            case .checklistItems:
                if let cell = tableView.dequeueReusableCell(withIdentifier: QuickStartChecklistCell.reuseIdentifier) as? QuickStartChecklistCell {
                    let tour = tours[indexPath.row]
                    cell.tour = tour
                    cell.completed = isCompleted(tour: tour)
                    return cell
                }
            case .skipAll:
                if let cell = tableView.dequeueReusableCell(withIdentifier: QuickStartSkipAllCell.reuseIdentifier) as? QuickStartSkipAllCell {
                    return cell
                }
            }
        }
        return UITableViewCell()
    }
}

private enum Sections: Int {
    case congratulations = 0
    case checklistItems = 1
    case skipAll = 2
}
