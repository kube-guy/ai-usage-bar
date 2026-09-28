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

    private static func koreanFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    private static let clockFormatter = koreanFormatter("HH:mm")
    private static let weekdayFormatter = koreanFormatter("E HH:mm")
    private static let dayFormatter = koreanFormatter("M/d HH:mm")

    /// `26분 후` / `2시간 10분 후` / `3일 19시간 후` — 리셋까지 남은 시간.
    static func resetRemaining(_ date: Date?) -> String {
        guard let date else { return "알 수 없음" }
        let delta = date.timeIntervalSinceNow
        if delta < 60 { return "곧" }
        let minutes = Int(delta / 60)
        let (hours, m) = (minutes / 60, minutes % 60)
        if hours < 24 {
            return hours > 0 ? "\(hours)시간 \(m)분 후" : "\(m)분 후"
        }
        let (days, h) = (hours / 24, hours % 24)
        return h > 0 ? "\(days)일 \(h)시간 후" : "\(days)일 후"
    }

    /// `오늘 12:36` / `내일 07:00` / `화 07:00` / `10/5 07:00` — 리셋되는 실제 시각.
    /// 남은 시간만으로는 "몇 시에 풀리나"를 셈해야 하므로 옆에 함께 적는다.
    static func resetClock(_ date: Date?) -> String {
        // 이미 지난 시각을 옆에 적으면 오히려 헷갈린다. 그때는 '곧' 만 남긴다.
        guard let date, date.timeIntervalSinceNow > 0 else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "오늘 " + clockFormatter.string(from: date) }
        if calendar.isDateInTomorrow(date) { return "내일 " + clockFormatter.string(from: date) }
        // 요일만 적으면 8일 뒤와 헷갈리므로 한 주를 넘어가면 날짜로 적는다.
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)).day ?? 0
        return days < 7 ? weekdayFormatter.string(from: date) : dayFormatter.string(from: date)
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
