import AppKit

/// 메뉴바 항목 하나를 담당한다. 1분마다 사용량을 다시 읽어 링과 메뉴를 갱신한다.
///
/// 한 프로세스 안에서 `NSStatusItem` 을 여러 개 만들 수 있으므로, 파이썬 판과 달리
/// Claude / Codex 가 각각 별도 프로세스로 뜰 필요도, 이를 감시할 런처도 없다.
final class StatusItemController {
    private static let refreshInterval: TimeInterval = 60

    private let provider: UsageProvider
    private let statusItem: NSStatusItem
    private let queue: DispatchQueue
    private var timer: Timer?
    /// 외형이 바뀌었을 때 API 를 다시 부르지 않고 아이콘만 다시 그리기 위해 보관한다.
    private var lastResult: UsageResult?

    init(provider: UsageProvider) {
        self.provider = provider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.queue = DispatchQueue(label: "ai-usage-bar.\(provider.letter)", qos: .utility)

        statusItem.button?.title = " ⏳"
        statusItem.menu = NSMenu()

        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // 라이트/다크 전환 시 바깥 링의 무채색 톤을 뒤집어야 한다.
        // 다음 갱신(최대 1분)까지 기다리지 않도록 알림을 받아 즉시 다시 그린다.
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        refresh()
    }

    deinit {
        timer?.invalidate()
        DistributedNotificationCenter.default.removeObserver(self)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func appearanceChanged() {
        // 알림이 오는 시점에는 메뉴바 외형이 아직 바뀌지 않았을 수 있다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let result = self.lastResult else { return }
            self.apply(result)
        }
    }

    /// 메뉴바 배경이 어두운지. 시스템 외형 설정이 아니라 상태 아이템 버튼의
    /// 실제 외형을 본다. 배경화면 때문에 메뉴바만 어두워진 경우까지 반영된다.
    private var isDarkMenuBar: Bool {
        guard let appearance = statusItem.button?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    @objc private func manualRefresh() {
        refresh()
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.provider.fetch()
                DispatchQueue.main.async { self.apply(result) }
            } catch {
                let message = error.localizedDescription
                // 토큰 문제는 사용자가 조치할 수 있으니 종료 메뉴를 함께 남긴다.
                let showQuit = error is TokenError
                DispatchQueue.main.async { self.showError(message, withQuit: showQuit) }
            }
        }
    }

    // MARK: - 표시

    private func apply(_ result: UsageResult) {
        guard let button = statusItem.button else { return }
        lastResult = result
        button.image = RingIcon.make(
            pct: result.sessionPercent,
            elapsed: result.sessionElapsed,
            letter: provider.letter,
            isDark: isDarkMenuBar)
        button.imagePosition = .imageLeading
        button.title = " \(Format.percent(result.sessionPercent))"

        let menu = NSMenu()
        for row in result.rows { menu.addItem(item(for: row)) }
        menu.addItem(.separator())
        menu.addItem(action("지금 새로고침", #selector(manualRefresh)))
        menu.addItem(action("종료", #selector(NSApplication.terminate(_:)), target: NSApp))
        statusItem.menu = menu
    }

    private func showError(_ message: String, withQuit: Bool) {
        guard let button = statusItem.button else { return }
        // 직전 사용률 링이 ⚠️ 옆에 남지 않도록 아이콘을 지운다.
        button.image = nil
        lastResult = nil
        button.title = "\(provider.letter) ⚠️"

        let menu = NSMenu()
        menu.addItem(item(for: .text(message)))
        menu.addItem(.separator())
        menu.addItem(action("지금 새로고침", #selector(manualRefresh)))
        if withQuit {
            menu.addItem(action("종료", #selector(NSApplication.terminate(_:)), target: NSApp))
        }
        statusItem.menu = menu
    }

    // MARK: - 메뉴 항목 만들기

    private func item(for row: MenuRow) -> NSMenuItem {
        switch row {
        case .separator:
            return .separator()
        case .text(let title):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .mono(let title):
            // 막대가 위아래로 어긋나지 않도록 고정폭 글꼴로 그린다.
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
            )
            item.isEnabled = false
            return item
        }
    }

    private func action(_ title: String, _ selector: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target ?? self
        return item
    }
}
