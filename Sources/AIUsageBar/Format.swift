import AppKit
import Foundation

/// 메뉴에 표시할 문자열 포맷 유틸.
enum Format {
    static let barWidth = 10

    static func bar(_ pct: Double, width: Int = barWidth) -> String {
        let clamped = min(max(pct, 0), 100)
        let filled = Int((Double(width) * clamped / 100).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    static func percent(_ pct: Double) -> String {
        String(format: "%.0f%%", pct)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "E HH:mm"
        return f
    }()

    /// `2시간 10분 후` / `토 06:00` 형태의 리셋 시각.
    static func reset(_ date: Date?) -> String {
        guard let date else { return "알 수 없음" }
        let delta = date.timeIntervalSinceNow
        if delta <= 0 { return "곧" }
        if delta < 12 * 3600 {
            let minutes = Int(delta / 60)
            let (h, m) = (minutes / 60, minutes % 60)
            return h > 0 ? "\(h)시간 \(m)분 후" : "\(m)분 후"
        }
        return weekdayFormatter.string(from: date)
    }

    static func monthLabel(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f.string(from: date)
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 사용률에 따른 링 색: 초록 → 주황 → 빨강 → 흰색.
    static func statusColor(_ pct: Double) -> NSColor {
        switch pct {
        case 100...: return NSColor(srgbRed: 0.92, green: 0.92, blue: 0.96, alpha: 1)
        case 86...: return NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
        case 61...: return NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1)
        default: return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        }
    }
}

/// ISO8601 문자열을 Date 로. 소수점 이하 자릿수가 제각각이라 두 형식을 모두 시도한다.
enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return withFraction.date(from: string) ?? plain.date(from: string)
    }
}
