import Foundation

/// 로그인 정보가 없거나 만료된 경우.
struct TokenError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 사용량 엔드포인트 호출이 실패한 경우.
struct NetworkError: LocalizedError {
    let message: String
    var errorDescription: String? { "네트워크 오류: \(message)" }
}

/// 메뉴에 들어가는 한 줄.
enum MenuRow {
    case text(String)
    /// 막대 그래프가 들어가 자릿수가 맞아야 하는 줄 — 고정폭 글꼴로 그린다.
    case mono(String)
    case separator
}

struct UsageResult {
    /// 메뉴바 링에 표시할 5시간 세션 사용률.
    let sessionPercent: Double
    /// 현재 세션 창이 얼마나 지났는지 0~1. 창 길이를 알 수 없으면 nil.
    /// 안쪽 링(사용률)과 같은 방향으로 차오르도록 '남은' 이 아니라 '지난' 비율이다.
    let sessionElapsed: Double?
    let rows: [MenuRow]
}

/// 리셋 시각과 창 길이로 '창이 얼마나 지났는지'를 구한다.
/// 리셋 직후 0 에서 시작해 리셋 직전 1 이 된다.
func elapsedFraction(resetsAt: Date?, windowSeconds: Double) -> Double? {
    guard let resetsAt, windowSeconds > 0 else { return nil }
    let remaining = resetsAt.timeIntervalSinceNow
    guard remaining.isFinite else { return nil }
    return min(max(1 - remaining / windowSeconds, 0), 1)
}

protocol UsageProvider {
    /// 링 가운데 글자.
    var letter: String { get }
    /// 상태 아이템 식별용 이름.
    var name: String { get }
    /// 네트워크와 디스크를 모두 건드리므로 백그라운드 큐에서 호출된다.
    func fetch() throws -> UsageResult
}

// MARK: - 공통 HTTP

enum HTTP {
    /// URLSession 은 비동기라 세마포어로 동기화한다 (호출부가 이미 백그라운드 큐).
    static func getJSON(
        url: URL,
        headers: [String: String],
        timeout: TimeInterval = 10,
        unauthorizedMessage: String
    ) throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var data: Data?
        var response: URLResponse?
        var error: Error?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) {
            data = $0
            response = $1
            error = $2
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 5)

        if let error {
            throw NetworkError(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, let data else {
            throw NetworkError(message: "응답이 없습니다.")
        }
        if http.statusCode == 401 {
            throw TokenError(message: unauthorizedMessage)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError(message: "HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError(message: "응답을 JSON으로 해석할 수 없습니다.")
        }
        return json
    }
}

// MARK: - JSON 편의 접근자

extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func double(_ key: String) -> Double {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        return 0
    }
    func string(_ key: String) -> String? { self[key] as? String }
}
