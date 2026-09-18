import Foundation

/// Codex CLI 사용량 (5시간 세션 / 7일 주간 한도).
///
/// 전제 조건:
///   - Codex CLI 가 설치되어 있고 `codex` 명령으로 ChatGPT 계정 로그인이 되어 있어야 한다.
///     (로그인하면 ~/.codex/auth.json 에 토큰이 저장된다.)
///   - API 키 모드(OPENAI_API_KEY)로만 쓰는 경우는 이 사용량 정보를 제공하지 않는다.
///
/// 데이터 출처: https://chatgpt.com/backend-api/wham/usage
/// (Codex CLI 자신이 /status 표시에 쓰는 것과 같은, 비공식이지만 실제로 쓰이는 엔드포인트)
struct CodexProvider: UsageProvider {
    let letter = "X"
    let name = "Codex CLI"

    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private var authPath: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
    }

    private let expiredMessage = "토큰이 만료되었습니다. 터미널에서 `codex`를 한 번 실행해 로그인을 갱신해주세요."

    private func auth() throws -> (token: String, accountID: String?) {
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            throw TokenError(message:
                "Codex 로그인 정보를 찾을 수 없습니다. 터미널에서 `codex` 실행 후 ChatGPT 계정으로 로그인해주세요.")
        }
        guard
            let data = try? Data(contentsOf: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw TokenError(message: "auth.json을 읽을 수 없습니다.")
        }

        let tokens = json.dict("tokens")
        let token = tokens.string("access_token") ?? tokens.string("accessToken")
        let accountID = tokens.string("account_id") ?? tokens.string("accountId")

        guard let token, !token.isEmpty else {
            throw TokenError(message: "액세스 토큰이 비어 있습니다. 터미널에서 `codex` 실행 후 다시 로그인해주세요.")
        }
        return (token, accountID)
    }

    /// 유닉스 타임스탬프(초)를 Date 로.
    private func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double, seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int, seconds > 0 { return Date(timeIntervalSince1970: Double(seconds)) }
        return nil
    }

    func fetch() throws -> UsageResult {
        let (token, accountID) = try auth()
        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
        ]
        if let accountID { headers["chatgpt-account-id"] = accountID }

        let data = try HTTP.getJSON(url: usageURL, headers: headers, unauthorizedMessage: expiredMessage)

        let plan = (data.string("plan_type") ?? "알 수 없음").capitalized
        let rateLimit = data.dict("rate_limit")
        let primary = rateLimit.dict("primary_window")      // 5시간
        let secondary = rateLimit.dict("secondary_window")  // 7일

        let sessionPct = primary.double("used_percent")
        let weeklyPct = secondary.double("used_percent")

        var rows: [MenuRow] = [
            .text("Plan: \(plan)"),
            .separator,
            .text("Plan limits"),
            .mono("  Current session   \(Format.bar(sessionPct))  \(Format.percent(sessionPct))"),
            .text("    resets in \(Format.reset(date(primary["reset_at"])))"),
            .mono("  Weekly limits     \(Format.bar(weeklyPct))  \(Format.percent(weeklyPct))"),
            .text("    resets \(Format.reset(date(secondary["reset_at"])))"),
        ]

        let credits = data.dict("credits")
        if credits["has_credits"] as? Bool == true {
            let unlimited = credits["unlimited"] as? Bool == true
            let balance = credits.double("balance")
            rows += [
                .separator,
                .text(unlimited ? "Credits: 무제한" : String(format: "Credits: $%.2f", balance)),
            ]
        }

        return UsageResult(sessionPercent: sessionPct, rows: rows)
    }
}
