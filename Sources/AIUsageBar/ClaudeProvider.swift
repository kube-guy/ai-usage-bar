import Foundation

/// Claude Code 사용량.
///
/// - 세션/주간 한도(%)      : https://api.anthropic.com/api/oauth/usage  (Keychain 토큰)
/// - 메시지 수 / 모델별 통계 : ~/.claude/projects/**/*.jsonl  (로컬 파일만 읽음, 전송 없음)
///
/// 토큰은 `security` CLI 로 읽는다. Security 프레임워크를 직접 쓰면 서명되지 않은
/// 이 바이너리에 대해 키체인 접근 승인 창이 새로 뜨지만, `security` 는 이미 승인돼 있다.
struct ClaudeProvider: UsageProvider {
    let letter = "C"
    let name = "Claude Code"

    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private let keychainService = "Claude Code-credentials"
    private let userAgent = "claude-code/2.1.220"
    /// 항상 이 순서/이름으로 고정 표시 (데이터가 없으면 0으로 표시)
    private let modelFamilies = ["opus", "sonnet", "haiku"]

    /// usage 엔드포인트는 1분마다 부르면 429 (`Retry-After: 3600`) 로 막힌다.
    /// 한도 수치는 이 간격으로만 새로 받고, 로컬 통계는 매 갱신마다 다시 센다.
    private let usageMinInterval: TimeInterval = 5 * 60
    /// 프로세스가 살아 있는 동안 API 응답을 들고 있는다. 갱신은 provider 의 전용 큐에서
    /// 일어나지만 --dump 등 다른 경로도 있으니 잠금을 둔다.
    private let cache = APICache()
    /// 토큰 갱신이 안 될 때 `claude` 를 다시 띄우기까지의 간격.
    private let refreshMinInterval: TimeInterval = 5 * 60

    private let expiredMessage = "토큰이 만료되었습니다. 터미널에서 `claude`를 실행해 갱신해주세요."

    // MARK: - 인증

    /// Keychain 에 든 토큰과 만료 시각. 만료 시각을 못 읽으면 nil.
    private func credentials() throws -> (token: String, expiresAt: Date?) {
        let user = NSUserName()
        let (status, output) = try run(
            URL(fileURLWithPath: "/usr/bin/security"),
            ["find-generic-password", "-a", user, "-w", "-s", keychainService])

        guard status == 0 else {
            throw TokenError(message: "로그인 정보를 찾을 수 없습니다. 터미널에서 `claude` 실행 후 로그인해주세요.")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
            let token = json.dict("claudeAiOauth").string("accessToken"),
            !token.isEmpty
        else {
            throw TokenError(message: "Keychain 데이터 형식을 해석할 수 없습니다.")
        }
        // expiresAt 은 밀리초 단위 유닉스 시각이다.
        let millis = json.dict("claudeAiOauth").double("expiresAt")
        return (token, millis > 0 ? Date(timeIntervalSince1970: millis / 1000) : nil)
    }

    /// access token 은 약 8시간이면 만료되고, 갱신은 `claude` 를 실행해야 일어난다.
    /// 만료됐으면 Claude Code 에 갱신을 맡긴 뒤 Keychain 을 다시 읽는다.
    /// refresh token 은 쓰면 바뀌므로 이 앱이 직접 갱신하지 않는다 — Claude Code 와 엇갈려 로그아웃될 수 있다.
    private func accessToken() throws -> String {
        let current = try credentials()
        guard let expiresAt = current.expiresAt, expiresAt <= Date().addingTimeInterval(60) else {
            return current.token
        }
        guard refreshViaCLI() else { return current.token }
        let refreshed = try credentials()
        log("토큰 갱신 시도: 만료 \(expiresAt) → \(refreshed.expiresAt.map { "\($0)" } ?? "알 수 없음")")
        return refreshed.token
    }

    /// 표준 에러로 남긴다. brew services 로 뜨면 로그 파일로 간다.
    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[\(Date())] \(message)\n".utf8))
    }

    /// `claude -p` 로 아주 짧은 요청을 보내 Claude Code 가 토큰을 갱신하게 한다.
    /// `claude auth status` 는 상태만 읽고 갱신하지 않는다 (실측). 모델을 불러야 갱신이 일어나므로
    /// 가장 가벼운 모델에 도구·MCP·설정 없이 보내고, 메시지 수 통계가 늘지 않게 세션도 남기지 않는다.
    /// 실패해도 매 분 다시 띄우지 않도록 시도 간격을 둔다. 실행했으면 true.
    @discardableResult
    private func refreshViaCLI() -> Bool {
        cache.lock.lock()
        let now = Date()
        if let last = cache.lastRefreshAttempt, now.timeIntervalSince(last) < refreshMinInterval {
            cache.lock.unlock()
            return false
        }
        cache.lastRefreshAttempt = now
        cache.lock.unlock()

        guard let claude = claudeExecutable() else { return false }
        let arguments = [
            "-p", "ok", "--model", "haiku", "--no-session-persistence",
            "--tools", "", "--strict-mcp-config", "--setting-sources", "",
        ]
        let result = try? run(claude, arguments, timeout: 60, in: FileManager.default.temporaryDirectory)
        log("`claude -p` 실행: 종료 코드 \(result.map { "\($0.0)" } ?? "실행 실패")")
        return result != nil
    }

