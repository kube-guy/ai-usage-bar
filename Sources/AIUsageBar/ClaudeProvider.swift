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

    private let expiredMessage = "토큰이 만료되었습니다. 터미널에서 `claude`를 실행해 갱신해주세요."

    // MARK: - 인증

    private func accessToken() throws -> String {
        let user = NSUserName()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", user, "-w", "-s", keychainService]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw TokenError(message: "security 명령을 실행할 수 없습니다.")
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TokenError(message: "로그인 정보를 찾을 수 없습니다. 터미널에서 `claude` 실행 후 로그인해주세요.")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
            let token = json.dict("claudeAiOauth").string("accessToken"),
            !token.isEmpty
        else {
            throw TokenError(message: "Keychain 데이터 형식을 해석할 수 없습니다.")
        }
        return token
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

        for key in ["plan", "planName", "subscriptionType", "tier"] {
            if let value = data.string(key), !value.isEmpty { return value.capitalized }
        }
        let account = data.dict("account")
        for key in ["plan", "planName", "subscriptionType"] {
            if let value = account.string(key), !value.isEmpty { return value.capitalized }
        }
        return "알 수 없음"
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
        let token = try accessToken()
        let usage = try HTTP.getJSON(
            url: usageURL, headers: headers(token), unauthorizedMessage: expiredMessage
        )
        let plan = planName(token)
        let stats = scanLocalStats()

        // usage API 는 리셋 시각만 주고 창 길이는 주지 않는다. 이름 그대로 5시간으로 본다.
        let sessionWindowSeconds: Double = 5 * 3600
        let fiveHour = usage.dict("five_hour")
        let sevenDay = usage.dict("seven_day")
        let sessionPct = fiveHour.double("utilization")
        let weeklyPct = sevenDay.double("utilization")

        var rows: [MenuRow] = [
            .text("Plan: \(plan)"),
            .separator,
            .text("Plan limits"),
            .mono("  Current session   \(Format.bar(sessionPct))  \(Format.percent(sessionPct))"),
            .text("    resets in \(Format.reset(ISODate.parse(fiveHour.string("resets_at"))))"),
            .mono("  Weekly limits     \(Format.bar(weeklyPct))  \(Format.percent(weeklyPct))"),
            .text("    resets \(Format.reset(ISODate.parse(sevenDay.string("resets_at"))))"),
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
            sessionElapsed: elapsedFraction(resetsAt: resetsAt, windowSeconds: sessionWindowSeconds),
            rows: rows)
    }
}