    /// launchd 로 뜨면 PATH 가 짧아서 `claude` 를 못 찾는다. 설치 위치를 직접 찾아본다.
    private func claudeExecutable() -> URL? {
        let home = NSHomeDirectory()
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"] + pathDirs
        return candidates
            .map { URL(fileURLWithPath: $0).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// 명령을 실행하고 종료 코드와 표준 출력을 돌려준다. 시간을 넘기면 끊는다.
    private func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval = 10, in directory: URL? = nil
    ) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw TokenError(message: "\(executable.lastPathComponent) 명령을 실행할 수 없습니다.")
        }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return (process.terminationStatus, output)
    }

    private func headers(_ token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": userAgent,
            "Accept": "application/json",
        ]
    }

    /// 비공식 profile 엔드포인트에서 플랜 이름을 얻어본다. 실패하면 '알 수 없음'.
    private func planName(_ token: String) -> String {
        guard let data = try? HTTP.getJSON(
            url: profileURL, headers: headers(token), unauthorizedMessage: expiredMessage
        ) else { return "알 수 없음" }

        // organization_type: "claude_max" / "claude_pro" …
        // rate_limit_tier:   "default_claude_max_5x" 처럼 배수까지 들어 있다.
        let organization = data.dict("organization")
        let type = organization.string("organization_type") ?? ""
        guard type.hasPrefix("claude_") else { return "알 수 없음" }
        var plan = String(type.dropFirst("claude_".count)).capitalized
        if let tier = organization.string("rate_limit_tier"),
           let multiplier = tier.split(separator: "_").last, multiplier.hasSuffix("x"),
           Int(multiplier.dropLast()) != nil {
            plan += " \(multiplier)"
        }
        return plan
    }

    private final class APICache {
        let lock = NSLock()
        var usage: [String: Any]?
        var usageFetchedAt: Date?
        /// 429 의 Retry-After 가 가리키는 시각. 그 전에는 usage 를 부르지 않는다.
        var blockedUntil: Date?
        var plan: String?
        /// 수동 새로고침 직후 한 번은 간격과 429 대기를 무시하고 바로 부른다.
        var forceNext = false
        /// 마지막으로 `claude` 에 토큰 갱신을 맡긴 시각.
        var lastRefreshAttempt: Date?
    }

    /// 직전 응답은 지우지 않는다. 다시 429 를 받아도 그 값을 보여줄 수 있어야 한다.
    /// 다시 로그인하면 계정이 바뀌었을 수 있으니 플랜도 새로 묻는다.
    func invalidateCache() {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        cache.forceNext = true
        cache.plan = nil
    }

    /// 한도 수치를 돌려준다. 간격이 안 됐거나 429 로 막혀 있으면 직전 응답을 쓴다.
    /// 두 번째 값은 직전 응답을 쓴 경우 그 응답을 받은 시각.
    private func usage(_ token: String) throws -> ([String: Any], staleSince: Date?) {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        let now = Date()
        let force = cache.forceNext
        cache.forceNext = false

        if force {
            // 아래에서 바로 부른다.
        } else if let cached = cache.usage, let fetchedAt = cache.usageFetchedAt {
            let blocked = cache.blockedUntil.map { now < $0 } ?? false
            if blocked || now.timeIntervalSince(fetchedAt) < usageMinInterval {
                return (cached, blocked ? fetchedAt : nil)
            }
        } else if let until = cache.blockedUntil, now < until {
            throw RateLimitError(retryAt: until)
        }

        do {
            let fresh = try HTTP.getJSON(
                url: usageURL, headers: headers(token), unauthorizedMessage: expiredMessage)
            cache.usage = fresh
            cache.usageFetchedAt = now
            cache.blockedUntil = nil
            return (fresh, nil)
        } catch let error as RateLimitError {
            // Retry-After 가 없으면 최소 간격만큼은 쉰다.
            cache.blockedUntil = error.retryAt ?? now.addingTimeInterval(usageMinInterval)
            guard let cached = cache.usage, let fetchedAt = cache.usageFetchedAt else { throw error }
            return (cached, fetchedAt)
        }
    }

    /// 플랜은 거의 바뀌지 않으니 한 번 알아내면 계속 쓴다. 실패했을 때만 다음 갱신에 다시 묻는다.
    private func cachedPlanName(_ token: String) -> String {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let plan = cache.plan { return plan }
        let plan = planName(token)
        if plan != "알 수 없음" { cache.plan = plan }
        return plan
    }

    /// 창이 이미 리셋됐다면 직전 응답의 사용률은 0 으로 본다.
    private func utilization(_ window: [String: Any]) -> Double {
        if let resetsAt = ISODate.parse(window.string("resets_at")), resetsAt <= Date() { return 0 }
        return window.double("utilization")
    }

    // MARK: - 로컬 JSONL 통계

    private struct LocalStats {
        var lifetimeTotal = 0
        var monthTotal = 0
        var weekTotal = 0
        var todayTotal = 0
        var todaySessions = Set<String>()
        var monthByFamily: [String: Int] = [:]
    }

    private func modelFamily(_ model: String) -> String {
        let lower = model.lowercased()
        for family in modelFamilies where lower.contains(family) { return family }
        return "기타"
    }

    private func scanLocalStats() -> LocalStats {
        var stats = LocalStats()
        for family in modelFamilies { stats.monthByFamily[family] = 0 }

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now

        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return stats }

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
                guard
                    let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    entry.string("type") == "assistant",
                    let timestamp = ISODate.parse(entry.string("timestamp"))
                else { continue }

                stats.lifetimeTotal += 1
                if timestamp >= weekAgo { stats.weekTotal += 1 }
                if timestamp >= monthStart {
                    stats.monthTotal += 1
                    let model = entry.dict("message").string("model") ?? "unknown"
                    stats.monthByFamily[modelFamily(model), default: 0] += 1
                }
                if calendar.startOfDay(for: timestamp) == today {
                    stats.todayTotal += 1
                    if let session = entry.string("sessionId") { stats.todaySessions.insert(session) }
                }
            }
        }
        return stats
    }

    // MARK: - 조합

    func fetch() throws -> UsageResult {
        var token = try accessToken()
        let usage: [String: Any], staleSince: Date?
        do {
            (usage, staleSince) = try self.usage(token)
        } catch is TokenError {
            // 만료 시각 전에 401 이 올 수도 있다 (다른 기기에서 다시 로그인 등). 한 번만 갱신해 본다.
            guard refreshViaCLI() else { throw TokenError(message: expiredMessage) }
            token = try credentials().token
            (usage, staleSince) = try self.usage(token)
        }
        let plan = cachedPlanName(token)
        let stats = scanLocalStats()

        // usage API 는 리셋 시각만 주고 창 길이는 주지 않는다. 이름 그대로 5시간으로 본다.
        let sessionWindowSeconds: Double = 5 * 3600
        let fiveHour = usage.dict("five_hour")
        let sevenDay = usage.dict("seven_day")
        let sessionPct = utilization(fiveHour)
        let weeklyPct = utilization(sevenDay)

        let minutesAgo = staleSince.map { max(Int(Date().timeIntervalSince($0) / 60), 0) }
        var rows: [MenuRow] = [
            .text("Plan: \(plan)"),
            .separator,
            .text("한도" + (minutesAgo.map { "  (요청 한도 초과로 \($0)분 전 값)" } ?? "")),
            .gauge(
                label: "5시간 세션", usedPct: sessionPct,
                resetsAt: ISODate.parse(fiveHour.string("resets_at"))),
            .gauge(
                label: "주간 (7일)", usedPct: weeklyPct,
                resetsAt: ISODate.parse(sevenDay.string("resets_at"))),
            .separator,
            .text("Models this month:"),
        ]

        let familyTotal = max(stats.monthByFamily.values.reduce(0, +), 1)
        for family in modelFamilies {
            let count = stats.monthByFamily[family] ?? 0
            let share = 100.0 * Double(count) / Double(familyTotal)
            let label = family.capitalized.padding(toLength: 16, withPad: " ", startingAt: 0)
            rows.append(.mono(
                "  \(label) \(Format.bar(share))  \(Format.percent(share))   \(Format.count(count)) msgs"
            ))
        }

        rows += [
            .separator,
            .text("Claude Code \(Format.monthLabel())"),
            .text("  이번 달: \(Format.count(stats.monthTotal)) messages"),
            .text("  오늘: \(Format.count(stats.todayTotal)) messages · \(stats.todaySessions.count) sessions"),
            .text("  최근 7일: \(Format.count(stats.weekTotal)) messages"),
            .text("  전체: \(Format.count(stats.lifetimeTotal)) messages"),
        ]

        let resetsAt = ISODate.parse(fiveHour.string("resets_at"))
        return UsageResult(
            sessionPercent: sessionPct,
            weeklyPercent: weeklyPct,
            weeklyElapsed: elapsedFraction(
                resetsAt: ISODate.parse(sevenDay.string("resets_at")), windowSeconds: 7 * 24 * 3600),
            sessionElapsed: elapsedFraction(resetsAt: resetsAt, windowSeconds: sessionWindowSeconds),
            rows: rows)
    }
}
